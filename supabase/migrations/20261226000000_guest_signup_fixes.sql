-- 访客报名上线前补的（Badie-iOS/docs/GUEST_SIGNUP.md “1.0.7 上线后要补的”）：
-- 2. 注册后在球群页报名：这台设备上有同一场的访客凭证时，把那一行改成自己的，不占两个位子
-- 3. 组织者移出访客：留了邮箱的发一封“你不在名单上了”
-- 4. 递补、改时间的邮件带取消链接：发信时换一个新凭证（session_signups.guest_mail_token_hash，库里只存哈希；
--    报名那台设备上的凭证照样能用）。1.0.8 的付款提醒邮件也用它
-- 5. 开场前 24 小时内有人退出、候补里又没人：通知组织者（只有这种时候）
-- 7. 注册用户可以在公开报名页上只显示名字首字母（profiles.public_initials，默认关）
-- 8. 访客开场前 2 小时内退出也记一笔临时取消（session_late_cancels 多 guest_name），组织者在名单下面看得到谁临时退了
-- 9. 报名页上结束的场次多留 1 天（写“已结束”）；清访客邮箱改成一个函数，1.0.8 收款时只改这个函数
-- 10. 改每周场次的时间（或名额、费用、球馆）：同一个星期几的改在原来那一行上，已经生成的场次跟着改、报名保留，
--     报了名的人收到“场次有变”（不再是“取消”加重新报名）
-- 11. 同一场同名的访客：后报的写成 “Tony 2”

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

alter table public.session_signups add column guest_mail_token_hash text unique;

alter table public.profiles add column public_initials boolean not null default false;
grant update (public_initials) on public.profiles to authenticated;

-- 临时取消也记访客（没有 user_id，记名字）
alter table public.session_late_cancels drop constraint session_late_cancels_pkey;
alter table public.session_late_cancels
  add column id bigint generated always as identity primary key,
  alter column user_id drop not null,
  add column guest_name text check (char_length(guest_name) between 2 and 20),
  add constraint session_late_cancels_session_user_key unique (session_id, user_id),
  add constraint session_late_cancels_member_or_guest check ((user_id is null) <> (guest_name is null));

-- ---------------------------------------------------------------------------
-- 内部工具
-- ---------------------------------------------------------------------------

-- 凭证对应的那一行报名：报名时给这台设备的，或者最近一封邮件里的
create function public.guest_signup_by_token(p_token text)
returns uuid language sql stable set search_path = '' as $$
  select id from public.session_signups
  where guest_token_hash = public.guest_token_hash(p_token) or guest_mail_token_hash = public.guest_token_hash(p_token)
  limit 1
$$;

-- 给邮件里的取消链接发一个新凭证（明文只在这封邮件里）；上一封邮件的链接随之失效
create function public.new_guest_mail_token(p_signup uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  token text := translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_');
begin
  update public.session_signups set guest_mail_token_hash = public.guest_token_hash(token) where id = p_signup;
  return token;
end
$$;

-- 公开页上的首字母：“Tony Bao” → “T. B.”
create function public.initials(p_name text)
returns text language sql immutable set search_path = '' as $$
  select string_agg(upper(left(w, 1)) || '.', ' ' order by n)
  from regexp_split_to_table(btrim(p_name), '\s+') with ordinality as x (w, n)
  where w <> ''
$$;

-- 访客的邮件多一个 p_params（和这一场的时间、球馆、群名一起填，比如改时间前的 {old}）
drop function public.guest_email(uuid, text, text, text);
create function public.guest_email(p_signup uuid, p_subject text, p_body text, p_link text, p_params jsonb default '{}')
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
                             public.slot(gs.starts_at, coalesce(gs.venue_id, g.venue_id)) || jsonb_build_object('group', g.name) || p_params as params) x
  where su.id = p_signup and su.guest_email is not null
$$;

