-- 别人在首页刷到你时看到的卡片：
-- - 卡片背景照片和头像分开（同一个 avatars 桶、同样的命名和大小限制，竖图）
-- - 没传背景照片时，卡片上半部分用 card_color（没选过的按用户 ID 给一个默认色，前端算）
alter table public.profiles add column card_color text
  check (card_color in ('lime', 'lavender', 'peach', 'sky', 'pink', 'mint', 'butter', 'ink'));
alter table public.profiles add column card_photo_path text;
grant update (card_color) on public.profiles to authenticated;

-- 头像和背景各一张，换的时候先传新的再删旧的：文件夹里最多 4 个
drop policy "players upload their own avatar" on storage.objects;
create policy "players upload their own avatar" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
              and public.my_avatar_file_count() < 4);

-- 换卡片背景：p_path 是刚传上去的文件（null = 不用照片，用颜色）
create function public.set_card_photo(p_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_path is not null and (p_path !~ ('^' || me || '/[0-9a-f-]{36}\.jpg$')
                             or not exists (select 1 from storage.objects where bucket_id = 'avatars' and name = p_path)) then
    raise exception 'invalid_avatar' using errcode = '22023';
  end if;
  update public.profiles set card_photo_path = p_path where id = me;
end
$$;
revoke execute on function public.set_card_photo(text) from public, anon;
grant execute on function public.set_card_photo(text) to authenticated;

-- 管理员撤下照片：头像和卡片背景一起撤
create or replace function public.admin_clear_avatar(p_user uuid, p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_admin();
  update public.profiles set avatar_path = null, card_photo_path = null where id = p_user;
  insert into public.moderation_log (admin_id, target_type, target_id, action, note)
    values (auth.uid(), 'avatar', p_user::text, 'clear', left(coalesce(p_note, ''), 500));
end
$$;

create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', pr.verified_kind,
    'avatar', pr.avatar_path,
    'gender', pr.gender,
    'tag', pr.tag,
    'card_color', pr.card_color,
    'card_photo', pr.card_photo_path,
    'recent_no_shows', public.recent_no_shows(p_user),
    'suspended_until', public.suspended_until(p_user))
  from public.player_card_base(p_user) base, public.win_rate(p_user) w, public.profiles pr
  where base is not null and pr.id = p_user
$$;

-- 卡片直接带上照片和颜色，不用每张再拉一次资料卡
create or replace function public.day_candidates(p_from timestamptz, p_to timestamptz, p_lat double precision, p_lon double precision,
                                      p_radius_km double precision)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(c order by c ->> 'starts_at'), '[]') from (
    select jsonb_build_object(
             'ticket', t.id, 'mode', t.mode, 'mixed', t.mixed, 'play_with', t.play_with,
             'starts_at', t.starts_at, 'ends_at', t.ends_at,
             'user', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'tag', p.tag, 'rating', p.rating, 'gender', p.gender,
                                        'recent_no_shows', public.recent_no_shows(p.id), 'avatar', p.avatar_path,
                                        'card_color', p.card_color, 'card_photo', p.card_photo_path),
             'venues', (select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name) order by v.name)
                        from public.venues v where v.id = any (t.venue_ids))) as c
    from public.match_tickets t join public.profiles p on p.id = t.user_id
    where auth.uid() is not null and p_to - p_from <= interval '2 days'
      and t.status = 'searching' and t.starts_at < p_to and t.ends_at > p_from and t.lock_at > now() + interval '30 minutes'
      and public.can_invite(auth.uid(), t)
      and not exists (select 1 from public.candidate_skips s where s.viewer = auth.uid() and s.ticket_id = t.id)
      and exists (select 1 from public.venues v
                  where v.id = any (t.venue_ids)
                    and extensions.st_dwithin(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography,
                                              least(greatest(p_radius_km, 1), 100) * 1000))
    order by t.starts_at
    limit 50) x
$$;

-- 举报队列带上卡片背景照片，撤下照片时一起撤
create or replace function public.admin_report_queue()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_admin();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'reason', r.reason, 'details', r.details, 'created_at', r.created_at,
      'reporter', jsonb_build_object('id', rp.id, 'nickname', rp.nickname),
      'reported', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'avatar', p.avatar_path, 'card_photo', p.card_photo_path,
                                     'suspended', coalesce(u.banned_until > now(), false)),
      'open_reports', (select count(*) from public.user_reports x where x.reported_id = r.reported_id and x.resolved_at is null),
      'messages', (select coalesce(jsonb_agg(jsonb_build_object('body', m.body, 'at', m.created_at) order by m.created_at desc), '[]')
                   from (select m.body, m.created_at from public.messages m
                         where m.sender_id = r.reported_id and m.created_at > now() - interval '30 days'
                           and (m.thread = 'dm:' || least(r.reporter_id, r.reported_id) || ':' || greatest(r.reporter_id, r.reported_id)
                                or (m.thread ~ '^(game|group):'
                                    and public.thread_access(split_part(m.thread, ':', 1), split_part(m.thread, ':', 2)::uuid, r.reporter_id) is not null))
                         order by m.created_at desc limit 20) m)
    ) order by r.created_at, r.id)
    from public.user_reports r
    join public.profiles p on p.id = r.reported_id
    join public.profiles rp on rp.id = r.reporter_id
    join auth.users u on u.id = r.reported_id
    where r.resolved_at is null), '[]'::jsonb);
end
$$;

-- 处理举报：dismiss 只结这一条；其余（改掉昵称、撤下照片、封号）会把这个人所有没处理的举报一起结案。
-- 封号：登录不了（已登录的最多 1 小时后失效），在找的约球取消，开着的局关掉。都记进审核日志
create or replace function public.admin_resolve_report(p_report bigint, p_action text, p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.user_reports;
  room record;
begin
  perform public.require_admin();
  select * into r from public.user_reports where id = p_report and resolved_at is null for update;
  if r.id is null then raise exception 'request_not_found' using errcode = 'P0002'; end if;
  if p_action not in ('dismiss', 'reset_nickname', 'clear_avatar', 'suspend')
     or (p_action = 'suspend' and (r.reported_id = auth.uid() or exists (select 1 from public.admin_users where user_id = r.reported_id))) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;

  if p_action = 'reset_nickname' then
    update public.profiles set nickname = 'Player ' || upper(left(replace(r.reported_id::text, '-', ''), 4)) where id = r.reported_id;
  elsif p_action = 'clear_avatar' then
    update public.profiles set avatar_path = null, card_photo_path = null where id = r.reported_id;
  elsif p_action = 'suspend' then
    update auth.users set banned_until = now() + interval '100 years' where id = r.reported_id;
    delete from auth.sessions where user_id = r.reported_id;
    update public.match_tickets set status = 'cancelled' where user_id = r.reported_id and status in ('searching', 'paused');
    for room in select id from public.rooms where owner_id = r.reported_id and status = 'open' loop
      perform public.close_room(room.id, 'owner_closed');
    end loop;
  end if;

  update public.user_reports set resolved_at = now()
    where case when p_action = 'dismiss' then id = r.id else reported_id = r.reported_id and resolved_at is null end;
  insert into public.moderation_log (admin_id, target_type, target_id, action, note)
    values (auth.uid(), 'user', r.reported_id::text, p_action, left(coalesce(p_note, ''), 500));
end
$$;
