-- 发现页 v5
-- - 约 TA 定具体时间：invite_player / counter_invite 多了 p_duration（打多少分钟，60–240，半小时一档）。
--   窗口正好这么长就是定好的时间（time_set = true）；不传照旧按 2 小时（旧版 App）
-- - 约双打：p_mode = 'doubles'（必须定好时间）。对方说好以后，这个邀请变成一个普通的公开双打局：两个人已经在里面，
--   附近的人看到“还差 2 人”可以加入，人齐了房主开局（和普通球局一样）。换个时间不传 p_mode 就保持原来的项目
-- - 球馆页“最近在这打过”和“常客”：venue_people(p_venue)

-- ---------------------------------------------------------------------------
-- 一对一的邀请也可以是双打（还在等回复时是私密的；答应以后 invitee_id 清空，就是普通房间）
-- ---------------------------------------------------------------------------

alter table public.rooms drop constraint rooms_invite_check,
  add constraint rooms_invite_check check (invitee_id is null or (visibility = 'private' and invitee_id <> owner_id));

-- 检查并整理邀请的球馆和时间窗口（客户端不能直接调用）：多了打多久（p_minutes，null = 2 小时）。
-- 窗口正好 p_minutes 长 = 定好的时间
drop function public.invite_window(text, timestamptz, timestamptz, text);
create function public.invite_window(p_venue text, p_window_start timestamptz, p_window_end timestamptz, p_daypart text,
                                     p_minutes int,
                                     out venue text, out tz text, out window_start timestamptz, out window_end timestamptz,
                                     out daypart text, out minutes int, out exact boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  select coalesce(v.merged_into, v.id) into venue from public.venues v where v.id = p_venue and not v.hidden_pending_review;
  if venue is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  select coalesce(v.time_zone_id, 'UTC') into tz from public.venues v where v.id = venue;
  daypart := nullif(p_daypart, 'any');
  minutes := coalesce(p_minutes, 120);
  if p_window_start is null or p_window_end is null
     or extract(epoch from p_window_start)::bigint % 1800 <> 0 or extract(epoch from p_window_end)::bigint % 1800 <> 0
     or p_window_end - p_window_start > interval '7 days'
     or minutes not between 60 and 240 or minutes % 30 <> 0
     or (daypart is not null and daypart not in ('morning', 'afternoon', 'evening')) then
    raise exception 'invalid_window' using errcode = '22023';
  end if;
  if p_window_start > now() + interval '30 days' then raise exception 'too_far' using errcode = '22023'; end if;
  -- 开头早于“现在 + 30 分钟”的往后挪；定好的时间挪了就不够长，下面会报 invalid_window
  window_start := greatest(p_window_start, to_timestamp(ceil(extract(epoch from now() + interval '30 minutes') / 1800) * 1800));
  window_end := p_window_end;
  if public.first_window_start(window_start, window_end, minutes, daypart, tz, window_start) is null then
    raise exception 'invalid_window' using errcode = '22023';
  end if;
  exact := window_end - window_start = make_interval(mins => minutes);
  if exact then daypart := null; end if;
end
$$;

-- 右滑发邀请：只有两个人的局（私密房间，对方在 room_invites 里），带时间窗口。每天最多 10 个
-- 返回 {room_id, remaining}
drop function public.invite_player(uuid, text, timestamptz, timestamptz, text);
create function public.invite_player(p_user uuid, p_venue text, p_window_start timestamptz, p_window_end timestamptz,
                                     p_daypart text default null, p_duration int default null,
                                     p_mode public.game_mode default 'singles')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  w record;
  sent int;
  new_room uuid;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_user is null then raise exception 'not_available' using errcode = 'P0002'; end if;
  -- 同一个人的邀请排队算个数；两个人同时互相右滑也只会有一个邀请
  perform pg_advisory_xact_lock(hashtextextended('nearby_invite:' || me::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('nearby_pair:' || least(me, p_user)::text || ':' || greatest(me, p_user)::text, 0));
  if not (select p.show_as_regular from public.profiles p where p.id = me) then
    raise exception 'not_visible' using errcode = '22023';
  end if;
  if not public.invite_allowed(me, p_user) then raise exception 'not_available' using errcode = 'P0002'; end if;
  if public.invite_open_between(me, p_user) then raise exception 'already_invited' using errcode = '23505'; end if;
  sent := (select count(*) from public.rooms where owner_id = me and invitee_id is not null and created_at > now() - interval '1 day')::int;
  if sent >= 10 then raise exception 'invite_limit' using errcode = '54000'; end if;

  select * into w from public.invite_window(p_venue, p_window_start, p_window_end, p_daypart, p_duration);
  -- 双打答应以后要变成普通的公开局，时间得先定好
  if coalesce(p_mode, 'singles') = 'doubles' and not w.exact then raise exception 'invalid_window' using errcode = '22023'; end if;
  if w.exact and public.has_game_between(me, w.window_start, w.window_end) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  insert into public.rooms (code, owner_id, mode, visibility, venue_id, starts_at, ends_at, level_min, level_max,
                            invitee_id, awaiting_id, window_start, window_end, duration_minutes, daypart, time_set)
    values (public.new_invite_code(), me, coalesce(p_mode, 'singles'), 'private', w.venue, w.window_start, w.window_end, 1, 9,
            p_user, p_user, w.window_start, w.window_end, w.minutes, w.daypart, w.exact)
    returning id into new_room;
  insert into public.room_members (room_id, user_id) values (new_room, me);
  insert into public.room_invites (room_id, user_id, invited_by) values (new_room, p_user, me);

  perform public.notify(p_user, 'room',
    case when p_mode = 'doubles' then '{name} invited you to play doubles' else '{name} invited you to play' end,
    '{when} · {court}. Open Badie to join.', '/app/rooms/' || new_room || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = me))
      || public.window_slot(w.window_start, w.window_end, w.exact, w.venue));
  return jsonb_build_object('room_id', new_room, 'remaining', greatest(9 - sent, 0));