-- 开场前 24 小时内有人退出、候补里又没人补上：告诉组织者，好去群里找人。平时报名、取消都不通知
create function public.notify_open_spot(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify(m.user_id, 'group', 'Spot open: {group}',
                        '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.',
                        '/app/groups/' || s.group_id || '/',
                        public.slot(s.starts_at, coalesce(s.venue_id, g.venue_id))
                          || jsonb_build_object('group', g.name, 'n', c.confirmed, 'total', s.capacity))
  from public.group_sessions s
  join public.play_groups g on g.id = s.group_id
  cross join lateral (select count(*) filter (where not su.waitlisted) as confirmed, count(*) filter (where su.waitlisted) as waiting
                      from public.session_signups su where su.session_id = s.id) c
  join public.group_members m on m.group_id = s.group_id and m.role in ('owner', 'organizer') and not m.pending
  where s.id = p_session and s.cancelled_at is null and s.starts_at > now() and s.starts_at < now() + interval '24 hours'
    and c.confirmed < s.capacity and c.waiting = 0 and m.user_id is distinct from auth.uid();
end
$$;

-- 场次结束一天后不再留访客的邮箱。1.0.8 收款时改这里（开了收款的场次留到付清或结束后 7 天，先到为准）
create function public.forget_guest_emails()
returns void language sql security definer set search_path = '' as $$
  update public.session_signups su set guest_email = null from public.group_sessions gs
  where gs.id = su.session_id and su.guest_email is not null and gs.ends_at < now() - interval '1 day'
$$;
select cron.schedule('guest-emails', '27 * * * *', 'select public.forget_guest_emails()');

revoke execute on function public.guest_signup_by_token(text), public.new_guest_mail_token(uuid), public.initials(text),
  public.guest_email(uuid, text, text, text, jsonb), public.notify_open_spot(uuid), public.forget_guest_emails()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 访客
-- ---------------------------------------------------------------------------

-- 报名页：结束的场次多留 1 天（网页上写“已结束”）；注册用户选了只显示首字母的，名单上是首字母；
-- 邮件里的凭证也能认出自己
create or replace function public.guest_group_page(p_code text, p_tokens text[] default '{}')
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
        'players', (select coalesce(jsonb_agg(jsonb_build_object(
                                      'name', case when su.user_id is null then su.guest_name
                                                   when p.public_initials then public.initials(p.nickname) else p.nickname end,
                                      'guest', su.user_id is null, 'waitlisted', su.waitlisted,
                                      'me', coalesce(su.guest_token_hash = any(mine) or su.guest_mail_token_hash = any(mine), false))
                                    order by su.waitlisted, su.signed_up_at), '[]')
                    from public.session_signups su left join public.profiles p on p.id = su.user_id
                    where su.session_id = s.id and (su.user_id is null or p.id is not null)))
        order by s.starts_at)
      from public.group_sessions s join public.venues v on v.id = coalesce(s.venue_id, g.venue_id)
      where s.group_id = g.id and s.ends_at > now() - interval '1 day' and s.starts_at < now() + interval '14 days'), '[]'));
end
$$;

