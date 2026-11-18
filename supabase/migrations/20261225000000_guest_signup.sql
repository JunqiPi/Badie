-- 球群的访客报名（iPhone 1.0.7，需求见 Badie-iOS/docs/GUEST_SIGNUP.md）：
-- 组织者打开“允许不注册的人报名”后有一个报名链接 badie.rsvp/g/<guest_code>/（和 6 位群号分开，可以重置）。
-- 没有账号的人在网页上填名字报名或候补。名额和候补只有一份逻辑：访客也是 session_signups 的一行（user_id 为空）。
-- - 每场访客最多 guest_limit 人（空 = 这一场名额的一半），候补里的访客也算：所以递补时谁排第一就补谁，不用跳过
-- - 取消凭证明文只在报名时返回一次，库里存哈希；报名走 guest-signup 函数（先核对 Turnstile），每个 IP 每小时最多 10 次
-- - 访客没有账号：不发推送，留了邮箱的发邮件（递补、场次取消、解散）
-- - 旧版 App：group_page 的 players 里也有访客（id 是这一行报名的 id，多 "guest": true），人数照算

create extension if not exists pgcrypto with schema extensions;

alter table public.play_groups
  add column guests_allowed boolean not null default false,
  add column guest_limit smallint check (guest_limit between 1 and 40),
  add column guest_code text unique;

-- 报名的主键改成独立的 id（访客没有 user_id）；一个人同一场还是只能报一次
alter table public.session_signups drop constraint session_signups_pkey;
alter table public.session_signups
  add column id uuid not null default gen_random_uuid() primary key,
  alter column user_id drop not null,
  add column guest_name text check (char_length(guest_name) between 2 and 20),
  add column guest_email text check (char_length(guest_email) <= 254),
  add column guest_locale text check (char_length(guest_locale) <= 10),
  add column guest_token_hash text unique,
  add constraint session_signups_session_user_key unique (session_id, user_id),
  add constraint session_signups_member_or_guest check (
    (user_id is not null and guest_name is null and guest_token_hash is null)
    or (user_id is null and guest_name is not null and guest_token_hash is not null));

-- 访客报名的 IP（哈希），一小时后删掉，只用来限次
create table public.guest_signup_ips (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  at timestamptz not null default now()
);
create index guest_signup_ips_ip_idx on public.guest_signup_ips (ip_hash, at);
alter table public.guest_signup_ips enable row level security;
revoke all on public.guest_signup_ips from anon, authenticated;
grant all on public.guest_signup_ips to service_role;

-- ---------------------------------------------------------------------------
-- 内部工具
-- ---------------------------------------------------------------------------

create function public.guest_token_hash(p_token text)
returns text language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
$$;

-- 8 位，大小写字母、数字和 - _（48 位随机数，猜不到）
create function public.new_guest_code()
returns text language sql volatile set search_path = '' as $$
  select translate(encode(extensions.gen_random_bytes(6), 'base64'), '+/', '-_')
$$;

-- 这一场最多几个访客：组织者设的数（不超过名额）；没设是名额的一半，至少 1 个
create function public.guest_cap(p_limit smallint, p_capacity smallint)
returns int language sql immutable set search_path = '' as $$
  select least(coalesce(p_limit, greatest(p_capacity / 2, 1)), p_capacity)
$$;

-- 给一行访客报名写一封邮件（没留邮箱返回 null）：按报名时的网页语言，p_link 放在正文后面
create function public.guest_email(p_signup uuid, p_subject text, p_body text, p_link text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'to', su.guest_email,
    'subject', public.render_text(x.locale, p_subject, x.params),
    'text', concat_ws(E'\n\n', public.render_text(x.locale, p_body, x.params), p_link,
                      E'—\n' || public.render_text(x.locale, 'You get this because you left your email when you signed up on Badie.')))
  from public.session_signups su
  join public.group_sessions gs on gs.id = su.session_id
  join public.play_groups g on g.id = gs.group_id
  cross join lateral (select coalesce(su.guest_locale, 'en') as locale,
                             public.slot(gs.starts_at, coalesce(gs.venue_id, g.venue_id)) || jsonb_build_object('group', g.name) as params) x
  where su.id = p_signup and su.guest_email is not null
$$;