end
$$;

-- 回复邀请（轮到我回复的时候）：好 = 成局（单打）或变成公开的双打局；不了 = 关闭。
-- 返回 {status: 'accepted' | 'declined', game_id, room_id}（双打答应后 game_id 是 null，去房间页）
create or replace function public.respond_invite(p_room uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  other uuid;
  new_game uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.invitee_id is null or r.status <> 'open' or me not in (r.owner_id, r.invitee_id) or p_accept is null
     or public.hidden_from(r.owner_id, r.invitee_id) or public.hidden_from(r.invitee_id, r.owner_id) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if r.awaiting_id is distinct from me then raise exception 'not_your_turn' using errcode = '22023'; end if;
  other := case when me = r.owner_id then r.invitee_id else r.owner_id end;

  -- 不了：谁都能说（包括不能约球的人）
  if not p_accept then
    perform public.decline_invite(p_room, me);
    return jsonb_build_object('status', 'declined', 'game_id', null);
  end if;

  if r.window_end - make_interval(mins => r.duration_minutes) <= now() then
    raise exception 'invite_expired' using errcode = 'P0002';
  end if;
  -- 窗口里还要有一个“现在 + 30 分钟”以后能开始的时间
  if public.first_window_start(r.window_start, r.window_end, r.duration_minutes, r.daypart,
                               (select coalesce(v.time_zone_id, 'UTC') from public.venues v where v.id = r.venue_id),
                               now() + interval '30 minutes') is null then
    raise exception 'too_late' using errcode = '22023';
  end if;
  -- 两个人都要能约球（发邀请以后才被暂停的也拦下）
  if public.suspended_until(r.owner_id) is not null or public.suspended_until(r.invitee_id) is not null then
    raise exception 'suspended' using errcode = '42501';
  end if;
  if r.time_set and (public.has_game_between(r.owner_id, r.starts_at, r.ends_at) or public.has_game_between(r.invitee_id, r.starts_at, r.ends_at)) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  insert into public.room_members (room_id, user_id) values (p_room, r.invitee_id) on conflict do nothing;
  delete from public.room_invites where room_id = p_room;

  -- 双打：变成普通的公开局，水平范围是两个人的上下各一级，附近的人可以加入，人齐了房主开局
  if r.mode = 'doubles' then
    update public.rooms
      set invitee_id = null, awaiting_id = null, visibility = 'public', last_activity_at = now(),
          level_min = greatest(1, least(public.room_level(r.owner_id, null, false), public.room_level(r.invitee_id, null, false)) - 1),
          level_max = least(9, greatest(public.room_level(r.owner_id, null, false), public.room_level(r.invitee_id, null, false)) + 1)
      where id = p_room;
    perform public.notify(other, 'room', '{name} said yes to doubles', '{when} · {court}. 2 more players can join.',
      '/app/rooms/' || p_room || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me)) || public.slot(r.starts_at, r.venue_id));
    return jsonb_build_object('status', 'accepted', 'game_id', null, 'room_id', p_room);
  end if;

  insert into public.games (mode, starts_at, ends_at, venue_id, window_start, window_end, duration_minutes, daypart, time_set)
    values ('singles', r.starts_at, r.ends_at, r.venue_id, r.window_start, r.window_end, r.duration_minutes, r.daypart, r.time_set)
    returning id into new_game;
  -- 和开局一样：水平高的是 1 队
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, x.id, row_number() over (order by public.open_rating(x.rating, x.gender) desc, x.id = r.owner_id desc)::smallint, x.rating
    from public.profiles x where x.id in (r.owner_id, r.invitee_id);
  update public.rooms set status = 'started', game_id = new_game, awaiting_id = null, last_activity_at = now() where id = p_room;

  perform public.notify(other, 'matched', 'Game confirmed',
    case when r.time_set then '{when} · {court}. Everyone confirmed.' else '{when} · {court}. Set the exact time when you’re ready.' end,
    '/app/games/' || new_game || '/', public.window_slot(r.starts_at, r.ends_at, r.time_set, r.venue_id));
  return jsonb_build_object('status', 'accepted', 'game_id', new_game, 'room_id', p_room);