-- 报名：同一场已经有同名的访客，后报的写成 “Tony 2”（名单里分得清）。其余同上一版
create or replace function public.guest_sign_up(p_code text, p_session uuid, p_name text, p_email text, p_locale text, p_ip text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  clean_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  clean_email text := nullif(lower(btrim(p_email)), '');
  ip text := public.guest_token_hash(coalesce(p_ip, ''));
  token text := translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_');
  s record;
  is_full boolean;
  signup uuid;
  n int := 2;
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
  if exists (select 1 from public.session_signups where session_id = p_session and lower(guest_name) = lower(clean_name)) then
    while exists (select 1 from public.session_signups
                  where session_id = p_session and lower(guest_name) = lower(rtrim(left(clean_name, 19 - length(n::text))) || ' ' || n)) loop
      n := n + 1;
    end loop;
    clean_name := rtrim(left(clean_name, 19 - length(n::text))) || ' ' || n;
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

-- 补填或改邮箱：邮件里的凭证也行
create or replace function public.guest_set_email(p_token text, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  clean_email text := nullif(lower(btrim(p_email)), '');
  signup uuid := public.guest_signup_by_token(p_token);
begin
  if clean_email is not null and (char_length(clean_email) > 254 or clean_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'invalid_email' using errcode = '22023';
  end if;
  if signup is null then raise exception 'signup_not_found' using errcode = 'P0002'; end if;
  update public.session_signups set guest_email = clean_email where id = signup;
  if clean_email is not null then perform public.send_guest_confirmation(signup, p_token); end if;
end
$$;

-- 访客取消：开场前 2 小时内退出也记一笔临时取消（组织者看得到）；24 小时内退出、没人补上时通知组织者
create or replace function public.guest_cancel(p_token text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r record;
begin
  select su.id, su.session_id, su.guest_name, su.waitlisted, gs.starts_at into r
    from public.session_signups su join public.group_sessions gs on gs.id = su.session_id
    where su.id = public.guest_signup_by_token(p_token);
  if r.id is null then raise exception 'signup_not_found' using errcode = 'P0002'; end if;
  perform public.drop_guest_signup(r.id);
  if r.waitlisted then return; end if;
  if r.starts_at - now() < interval '2 hours' then
    insert into public.session_late_cancels (session_id, guest_name) values (r.session_id, r.guest_name);
  end if;
  perform public.notify_open_spot(r.session_id);
end
$$;

-- ---------------------------------------------------------------------------
-- 成员和组织者
-- ---------------------------------------------------------------------------

-- 报名：多一个 p_guest_token（网页上这台设备报这一场时存的访客凭证）。对得上就把那一行访客报名改成自己的，
-- 名额和候补的位置不变，不会一人占两个位子。旧版 App 不传，照旧
drop function public.sign_up_session(uuid);
create function public.sign_up_session(p_session uuid, p_guest_token text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  s public.group_sessions;
  is_full boolean;
begin
  select * into s from public.group_sessions where id = p_session and cancelled_at is null and starts_at > now() for update;
  if s.id is null then raise exception 'session_closed' using errcode = 'P0002'; end if;
  if public.group_role_of(s.group_id, me) is null or public.group_role_of(s.group_id, me) = 'pending' then
    raise exception 'not_member' using errcode = '42501';
  end if;
  if exists (select 1 from public.session_signups where session_id = p_session and user_id = me) then
    return (select case when waitlisted then 'waitlisted' else 'confirmed' end from public.session_signups where session_id = p_session and user_id = me);
  end if;
  update public.session_signups
    set user_id = me, guest_name = null, guest_email = null, guest_locale = null, guest_token_hash = null, guest_mail_token_hash = null
    where id = public.guest_signup_by_token(p_guest_token) and session_id = p_session
    returning waitlisted into is_full;
  if found then return case when is_full then 'waitlisted' else 'confirmed' end; end if;
  is_full := (select count(*) from public.session_signups where session_id = p_session and not waitlisted) >= s.capacity;
  insert into public.session_signups (session_id, user_id, waitlisted) values (p_session, me, is_full);
  return case when is_full then 'waitlisted' else 'confirmed' end;
end
$$;
revoke execute on function public.sign_up_session(uuid, text) from public, anon;
grant execute on function public.sign_up_session(uuid, text) to authenticated;

-- 取消报名：多了开场前 24 小时内没人补上时通知组织者，其余不变
create or replace function public.cancel_signup(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.group_sessions;
  was_waitlisted boolean;
begin
  select * into s from public.group_sessions where id = p_session and cancelled_at is null and ends_at > now() for update;
  if s.id is null then raise exception 'session_closed' using errcode = 'P0002'; end if;
  delete from public.session_signups where session_id = p_session and user_id = auth.uid() returning waitlisted into was_waitlisted;
  if was_waitlisted is null or was_waitlisted then return; end if;
  if s.starts_at - now() < interval '2 hours' then
    insert into public.session_late_cancels (session_id, user_id) values (p_session, auth.uid()) on conflict do nothing;
  end if;
  if s.starts_at > now() then
    perform public.promote_waitlist(p_session);
    perform public.notify_open_spot(p_session);
  end if;
end
$$;

-- 组织者移出访客：留了邮箱的收到“你不在名单上了”（邮件先写好，删了那一行就查不到了）
create or replace function public.remove_guest(p_signup uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  email jsonb;
begin
  if not public.is_organizer((select gs.group_id from public.session_signups su join public.group_sessions gs on gs.id = su.session_id
                              where su.id = p_signup and su.user_id is null), auth.uid()) then
    raise exception 'not_organizer' using errcode = '42501';
  end if;
  email := public.guest_email(p_signup, 'You’re off the list: {group}', 'The organizer took you off the list for {when} · {court}.', null);
  perform public.drop_guest_signup(p_signup);
  perform public.send_guest_emails(jsonb_build_array(email));
end
$$;

-- 递补：补上的是访客，邮件里带取消链接（新凭证）
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
  elsif promoted.guest_email is not null then
    perform public.send_guest_emails(jsonb_build_array(public.guest_email(promoted.id, 'You’re in: {group}',
      'A spot opened up for {when} · {court}. If you can’t make it, cancel here:',
      'https://badie.rsvp/g/' || s.guest_code || '/?cancel=' || public.new_guest_mail_token(promoted.id))));
  end if;
end
$$;

-- 改球群：改了每周场次的时间（或名额、费用、球馆）时，同一个星期几的改在原来那一行上，已经生成、还没开始的场次跟着改，
-- 报名都保留；报了名的人收到“场次有变”（访客的邮件带取消链接），名额多了候补的补上。
-- 同一个星期几没有新的那一项（删了或换了星期几）才像以前一样取消那几场。其余同上一版（20261221000000_group_venues.sql）
create or replace function public.update_group(p_group uuid, p_name text, p_summary text, p_level_min int, p_level_max int,
                                               p_policy public.join_policy, p_schedules jsonb, p_coached boolean default null,
                                               p_venues text[] default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  old record;
  doomed uuid;
  session record;
  item jsonb;
  is_coached boolean;
  before text[];
  courts text[];
  items jsonb;
  court text;
  tz text;
  new_start timestamptz;
begin
  if public.group_role_of(p_group, auth.uid()) is distinct from 'owner' then raise exception 'not_organizer' using errcode = '42501'; end if;
  before := public.group_courts(p_group);
  if p_venues is null then
    courts := before;
  else
    courts := public.resolve_group_courts(p_venues);
    if courts is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  end if;
  is_coached := coalesce(p_coached, (select g.coached from public.play_groups g where g.id = p_group));
  if not public.valid_schedules(p_schedules, is_coached) then raise exception 'invalid_schedule' using errcode = '22023'; end if;
  if btrim(p_name) ~* '(https?:|www\.|@|\d{5,})' or coalesce(p_summary, '') ~* '(https?:|www\.|\d{7,})' then
    raise exception 'no_contact_info' using errcode = '22023';
  end if;

  if courts is distinct from before then
    -- 主球馆换了：原来写“主球馆”的场次还在原来的球馆
    if courts[1] is distinct from before[1] and before[1] = any(courts) then
      update public.group_schedules set venue_id = before[1] where group_id = p_group and venue_id is null;
    end if;
    -- 删掉的球馆：那里的场次回到主球馆，还没开始的场次也改过去
    update public.group_schedules set venue_id = null where group_id = p_group and not venue_id = any(courts);
    update public.group_sessions s set venue_id = coalesce(sc.venue_id, courts[1])
      from public.group_schedules sc
      where sc.id = s.schedule_id and s.group_id = p_group and s.starts_at > now() and not s.venue_id = any(courts);
    update public.group_schedules set venue_id = null where group_id = p_group and venue_id = courts[1];
    delete from public.group_venues where group_id = p_group;
    insert into public.group_venues (group_id, venue_id, position)
      select p_group, c, (n - 1)::smallint from unnest(courts) with ordinality as x (c, n);
  end if;
  items := public.normalize_group_schedules(p_schedules, courts, before, p_group);

  update public.play_groups set name = btrim(p_name), summary = btrim(coalesce(p_summary, '')),
         level_min = p_level_min, level_max = p_level_max, join_policy = p_policy, coached = is_coached, venue_id = courts[1]
    where id = p_group;

  for old in select s.* from public.group_schedules s where s.group_id = p_group and not exists (
               select 1 from jsonb_array_elements(items) n
               where (n ->> 'weekday')::int = s.weekday and (n ->> 'start')::int = s.start_minutes and (n ->> 'end')::int = s.end_minutes
                 and (n ->> 'capacity')::int = s.capacity and nullif(btrim(n ->> 'fee'), '') is not distinct from s.fee_note
                 and (n ->> 'venue') is not distinct from s.venue_id)
             order by s.weekday, s.start_minutes loop
    -- 同一个星期几、还没有对应的那一项新的
    select n into item from jsonb_array_elements(items) n
      where (n ->> 'weekday')::int = old.weekday and not exists (
              select 1 from public.group_schedules s
              where s.group_id = p_group and s.weekday = (n ->> 'weekday')::int and s.start_minutes = (n ->> 'start')::int
                and s.end_minutes = (n ->> 'end')::int and s.capacity = (n ->> 'capacity')::int
                and s.fee_note is not distinct from nullif(btrim(n ->> 'fee'), '') and s.venue_id is not distinct from (n ->> 'venue'))
      order by (n ->> 'start')::int limit 1;
    if item is null then
      for doomed in select id from public.group_sessions where schedule_id = old.id and cancelled_at is null and starts_at > now() loop
        perform public.cancel_session(doomed);
      end loop;
      delete from public.group_schedules where id = old.id;
      continue;
    end if;

    update public.group_schedules
      set start_minutes = (item ->> 'start')::smallint, end_minutes = (item ->> 'end')::smallint, capacity = (item ->> 'capacity')::smallint,
          fee_note = nullif(btrim(item ->> 'fee'), ''), venue_id = item ->> 'venue'
      where id = old.id;
    court := coalesce(item ->> 'venue', courts[1]);
    tz := (select coalesce(v.time_zone_id, 'UTC') from public.venues v where v.id = court);
    for session in select gs.id, gs.starts_at, gs.venue_id, gs.capacity, gs.cancelled_at, coalesce(v.time_zone_id, 'UTC') as old_tz,
                          (gs.starts_at at time zone coalesce(v.time_zone_id, 'UTC'))::date as day
                   from public.group_sessions gs left join public.venues v on v.id = gs.venue_id
                   where gs.schedule_id = old.id and gs.starts_at > now() loop
      new_start := (session.day + make_interval(mins => (item ->> 'start')::int)) at time zone tz;
      -- 改到了今天已经过去的时间：这一场取消
      if new_start <= now() then
        if session.cancelled_at is null then perform public.cancel_session(session.id); end if;
        continue;
      end if;
      update public.group_sessions
        set starts_at = new_start, ends_at = (session.day + make_interval(mins => (item ->> 'end')::int)) at time zone tz,
            capacity = (item ->> 'capacity')::int, venue_id = court
        where id = session.id;
      continue when session.cancelled_at is not null;
      if new_start <> session.starts_at or court is distinct from session.venue_id then
        perform public.notify(su.user_id, 'group', 'Session changed: {group}', '{old} is now {when} · {court}. You’re still on the list.',
                              '/app/groups/' || p_group || '/',
                              public.slot(new_start, court) || jsonb_build_object('group', btrim(p_name),
                                                                                  'old', jsonb_build_object('at', session.starts_at, 'tz', session.old_tz)))
          from public.session_signups su where su.session_id = session.id and su.user_id <> auth.uid();
        perform public.send_guest_emails((
          select jsonb_agg(public.guest_email(su.id, 'Session changed: {group}',
                                              '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:',
                                              'https://badie.rsvp/g/' || g.guest_code || '/?cancel=' || public.new_guest_mail_token(su.id),
                                              jsonb_build_object('old', jsonb_build_object('at', session.starts_at, 'tz', session.old_tz))))
          from public.session_signups su join public.play_groups g on g.id = p_group
          where su.session_id = session.id and su.guest_email is not null));
      end if;
      -- 名额多了：候补的按顺序补上
      perform public.promote_waitlist(session.id) from generate_series(1, (item ->> 'capacity')::int - session.capacity);
    end loop;
  end loop;

  insert into public.group_schedules (group_id, weekday, start_minutes, end_minutes, capacity, fee_note, venue_id)
    select p_group, (n ->> 'weekday')::smallint, (n ->> 'start')::smallint, (n ->> 'end')::smallint, (n ->> 'capacity')::smallint,
           nullif(btrim(n ->> 'fee'), ''), n ->> 'venue'
    from jsonb_array_elements(items) n
    where not exists (select 1 from public.group_schedules s
                      where s.group_id = p_group and s.weekday = (n ->> 'weekday')::int and s.start_minutes = (n ->> 'start')::int
                        and s.end_minutes = (n ->> 'end')::int and s.capacity = (n ->> 'capacity')::int
                        and s.fee_note is not distinct from nullif(btrim(n ->> 'fee'), '')
                        and s.venue_id is not distinct from (n ->> 'venue'));
  perform public.ensure_sessions(p_group);
end
$$;

-- 球群页：组织者多看到每一场开场前 2 小时内退出的人（"late_cancels"：名字、是不是访客；又报回来的成员不算）。其余同上一版
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
                                          where su.session_id = s.id and (su.user_id is null or p.id is not null)) end,
        'late_cancels', case when organizer then (select jsonb_agg(jsonb_build_object('nickname', coalesce(p.nickname, lc.guest_name),
                                                                                      'guest', lc.user_id is null)
                                                                   order by lc.cancelled_at)
                                                  from public.session_late_cancels lc left join public.profiles p on p.id = lc.user_id
                                                  where lc.session_id = s.id and (lc.user_id is null or p.id is not null)
                                                    and not exists (select 1 from public.session_signups su
                                                                    where su.session_id = s.id and su.user_id = lc.user_id)) end)
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

-- ---------------------------------------------------------------------------
-- 通知和邮件的译文
-- ---------------------------------------------------------------------------

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', 'You’re off the list: {group}', '你不在名单上了：{group}'),
  ('zh-Hans', 'The organizer took you off the list for {when} · {court}.', '组织者把你从 {when} · {court} 的名单上移出了。'),
  ('zh-Hans', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', '{when} · {court} 空出了位置，你已报上名。去不了的话，在这里取消：'),
  ('zh-Hans', 'Spot open: {group}', '有空位：{group}'),
  ('zh-Hans', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court} 有人退出，候补里没人。现在报了 {n}/{total}。'),
  ('zh-Hans', 'Session changed: {group}', '场次有变：{group}'),
  ('zh-Hans', '{old} is now {when} · {court}. You’re still on the list.', '{old} 这场改成了 {when} · {court}。你还在名单上。'),
  ('zh-Hans', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', '{old} 这场改成了 {when} · {court}。你还在名单上。去不了的话，在这里取消：'),
  ('zh-Hant', 'You’re off the list: {group}', '你不在名單上了：{group}'),
  ('zh-Hant', 'The organizer took you off the list for {when} · {court}.', '組織者把你從 {when} · {court} 的名單上移除了。'),
  ('zh-Hant', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', '{when} · {court} 有空位了，你已報上名。去不了的話，在這裡取消：'),
  ('zh-Hant', 'Spot open: {group}', '有空位：{group}'),
  ('zh-Hant', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court} 有人退出，候補裡沒人。現在報了 {n}/{total}。'),
  ('zh-Hant', 'Session changed: {group}', '場次有變：{group}'),
  ('zh-Hant', '{old} is now {when} · {court}. You’re still on the list.', '{old} 這場改成了 {when} · {court}。你還在名單上。'),
  ('zh-Hant', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', '{old} 這場改成了 {when} · {court}。你還在名單上。去不了的話，在這裡取消：'),
  ('ja', 'You’re off the list: {group}', '参加リストから外れました：{group}'),
  ('ja', 'The organizer took you off the list for {when} · {court}.', '主催者が {when} · {court} の参加リストからあなたを外しました。'),
  ('ja', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', '{when} · {court} に空きが出て、参加が決まりました。行けなくなったら、こちらからキャンセルできます：'),
  ('ja', 'Spot open: {group}', '空きが出ました：{group}'),
  ('ja', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court}：キャンセルが出ましたが、キャンセル待ちの人はいません。現在 {n}/{total} 人です。'),
  ('ja', 'Session changed: {group}', '日程が変わりました：{group}'),
  ('ja', '{old} is now {when} · {court}. You’re still on the list.', '{old} の回は {when} · {court} に変わりました。申し込みはそのままです。'),
  ('ja', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', '{old} の回は {when} · {court} に変わりました。申し込みはそのままです。行けなくなったら、こちらからキャンセルできます：'),
  ('ko', 'You’re off the list: {group}', '명단에서 빠졌어요: {group}'),
  ('ko', 'The organizer took you off the list for {when} · {court}.', '운영자가 {when} · {court} 명단에서 회원님을 뺐어요.'),
  ('ko', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', '{when} · {court}에 자리가 나서 신청됐어요. 못 가게 되면 여기서 취소하세요:'),
  ('ko', 'Spot open: {group}', '자리가 비었어요: {group}'),
  ('ko', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court}: 한 명이 빠졌는데 대기자가 없어요. 지금 {n}/{total}명이에요.'),
  ('ko', 'Session changed: {group}', '일정이 바뀌었어요: {group}'),
  ('ko', '{old} is now {when} · {court}. You’re still on the list.', '{old} 일정이 {when} · {court}(으)로 바뀌었어요. 신청은 그대로예요.'),
  ('ko', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', '{old} 일정이 {when} · {court}(으)로 바뀌었어요. 신청은 그대로예요. 못 가게 되면 여기서 취소하세요:'),
  ('id', 'You’re off the list: {group}', 'Kamu tidak ada di daftar lagi: {group}'),
  ('id', 'The organizer took you off the list for {when} · {court}.', 'Penyelenggara mengeluarkanmu dari daftar {when} · {court}.'),
  ('id', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', 'Ada slot kosong untuk {when} · {court}, dan kamu sudah masuk. Kalau tidak bisa datang, batalkan di sini:'),
  ('id', 'Spot open: {group}', 'Ada slot kosong: {group}'),
  ('id', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court}: ada yang batal dan daftar tunggu kosong. Sekarang {n}/{total} terdaftar.'),
  ('id', 'Session changed: {group}', 'Sesi berubah: {group}'),
  ('id', '{old} is now {when} · {court}. You’re still on the list.', 'Sesi {old} sekarang {when} · {court}. Kamu tetap terdaftar.'),
  ('id', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', 'Sesi {old} sekarang {when} · {court}. Kamu tetap terdaftar. Kalau tidak bisa datang, batalkan di sini:'),
  ('ms', 'You’re off the list: {group}', 'Anda tiada dalam senarai lagi: {group}'),
  ('ms', 'The organizer took you off the list for {when} · {court}.', 'Penganjur mengeluarkan anda daripada senarai {when} · {court}.'),
  ('ms', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', 'Ada tempat kosong untuk {when} · {court}, dan anda sudah masuk. Jika anda tidak dapat hadir, batalkan di sini:'),
  ('ms', 'Spot open: {group}', 'Ada tempat kosong: {group}'),
  ('ms', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court}: seorang menarik diri dan senarai menunggu kosong. Kini {n}/{total} mendaftar.'),
  ('ms', 'Session changed: {group}', 'Sesi berubah: {group}'),
  ('ms', '{old} is now {when} · {court}. You’re still on the list.', 'Sesi {old} kini {when} · {court}. Anda masih dalam senarai.'),
  ('ms', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', 'Sesi {old} kini {when} · {court}. Anda masih dalam senarai. Jika anda tidak dapat hadir, batalkan di sini:'),
  ('th', 'You’re off the list: {group}', 'คุณไม่อยู่ในรายชื่อแล้ว: {group}'),
  ('th', 'The organizer took you off the list for {when} · {court}.', 'ผู้จัดเอาคุณออกจากรายชื่อรอบ {when} · {court} แล้ว'),
  ('th', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', 'มีที่ว่างสำหรับ {when} · {court} และคุณได้ที่แล้ว ถ้าไปไม่ได้ ยกเลิกได้ที่นี่:'),
  ('th', 'Spot open: {group}', 'มีที่ว่าง: {group}'),
  ('th', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court}: มีคนถอนตัวและไม่มีใครในคิวสำรอง ตอนนี้ลงชื่อ {n}/{total}'),
  ('th', 'Session changed: {group}', 'รอบมีการเปลี่ยนแปลง: {group}'),
  ('th', '{old} is now {when} · {court}. You’re still on the list.', 'รอบ {old} เปลี่ยนเป็น {when} · {court} คุณยังอยู่ในรายชื่อ'),
  ('th', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', 'รอบ {old} เปลี่ยนเป็น {when} · {court} คุณยังอยู่ในรายชื่อ ถ้าไปไม่ได้ ยกเลิกได้ที่นี่:'),
  ('vi', 'You’re off the list: {group}', 'Bạn không còn trong danh sách: {group}'),
  ('vi', 'The organizer took you off the list for {when} · {court}.', 'Người tổ chức đã đưa bạn ra khỏi danh sách buổi {when} · {court}.'),
  ('vi', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', 'Có chỗ trống cho {when} · {court} và bạn đã có chỗ. Nếu không đi được, hủy tại đây:'),
  ('vi', 'Spot open: {group}', 'Có chỗ trống: {group}'),
  ('vi', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court}: có người rút và không ai trong danh sách chờ. Hiện có {n}/{total} người.'),
  ('vi', 'Session changed: {group}', 'Buổi có thay đổi: {group}'),
  ('vi', '{old} is now {when} · {court}. You’re still on the list.', 'Buổi {old} đổi thành {when} · {court}. Bạn vẫn có tên trong danh sách.'),
  ('vi', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', 'Buổi {old} đổi thành {when} · {court}. Bạn vẫn có tên trong danh sách. Nếu không đi được, hủy tại đây:'),
  ('hi', 'You’re off the list: {group}', 'आप लिस्ट में नहीं हैं: {group}'),
  ('hi', 'The organizer took you off the list for {when} · {court}.', 'ऑर्गनाइज़र ने आपको {when} · {court} की लिस्ट से हटा दिया।'),
  ('hi', 'A spot opened up for {when} · {court}. If you can’t make it, cancel here:', '{when} · {court} में एक जगह खाली हुई और आपका नाम लिख लिया गया। अगर आना न हो पाए, तो यहाँ कैंसिल करें:'),
  ('hi', 'Spot open: {group}', 'जगह खाली: {group}'),
  ('hi', '{when} · {court}: someone dropped out and no one is on the waitlist. {n}/{total} signed up.', '{when} · {court}: किसी ने नाम वापस लिया और वेटलिस्ट में कोई नहीं है। अभी {n}/{total} लोग हैं।'),
  ('hi', 'Session changed: {group}', 'सेशन बदला: {group}'),
  ('hi', '{old} is now {when} · {court}. You’re still on the list.', '{old} वाला सेशन अब {when} · {court} पर है। आपका नाम लिस्ट में है।'),
  ('hi', '{old} is now {when} · {court}. You’re still on the list. If you can’t make it, cancel here:', '{old} वाला सेशन अब {when} · {court} पर है। आपका नाम लिस्ट में है। अगर आना न हो पाए, तो यहाँ कैंसिल करें:')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