-- 发给访客的邮件（数组里的 null 跳过）。地址和暗号和约球邮件一样，没配就不发
create function public.send_guest_emails(p_emails jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  url text;
  secret text;
  emails jsonb := (select jsonb_agg(e || jsonb_build_object('from', 'Badie <games@badie.rsvp>'))
                   from jsonb_array_elements(coalesce(p_emails, '[]')) e where jsonb_typeof(e) = 'object');
begin
  if emails is null then return; end if;
  select decrypted_secret into url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_secret';
  if url is null or secret is null then return; end if;
  perform net.http_post(url := rtrim(url, '/') || '/functions/v1/send-email', body := emails,
                        headers := jsonb_build_object('x-push-secret', secret, 'Content-Type', 'application/json'));
end
$$;

-- 报上或候补后的确认邮件：只有这时有明文凭证，带取消链接
create function public.send_guest_confirmation(p_signup uuid, p_token text)
returns void language sql security definer set search_path = '' as $$
  select public.send_guest_emails(jsonb_build_array(public.guest_email(
    su.id, case when su.waitlisted then 'You’re on the waitlist: {group}' else 'You’re signed up: {group}' end,
    '{when} · {court}. If you can’t make it, cancel here:', 'https://badie.rsvp/g/' || g.guest_code || '/?cancel=' || p_token)))
  from public.session_signups su
  join public.group_sessions gs on gs.id = su.session_id
  join public.play_groups g on g.id = gs.group_id
  where su.id = p_signup
$$;

-- 删掉一行访客报名：删的是已报上、还没开场的，候补递补
create function public.drop_guest_signup(p_signup uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.group_sessions;
  was_waitlisted boolean;
begin
  select gs.* into s from public.session_signups su join public.group_sessions gs on gs.id = su.session_id
    where su.id = p_signup and su.user_id is null;
  if s.id is null then raise exception 'signup_not_found' using errcode = 'P0002'; end if;
  perform 1 from public.group_sessions where id = s.id and cancelled_at is null and ends_at > now() for update;
  if not found then raise exception 'session_closed' using errcode = 'P0002'; end if;
  delete from public.session_signups where id = p_signup returning waitlisted into was_waitlisted;
  if not was_waitlisted and s.starts_at > now() then perform public.promote_waitlist(s.id); end if;
end
$$;

revoke execute on function public.guest_token_hash(text), public.new_guest_code(), public.guest_cap(smallint, smallint),
  public.guest_email(uuid, text, text, text), public.send_guest_emails(jsonb), public.send_guest_confirmation(uuid, text),
  public.drop_guest_signup(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 访客（网页，不登录）
-- ---------------------------------------------------------------------------

-- 报名页：只在开着访客报名时返回。报名的人只给名字（注册用户是昵称），不给 id、头像、等级、邮箱。
-- p_tokens：这台设备上存的取消凭证，对上的那一行标 "me"
create function public.guest_group_page(p_code text, p_tokens text[] default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  g public.play_groups;
  mine text[] := (select coalesce(array_agg(public.guest_token_hash(t)), '{}') from unnest(p_tokens[1:50]) t);
begin
  select * into g from public.play_groups where guest_code = p_code and guests_allowed;
  if g.id is null then return null; end if;
  perform public.ensure_sessions(g.id);
  return jsonb_build_object(
    'group_id', g.id, 'name', g.name, 'summary', g.summary,
    'organizer', (select nickname from public.profiles where id = g.owner_id),
    'venue', (select jsonb_build_object('name', v.name, 'city', v.city) from public.venues v where v.id = g.venue_id),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'starts_at', s.starts_at, 'ends_at', s.ends_at, 'capacity', s.capacity, 'cancelled', s.cancelled_at is not null,
        'venue', v.name, 'city', v.city, 'tz', v.time_zone_id,
        'guest_spots', public.guest_cap(g.guest_limit, s.capacity) - (select count(*) from public.session_signups su
                                                                       where su.session_id = s.id and su.user_id is null),
        'players', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce(p.nickname, su.guest_name), 'guest', su.user_id is null,
                                                                  'waitlisted', su.waitlisted, 'me', coalesce(su.guest_token_hash = any(mine), false))
                                              order by su.waitlisted, su.signed_up_at), '[]')
                    from public.session_signups su left join public.profiles p on p.id = su.user_id
                    where su.session_id = s.id and (su.user_id is null or p.id is not null)))
        order by s.starts_at)
      from public.group_sessions s join public.venues v on v.id = coalesce(s.venue_id, g.venue_id)
      where s.group_id = g.id and s.ends_at > now() and s.starts_at < now() + interval '14 days'), '[]'));