end
$$;

-- 换个时间（轮到我回复的时候）：改窗口（球馆、打多久、项目也能换），轮到对方回复。不占每天 10 个。
-- p_mode 不传就保持原来的项目
drop function public.counter_invite(uuid, text, timestamptz, timestamptz, text);
create function public.counter_invite(p_room uuid, p_venue text, p_window_start timestamptz, p_window_end timestamptz,
                                      p_daypart text default null, p_duration int default null,
                                      p_mode public.game_mode default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  w record;
  other uuid;
  new_mode public.game_mode;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.invitee_id is null or r.status <> 'open' or me not in (r.owner_id, r.invitee_id)
     or public.hidden_from(r.owner_id, r.invitee_id) or public.hidden_from(r.invitee_id, r.owner_id) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if r.awaiting_id is distinct from me then raise exception 'not_your_turn' using errcode = '22023'; end if;
  other := case when me = r.owner_id then r.invitee_id else r.owner_id end;
  if public.suspended_until(me) is not null or public.suspended_until(other) is not null then
    raise exception 'suspended' using errcode = '42501';
  end if;

  new_mode := coalesce(p_mode, r.mode);
  select * into w from public.invite_window(coalesce(p_venue, r.venue_id), p_window_start, p_window_end, p_daypart, p_duration);
  if new_mode = 'doubles' and not w.exact then raise exception 'invalid_window' using errcode = '22023'; end if;
  if w.exact and public.has_game_between(me, w.window_start, w.window_end) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  update public.rooms set venue_id = w.venue, starts_at = w.window_start, ends_at = w.window_end, mode = new_mode,
                          window_start = w.window_start, window_end = w.window_end, duration_minutes = w.minutes,
                          daypart = w.daypart, time_set = w.exact,
                          awaiting_id = other, invite_rounds = invite_rounds + 1, last_activity_at = now()
    where id = p_room;
  perform public.notify(other, 'invite_counter', '{name} suggested another time', '{when} · {court}. Open Badie to answer.',
    '/app/rooms/' || p_room || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = me))
      || public.window_slot(w.window_start, w.window_end, w.exact, w.venue));
end
$$;

-- ---------------------------------------------------------------------------
-- 球馆页：最近 30 天在这打过的人、常客（收藏了这家的）。只列在附近的人里能看到的
-- （开了显示、定过级、收藏了球馆，和大厅一样，点进去能看资料），不列自己和拉黑 / 举报过的，各最多 20 位
-- 返回 {recent: [user], regulars: [user]}，user 和 nearby_players 里的一样
-- ---------------------------------------------------------------------------

create function public.venue_people(p_venue text)
returns jsonb language sql stable security definer set search_path = '' as $$
  with here as (
    -- 合并过的球馆：原来那家的球局也算
    select v.id from public.venues v where v.id = p_venue or v.merged_into = p_venue),
  visible as (
    select p.id from public.profiles p
    where p.id <> auth.uid() and p.show_as_regular and public.has_level(p.id)
      and exists (select 1 from public.favorite_venues f where f.user_id = p.id)
      and not public.hidden_from(auth.uid(), p.id) and not public.hidden_from(p.id, auth.uid())),
  recent as (
    select gp.user_id as id, max(g.ends_at) as last_played
    from public.games g join public.game_players gp on gp.game_id = g.id
    where g.venue_id in (select id from here) and g.status = 'scheduled' and g.time_set
      and g.ends_at between now() - interval '30 days' and now() and gp.cancelled_at is null
      and gp.user_id in (select id from visible)
    group by gp.user_id
    order by last_played desc, gp.user_id
    limit 20),
  regulars as (
    select f.user_id as id, min(f.created_at) as since
    from public.favorite_venues f
    where f.venue_id in (select id from here) and f.user_id in (select id from visible)
    group by f.user_id
    order by since, f.user_id
    limit 20)
  select jsonb_build_object(
    'recent', coalesce((select jsonb_agg(public.nearby_user(x.id) order by x.last_played desc, x.id) from recent x), '[]'),
    'regulars', coalesce((select jsonb_agg(public.nearby_user(x.id) order by x.since, x.id) from regulars x), '[]'))
  where auth.uid() is not null
$$;

-- ---------------------------------------------------------------------------
-- 权限和通知文字
-- ---------------------------------------------------------------------------

revoke execute on function public.invite_window(text, timestamptz, timestamptz, text, int) from public, anon, authenticated;
revoke execute on function public.invite_player(uuid, text, timestamptz, timestamptz, text, int, public.game_mode),
  public.counter_invite(uuid, text, timestamptz, timestamptz, text, int, public.game_mode), public.venue_people(text)
  from public, anon;
grant execute on function public.invite_player(uuid, text, timestamptz, timestamptz, text, int, public.game_mode),
  public.counter_invite(uuid, text, timestamptz, timestamptz, text, int, public.game_mode), public.venue_people(text)
  to authenticated;

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', '{name} invited you to play doubles', '{name} 约你打双打'),
  ('zh-Hans', '{name} said yes to doubles', '{name} 答应打双打'),
  ('zh-Hans', '{when} · {court}. 2 more players can join.', '{when} · {court}。还差 2 人，附近的人可以加入。'),
  ('zh-Hant', '{name} invited you to play doubles', '{name} 約你打雙打'),
  ('zh-Hant', '{name} said yes to doubles', '{name} 答應打雙打'),
  ('zh-Hant', '{when} · {court}. 2 more players can join.', '{when} · {court}。還差 2 人，附近的人可以加入。'),
  ('ja', '{name} invited you to play doubles', '{name} さんからダブルスの招待が届きました'),
  ('ja', '{name} said yes to doubles', '{name} さんがダブルスに OK しました'),
  ('ja', '{when} · {court}. 2 more players can join.', '{when} · {court}。あと 2 人参加できます。'),
  ('ko', '{name} invited you to play doubles', '{name}님이 복식 게임에 초대했어요'),
  ('ko', '{name} said yes to doubles', '{name}님이 복식을 수락했어요'),
  ('ko', '{when} · {court}. 2 more players can join.', '{when} · {court}. 2명 더 참가할 수 있어요.'),
  ('id', '{name} invited you to play doubles', '{name} mengajakmu main ganda'),
  ('id', '{name} said yes to doubles', '{name} setuju main ganda'),
  ('id', '{when} · {court}. 2 more players can join.', '{when} · {court}. Masih bisa 2 pemain lagi.'),
  ('ms', '{name} invited you to play doubles', '{name} menjemput anda bermain beregu'),
  ('ms', '{name} said yes to doubles', '{name} setuju bermain beregu'),
  ('ms', '{when} · {court}. 2 more players can join.', '{when} · {court}. 2 lagi pemain boleh menyertai.'),
  ('th', '{name} invited you to play doubles', '{name} ชวนคุณมาตีคู่'),
  ('th', '{name} said yes to doubles', '{name} ตกลงตีคู่'),
  ('th', '{when} · {court}. 2 more players can join.', '{when} · {court} รับได้อีก 2 คน'),
  ('vi', '{name} invited you to play doubles', '{name} mời bạn đánh đôi'),
  ('vi', '{name} said yes to doubles', '{name} đã đồng ý đánh đôi'),
  ('vi', '{when} · {court}. 2 more players can join.', '{when} · {court}. Còn 2 chỗ trống.'),
  ('hi', '{name} invited you to play doubles', '{name} ने आपको डबल्स खेलने बुलाया'),
  ('hi', '{name} said yes to doubles', '{name} डबल्स के लिए तैयार हैं'),
  ('hi', '{when} · {court}. 2 more players can join.', '{when} · {court}. 2 और खिलाड़ी जुड़ सकते हैं।')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