end
$$;

-- 报名（只给 guest-signup 函数调：它先核对人机验证、带上 IP）。返回 {status: confirmed / waitlisted, position, token}
create function public.guest_sign_up(p_code text, p_session uuid, p_name text, p_email text, p_locale text, p_ip text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  clean_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  clean_email text := nullif(lower(btrim(p_email)), '');
  ip text := public.guest_token_hash(coalesce(p_ip, ''));
  token text := translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_');
  s record;
  is_full boolean;
  signup uuid;
begin
  select gs.id, gs.capacity, gs.starts_at, gs.cancelled_at, g.guest_limit into s
    from public.group_sessions gs join public.play_groups g on g.id = gs.group_id
    where gs.id = p_session and g.guest_code = p_code and g.guests_allowed
    for update of gs;
  if s.id is null then raise exception 'guests_off' using errcode = 'P0002'; end if;
  if s.cancelled_at is not null or s.starts_at <= now() then raise exception 'session_closed' using errcode = 'P0002'; end if;
  if char_length(clean_name) not between 2 and 20 then raise exception 'invalid_guest_name' using errcode = '22023'; end if;
  if clean_name ~* '(https?:|www\.|@|\d{5,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
  if public.has_offensive(clean_name) then raise exception 'objectionable_content' using errcode = '22023'; end if;
  if clean_email is not null and (char_length(clean_email) > 254 or clean_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'invalid_email' using errcode = '22023';
  end if;

  -- 每个 IP 每小时最多报 10 次（出错的那次整个回滚，不算）
  delete from public.guest_signup_ips where ip_hash = ip and at < now() - interval '1 hour';
  if (select count(*) from public.guest_signup_ips where ip_hash = ip) >= 10 then
    raise exception 'too_many_signups' using errcode = '54000';
  end if;
  insert into public.guest_signup_ips (ip_hash) values (ip);

  if (select count(*) from public.session_signups where session_id = p_session and user_id is null) >= public.guest_cap(s.guest_limit, s.capacity) then
    raise exception 'guest_spots_full' using errcode = '54000';
  end if;
  is_full := (select count(*) from public.session_signups where session_id = p_session and not waitlisted) >= s.capacity;
  insert into public.session_signups (session_id, waitlisted, guest_name, guest_email, guest_locale, guest_token_hash)
    values (p_session, is_full, clean_name, clean_email, nullif(left(btrim(p_locale), 10), ''), public.guest_token_hash(token))
    returning id into signup;
  perform public.send_guest_confirmation(signup, token);
  return jsonb_build_object(
    'status', case when is_full then 'waitlisted' else 'confirmed' end,
    'position', case when is_full then (select count(*) from public.session_signups where session_id = p_session and waitlisted) end,
    'token', token);
end
$$;

-- 报名后补填或改邮箱（空 = 不要邮件）；填了就发一封带取消链接的确认邮件
create function public.guest_set_email(p_token text, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  clean_email text := nullif(lower(btrim(p_email)), '');
  signup uuid;
begin
  if clean_email is not null and (char_length(clean_email) > 254 or clean_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'invalid_email' using errcode = '22023';
  end if;
  update public.session_signups set guest_email = clean_email where guest_token_hash = public.guest_token_hash(p_token) returning id into signup;
  if signup is null then raise exception 'signup_not_found' using errcode = 'P0002'; end if;
  if clean_email is not null then perform public.send_guest_confirmation(signup, p_token); end if;
end
$$;

-- 访客取消（凭证在报名的那台设备上或确认邮件里）。访客没有账号，不记临时取消
create function public.guest_cancel(p_token text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  signup uuid := (select id from public.session_signups where guest_token_hash = public.guest_token_hash(p_token));
begin
  if signup is null then raise exception 'signup_not_found' using errcode = 'P0002'; end if;
  perform public.drop_guest_signup(signup);
end
$$;

-- ---------------------------------------------------------------------------
-- 组织者
-- ---------------------------------------------------------------------------

-- 开关访客报名、改每场上限（null = 名额的一半）。第一次打开时生成链接；关掉后链接打不开，已经报上的访客保留
create function public.set_guest_signup(p_group uuid, p_allowed boolean, p_limit int default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_organizer(p_group, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  if p_limit is not null and p_limit not between 1 and 40 then raise exception 'invalid_guest_limit' using errcode = '22023'; end if;
  update public.play_groups
    set guests_allowed = coalesce(p_allowed, false), guest_limit = p_limit,
        guest_code = coalesce(guest_code, case when p_allowed then public.new_guest_code() end)
    where id = p_group;
end
$$;

-- 换一个链接，旧的马上失效（已经报上的访客不受影响，凭证照样能取消）
create function public.reset_guest_link(p_group uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  code text;
begin
  if not public.is_organizer(p_group, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  update public.play_groups set guest_code = public.new_guest_code() where id = p_group returning guest_code into code;
  return code;
end
$$;

-- 把访客移出某一场（和移出成员一样，候补递补）
create function public.remove_guest(p_signup uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_organizer((select gs.group_id from public.session_signups su join public.group_sessions gs on gs.id = su.session_id
                              where su.id = p_signup and su.user_id is null), auth.uid()) then
    raise exception 'not_organizer' using errcode = '42501';
  end if;
  perform public.drop_guest_signup(p_signup);
end
$$;

revoke execute on function public.guest_group_page(text, text[]), public.guest_sign_up(text, uuid, text, text, text, text),
  public.guest_set_email(text, text), public.guest_cancel(text), public.set_guest_signup(uuid, boolean, int),
  public.reset_guest_link(uuid), public.remove_guest(uuid) from public, anon, authenticated;
grant execute on function public.guest_group_page(text, text[]), public.guest_set_email(text, text), public.guest_cancel(text)
  to anon, authenticated;
grant execute on function public.set_guest_signup(uuid, boolean, int), public.reset_guest_link(uuid), public.remove_guest(uuid) to authenticated;
grant execute on function public.guest_sign_up(text, uuid, text, text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 原有的函数认访客行
-- ---------------------------------------------------------------------------

-- 递补：按报名这一行的 id 补（访客没有 user_id）；补上的是访客就发邮件
create or replace function public.promote_waitlist(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  promoted public.session_signups;
begin
  -- 锁住场次：两个人同时退出时只递补一次、不会补错人
  perform 1 from public.group_sessions where id = p_session for update;
  select gs.id, gs.group_id, gs.starts_at, gs.capacity, g.name, g.guest_code, coalesce(gs.venue_id, g.venue_id) as court into s
    from public.group_sessions gs join public.play_groups g on g.id = gs.group_id where gs.id = p_session;
  if (select count(*) from public.session_signups where session_id = p_session and not waitlisted) >= s.capacity then return; end if;
  update public.session_signups set waitlisted = false
    where session_id = p_session and waitlisted and id = (select id from public.session_signups where session_id = p_session and waitlisted
                                                          order by signed_up_at limit 1)
    returning * into promoted;
  if promoted.user_id is not null then
    perform public.notify(promoted.user_id, 'group', 'You’re in: {group}', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.',
      '/app/groups/' || s.group_id || '/', public.slot(s.starts_at, s.court) || jsonb_build_object('group', s.name));
  elsif promoted.id is not null then
    perform public.send_guest_emails(jsonb_build_array(public.guest_email(promoted.id, 'You’re in: {group}',
      'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', 'https://badie.rsvp/g/' || s.guest_code || '/')));
  end if;
end
$$;

-- 取消场次：留了邮箱的访客也收到邮件
create or replace function public.cancel_session(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  player record;
begin
  select gs.id, gs.group_id, gs.starts_at, g.name, coalesce(gs.venue_id, g.venue_id) as court into s
    from public.group_sessions gs join public.play_groups g on g.id = gs.group_id
    where gs.id = p_session and gs.cancelled_at is null and gs.starts_at > now();
  if s.id is null then raise exception 'session_closed' using errcode = 'P0002'; end if;
  if not public.is_organizer(s.group_id, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  update public.group_sessions set cancelled_at = now() where id = p_session;
  for player in select user_id from public.session_signups where session_id = p_session and user_id <> auth.uid() loop
    perform public.notify(player.user_id, 'group', 'Session cancelled: {group}',
      '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '/app/groups/' || s.group_id || '/',
      public.slot(s.starts_at, s.court) || jsonb_build_object('group', s.name));
  end loop;
  perform public.send_guest_emails((select jsonb_agg(public.guest_email(su.id, 'Session cancelled: {group}',
                                                                        '{when} · {court} was cancelled by the organizer. Nothing counts against you.', null))
                                    from public.session_signups su where su.session_id = p_session and su.guest_email is not null));
end
$$;

-- 解散：以后场次里留了邮箱的访客也收到邮件
create or replace function public.disband_group(p_group uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.play_groups;
  member record;
begin
  select * into g from public.play_groups where id = p_group for update;
  if g.id is null then raise exception 'group_not_found' using errcode = 'P0002'; end if;
  if g.owner_id <> auth.uid() then raise exception 'not_organizer' using errcode = '42501'; end if;
  for member in select user_id from public.group_members where group_id = p_group and user_id <> g.owner_id and not pending loop
    perform public.notify(member.user_id, 'group', 'Group closed: {group}', 'The organizer closed {group}.', null,
      jsonb_build_object('group', g.name));
  end loop;
  perform public.send_guest_emails((select jsonb_agg(public.guest_email(su.id, 'Group closed: {group}', 'The organizer closed {group}.', null))
                                    from public.session_signups su join public.group_sessions gs on gs.id = su.session_id
                                    where gs.group_id = p_group and gs.starts_at > now() and gs.cancelled_at is null
                                      and su.guest_email is not null));
  delete from public.play_groups where id = p_group;
end
$$;

-- 球群页：players 里也有访客（id 是报名这一行的 id，"guest": true，带报名时间），旧版 App 照样解得开、人数照算；
-- 组织者多看到访客报名的设置（guests_allowed、guest_limit、guest_code）
create or replace function public.group_page(p_group uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  role text := public.group_role_of(p_group, me);
  member boolean := role in ('owner', 'organizer', 'member');
  organizer boolean := role in ('owner', 'organizer');
begin
  if me is null or not exists (select 1 from public.play_groups g where g.id = p_group and not public.blocked_between(me, g.owner_id)) then
    return null;
  end if;
  perform public.ensure_sessions(p_group);
  return public.group_summary(p_group) || jsonb_build_object(
    'invite_code', case when member then (select invite_code from public.play_groups where id = p_group) end,
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'starts_at', s.starts_at, 'ends_at', s.ends_at, 'capacity', s.capacity, 'cancelled', s.cancelled_at is not null,
        'venue', coalesce(s.venue_id, g.venue_id),
        'confirmed', (select count(*) from public.session_signups su where su.session_id = s.id and not su.waitlisted),
        'waitlist', (select count(*) from public.session_signups su where su.session_id = s.id and su.waitlisted),
        'my_status', (select case when not su.waitlisted then 'confirmed'
                                  else 'waitlisted:' || (select count(*) from public.session_signups w
                                                         where w.session_id = s.id and w.waitlisted and w.signed_up_at <= su.signed_up_at) end
                      from public.session_signups su where su.session_id = s.id and su.user_id = me),
        'players', case when member then (select jsonb_agg(jsonb_build_object('id', coalesce(su.user_id, su.id), 'nickname', coalesce(p.nickname, su.guest_name),
                                                                              'waitlisted', su.waitlisted, 'guest', su.user_id is null,
                                                                              'signed_up_at', su.signed_up_at)
                                                           order by su.waitlisted, su.signed_up_at)
                                          from public.session_signups su left join public.profiles p on p.id = su.user_id
                                          where su.session_id = s.id and (su.user_id is null or p.id is not null)) end)
        order by s.starts_at)
      from public.group_sessions s join public.play_groups g on g.id = s.group_id
      where s.group_id = p_group and s.ends_at > now() and s.starts_at < now() + interval '14 days'), '[]'),
    'members', case when member then (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'role', m.role)
                                                       order by m.role, lower(p.nickname))
                                      from public.group_members m join public.profiles p on p.id = m.user_id
                                      where m.group_id = p_group and not m.pending) end,
    'pending', case when organizer then (
        select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) order by m.joined_at), '[]')
        from public.group_members m join public.profiles p on p.id = m.user_id where m.group_id = p_group and m.pending) end,
    'guests_allowed', case when organizer then (select guests_allowed from public.play_groups where id = p_group) end,
    'guest_limit', case when organizer then (select guest_limit from public.play_groups where id = p_group) end,
    'guest_code', case when organizer then (select guest_code from public.play_groups where id = p_group) end);
end
$$;

-- 每小时删掉一小时前的 IP 记录；结束超过一天的场次不再留访客的邮箱
select cron.schedule('guest-signup-ips', '17 * * * *', $$delete from public.guest_signup_ips where at < now() - interval '1 hour'$$);
select cron.schedule('guest-emails', '27 * * * *', $$
  update public.session_signups su set guest_email = null from public.group_sessions gs
  where gs.id = su.session_id and su.guest_email is not null and gs.ends_at < now() - interval '1 day'$$);

-- 邮件译文（递补、取消、解散的邮件沿用通知的译文）
insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', 'You’re signed up: {group}', '已报名：{group}'),
  ('zh-Hans', 'You’re on the waitlist: {group}', '已候补：{group}'),
  ('zh-Hans', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court}。去不了的话，在这里取消：'),
  ('zh-Hans', 'You get this because you left your email when you signed up on Badie.', '你在 Badie 报名时留了邮箱，所以收到这封邮件。'),
  ('zh-Hant', 'You’re signed up: {group}', '已報名：{group}'),
  ('zh-Hant', 'You’re on the waitlist: {group}', '已候補：{group}'),
  ('zh-Hant', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court}。去不了的話，在這裡取消：'),
  ('zh-Hant', 'You get this because you left your email when you signed up on Badie.', '你在 Badie 報名時留了電郵，所以收到這封郵件。'),
  ('ja', 'You’re signed up: {group}', '申し込みました：{group}'),
  ('ja', 'You’re on the waitlist: {group}', 'キャンセル待ちに入りました：{group}'),
  ('ja', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court}。行けなくなったら、こちらからキャンセルできます：'),
  ('ja', 'You get this because you left your email when you signed up on Badie.', 'Badie で申し込むときにメールアドレスを入力したため、このメールが届いています。'),
  ('ko', 'You’re signed up: {group}', '신청했어요: {group}'),
  ('ko', 'You’re on the waitlist: {group}', '대기 명단에 올랐어요: {group}'),
  ('ko', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court}. 못 가게 되면 여기서 취소하세요:'),
  ('ko', 'You get this because you left your email when you signed up on Badie.', 'Badie에서 신청할 때 이메일을 남겨서 이 메일을 받았어요.'),
  ('hi', 'You’re signed up: {group}', 'आपका नाम लिख लिया गया: {group}'),
  ('hi', 'You’re on the waitlist: {group}', 'आप वेटलिस्ट में हैं: {group}'),
  ('hi', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court}। अगर आना न हो पाए, तो यहाँ कैंसिल करें:'),
  ('hi', 'You get this because you left your email when you signed up on Badie.', 'आपने Badie पर नाम लिखवाते समय अपना ईमेल दिया था, इसलिए यह ईमेल आया है।'),
  ('id', 'You’re signed up: {group}', 'Kamu sudah daftar: {group}'),
  ('id', 'You’re on the waitlist: {group}', 'Kamu masuk daftar tunggu: {group}'),
  ('id', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court}. Kalau tidak bisa datang, batalkan di sini:'),
  ('id', 'You get this because you left your email when you signed up on Badie.', 'Kamu menerima email ini karena mencantumkan email saat mendaftar di Badie.'),
  ('ms', 'You’re signed up: {group}', 'Anda sudah mendaftar: {group}'),
  ('ms', 'You’re on the waitlist: {group}', 'Anda dalam senarai menunggu: {group}'),
  ('ms', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court}. Jika anda tidak dapat hadir, batalkan di sini:'),
  ('ms', 'You get this because you left your email when you signed up on Badie.', 'Anda menerima e-mel ini kerana memberikan e-mel semasa mendaftar di Badie.'),
  ('th', 'You’re signed up: {group}', 'ลงชื่อแล้ว: {group}'),
  ('th', 'You’re on the waitlist: {group}', 'อยู่ในคิวสำรองแล้ว: {group}'),
  ('th', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court} ถ้าไปไม่ได้ ยกเลิกได้ที่นี่:'),
  ('th', 'You get this because you left your email when you signed up on Badie.', 'คุณได้รับอีเมลนี้เพราะใส่อีเมลไว้ตอนลงชื่อใน Badie'),
  ('vi', 'You’re signed up: {group}', 'Bạn đã đăng ký: {group}'),
  ('vi', 'You’re on the waitlist: {group}', 'Bạn đang trong danh sách chờ: {group}'),
  ('vi', '{when} · {court}. If you can’t make it, cancel here:', '{when} · {court}. Nếu không đi được, hủy tại đây:'),
  ('vi', 'You get this because you left your email when you signed up on Badie.', 'Bạn nhận được email này vì đã để lại email khi đăng ký trên Badie.')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
