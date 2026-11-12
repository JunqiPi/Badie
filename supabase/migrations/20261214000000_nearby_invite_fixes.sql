-- 附近的人 v2 的修正
-- - 没定时间的球局：要先定时间才能报赛果（time_not_set）；有人签到就按现在定下时间（这个半点开始）；
--   有人签到或报过赛果的不再自动取消。旧版 App（1.0.4）在定时间前报赛果只会收到错误
-- - 好 / 换个时间：任一方因为爽约不能约球时拦下（suspended）
-- - 好：窗口里还要有一个“现在 + 30 分钟”以后能开始的时间，不然 too_late
-- - 到点关闭邀请只关还开着的（和“好”同时发生时不会把已成局的关掉）
-- - 推荐时间只给能约的人（或者两人之间已经有邀请）
-- - 说了不了 / 过期以后，受邀的人还能打开房间页（通知里的链接）；房间带上谁说的不了（declined_by）
-- - 常用时间和 iOS 一致：每段 1–8 小时，最多 5 段

-- ---------------------------------------------------------------------------
-- 常用时间：每段 1–8 小时，最多 5 段
-- ---------------------------------------------------------------------------

-- 已经存的先整理：只留 1–8 小时的，最多前 5 段（新旧规则都满足，改规则时不会有不合格的行）
update public.profiles p set usual_times = coalesce((
    select jsonb_agg(x.e order by x.n)
    from (select t.e, t.n from jsonb_array_elements(p.usual_times) with ordinality t (e, n)
          where ((t.e ->> 'end')::interval - (t.e ->> 'start')::interval) between interval '1 hour' and interval '8 hours'
          order by t.n limit 5) x), '[]'::jsonb)
  where jsonb_array_length(p.usual_times) > 5
     or exists (select 1 from jsonb_array_elements(p.usual_times) e
                where ((e ->> 'end')::interval - (e ->> 'start')::interval) not between interval '1 hour' and interval '8 hours');

-- [{weekday 1–7（1 = 周日）, start "HH:MM", end "HH:MM"（可到 24:00）}]，每段 1–8 小时，最多 5 段
create or replace function public.valid_usual_times(p jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(p) = 'array' and jsonb_array_length(p) <= 5
    and not exists (
      select 1 from jsonb_array_elements(p) e
      where not (case
        when jsonb_typeof(e) <> 'object' then false
        when (select count(*) from jsonb_object_keys(e)) <> 3 then false
        when not (coalesce(e ->> 'weekday', '') in ('1', '2', '3', '4', '5', '6', '7')
                  and jsonb_typeof(e -> 'weekday') = 'number'
                  and coalesce(e ->> 'start', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
                  and coalesce(e ->> 'end', '') ~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$') then false
        else ((e ->> 'end')::interval - (e ->> 'start')::interval) between interval '1 hour' and interval '8 hours' end))
$$;

-- ---------------------------------------------------------------------------
-- 邀请：谁说的不了
-- ---------------------------------------------------------------------------

alter table public.rooms add column declined_by uuid references auth.users (id) on delete set null;

create or replace function public.decline_invite(p_room uuid, p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
begin
  update public.rooms set status = 'closed', closed_reason = 'declined', awaiting_id = null, declined_by = p_user,
                          last_activity_at = now()
    where id = p_room and status = 'open' and invitee_id is not null and p_user in (owner_id, invitee_id)
    returning * into r;
  if r.id is null then return; end if;
  delete from public.room_invites where room_id = p_room;
  perform public.notify(case when p_user = r.owner_id then r.invitee_id else r.owner_id end, 'invite_declined',
    '{name} can’t make it this time', '{when} · {court}', '/app/play/',
    jsonb_build_object('name', (select nickname from public.profiles where id = p_user))
      || public.window_slot(r.starts_at, r.ends_at, r.time_set, r.venue_id));
end
$$;

-- 房间概要：邀请里多了 declined_by
create or replace function public.room_summary(p_room uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', r.id, 'mode', r.mode, 'visibility', r.visibility, 'status', r.status, 'closed_reason', r.closed_reason,
    'game_id', r.game_id, 'starts_at', r.starts_at, 'ends_at', r.ends_at, 'level_min', r.level_min, 'level_max', r.level_max,
    'tags', r.tags, 'note', r.note, 'gender', r.gender, 'mixed', r.mixed, 'capacity', public.room_capacity(r.mode),
    'last_activity_at', r.last_activity_at,
    'going', (select count(*) from public.room_members m where m.room_id = r.id and not m.waitlisted),
    'mixed_going', case when r.mixed then jsonb_build_object('male', public.room_going(r.id, 'male'), 'female', public.room_going(r.id, 'female')) end,
    'waitlist', (select count(*) from public.room_members m where m.room_id = r.id and m.waitlisted),
    'owner', (select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) from public.profiles p where p.id = r.owner_id),
    'venue', (select jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                        'lat', v.lat, 'lon', v.lon, 'pricing', v.pricing, 'country', v.country_code)
              from public.venues v where v.id = r.venue_id),
    'my_status', public.room_status_of(r.id, auth.uid()),
    -- 时间窗口：time_set = false 时 starts_at / ends_at 就是窗口，在里面打 duration_minutes 分钟
    'time_set', r.time_set, 'window_start', r.window_start, 'window_end', r.window_end,
    'duration_minutes', r.duration_minutes, 'daypart', r.daypart,
    -- 附近的人的一对一邀请（普通房间是 null）：awaiting = 该谁回复（说好、不了、过期以后是 null），declined_by = 谁说的不了
    'invite', case when r.invitee_id is not null then jsonb_build_object(
      'from', public.nearby_user(r.owner_id), 'to', public.nearby_user(r.invitee_id),
      'awaiting_id', r.awaiting_id, 'awaiting_me', r.awaiting_id = auth.uid(), 'rounds', r.invite_rounds,
      'answer_by', r.window_end - make_interval(mins => r.duration_minutes), 'declined_by', r.declined_by) end)
  from public.rooms r where r.id = p_room
$$;

-- 房间页：一对一邀请的受邀人在说了不了、过期以后也能打开（通知里的链接），只是没有房间码和名单
create or replace function public.room_page(p_room uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  status text;
begin
  select * into r from public.rooms where id = p_room;
  status := public.room_status_of(p_room, me);
  if me is null or r.id is null or public.blocked_between(me, r.owner_id)
     or (r.visibility = 'private' and status is null and r.invitee_id is distinct from me) then
    return null;
  end if;
  return public.room_summary(p_room) || jsonb_build_object(
    'code', case when status is not null then r.code end,
    'members', case when status is not null then coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'waitlisted', m.waitlisted,
                                          'me', p.id = me) order by m.waitlisted, m.joined_at)
      from public.room_members m join public.profiles p on p.id = m.user_id where m.room_id = p_room), '[]') end);
end
$$;

-- ---------------------------------------------------------------------------
-- 回复、换个时间：不能约球的人拦下；说好时还要来得及
-- ---------------------------------------------------------------------------

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
  return jsonb_build_object('status', 'accepted', 'game_id', new_game);
end
$$;

create or replace function public.counter_invite(p_room uuid, p_venue text, p_window_start timestamptz, p_window_end timestamptz,
                                                 p_daypart text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  r public.rooms;
  w record;
  other uuid;
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

  select * into w from public.invite_window(coalesce(p_venue, r.venue_id), p_window_start, p_window_end, p_daypart);
  if w.exact and public.has_game_between(me, w.window_start, w.window_end) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  update public.rooms set venue_id = w.venue, starts_at = w.window_start, ends_at = w.window_end,
                          window_start = w.window_start, window_end = w.window_end, daypart = w.daypart, time_set = w.exact,
                          awaiting_id = other, invite_rounds = invite_rounds + 1, last_activity_at = now()
    where id = p_room;
  perform public.notify(other, 'invite_counter', '{name} suggested another time', '{when} · {court}. Open Badie to answer.',
    '/app/rooms/' || p_room || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = me))
      || public.window_slot(w.window_start, w.window_end, w.exact, w.venue));
end
$$;

-- 推荐时间：只给能约的人，或者两人之间已经有邀请（换个时间的时候）
create or replace function public.suggest_invite_window(p_user uuid, p_venue text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  venue text;
  tz text;
  earliest timestamptz := to_timestamp(ceil(extract(epoch from now() + interval '30 minutes') / 1800) * 1800);
  best record;
begin
  if me is null or p_user is null or me = p_user or public.hidden_from(me, p_user) or public.hidden_from(p_user, me)
     or not (public.invite_allowed(me, p_user) or public.invite_open_between(me, p_user)) then
    return null;
  end if;
  venue := coalesce((select v.id from public.venues v where v.id = p_venue and not v.hidden_pending_review),
                    public.play_suggestion(me, p_user) ->> 'venue_id',
                    (select f.venue_id from public.favorite_venues f where f.user_id = me order by f.created_at, f.venue_id limit 1));
  select coalesce(v.time_zone_id, 'UTC') into tz from public.venues v where v.id = venue;
  tz := coalesce(tz, 'UTC');

  select x.s, x.e into best
  from (
    select greatest(to_timestamp(ceil(extract(epoch from ((days.d + greatest((a ->> 'start')::time, (b ->> 'start')::time)) at time zone tz)) / 1800) * 1800),
                    earliest) as s,
           to_timestamp(floor(extract(epoch from ((days.d + least((a ->> 'end')::interval, (b ->> 'end')::interval)) at time zone tz)) / 1800) * 1800) as e
    from (select (now() at time zone tz)::date + i as d from generate_series(0, 6) i) days,
         jsonb_array_elements((select usual_times from public.profiles where id = me)) a,
         jsonb_array_elements((select usual_times from public.profiles where id = p_user)) b
    where (a ->> 'weekday')::int = extract(dow from days.d)::int + 1 and (b ->> 'weekday')::int = (a ->> 'weekday')::int) x
  where x.e - x.s >= interval '2 hours'
  order by x.s, x.e desc
  limit 1;
  if best.s is null then return null; end if;

  return jsonb_build_object(
    'window_start', best.s, 'window_end', best.e,
    -- 整段都在一个时段里时给出时段，方便客户端选中对应的选项
    'daypart', (select h.n from (values ('morning', 8, 12), ('afternoon', 14, 18), ('evening', 18, 22)) h (n, f, t)
                where (best.s at time zone tz)::date = (best.e at time zone tz)::date
                  and extract(epoch from (best.s at time zone tz)::time) >= h.f * 3600
                  and extract(epoch from (best.e at time zone tz)::time) <= h.t * 3600
                  and (best.e at time zone tz)::time <> '00:00'
                limit 1),
    'venue_id', venue, 'venue_name', (select v.name from public.venues v where v.id = venue));
end
$$;

-- ---------------------------------------------------------------------------
-- 到点：邀请只关还开着的；没定时间的球局有人签到或报过赛果就不取消
-- ---------------------------------------------------------------------------

create or replace function public.expire_rooms()
returns void language plpgsql security definer set search_path = '' as $$
declare
  r record;
begin
  for r in select id, starts_at, invitee_id from public.rooms
           where status = 'open'
             and ((invitee_id is null and ((starts_at is not null and starts_at <= now())
                                           or (starts_at is null and last_activity_at < now() - interval '30 minutes')))
                  or (invitee_id is not null and window_end - make_interval(mins => duration_minutes) <= now())) loop
    if r.invitee_id is not null then
      -- 同时有人说好时（已经成局）不动
      update public.rooms set status = 'closed', closed_reason = 'expired', awaiting_id = null where id = r.id and status = 'open';
      if found then delete from public.room_invites where room_id = r.id; end if;
    else
      perform public.close_room(r.id, case when r.starts_at is null then 'expired' else 'start_time_passed' end);
    end if;
  end loop;
  perform public.expire_unset_games();
end
$$;

create or replace function public.expire_unset_games()
returns void language plpgsql security definer set search_path = '' as $$
declare
  g record;
  player record;
begin
  for g in update public.games x set status = 'cancelled'
           where x.status = 'scheduled' and not x.time_set and x.window_end - make_interval(mins => x.duration_minutes) <= now()
             -- 有人签到或报过赛果：已经打了，不取消
             and not exists (select 1 from public.game_players gp where gp.game_id = x.id and gp.checked_in_at is not null)
             and not exists (select 1 from public.result_reports rr where rr.game_id = x.id)
           returning x.id, x.starts_at, x.ends_at, x.venue_id loop
    for player in select user_id from public.game_players where game_id = g.id and cancelled_at is null loop
      perform public.notify(player.user_id, 'cancelled', 'Game cancelled', 'No time was set for {when} · {court}, so it was cancelled.',
        '/app/games/', public.window_slot(g.starts_at, g.ends_at, false, g.venue_id));
    end loop;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 签到、报赛果：没定时间的球局
-- ---------------------------------------------------------------------------

-- 开赛前 30 分钟到结束之间签到。没定具体时间的：有人签到就按现在定下时间
-- （这个半点开始、不早于窗口开始、整场在窗口里，打 duration_minutes 分钟），和定时间一样告诉对方
create or replace function public.check_in(p_game uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  game public.games;
  new_start timestamptz;
  new_end timestamptz;
  player record;
begin
  update public.game_players gp set checked_in_at = coalesce(gp.checked_in_at, now())
    from public.games g
    where g.id = gp.game_id and gp.game_id = p_game and gp.user_id = me and g.status = 'scheduled'
      and now() between g.starts_at - interval '30 minutes' and g.ends_at;
  if not found then raise exception 'cannot_check_in' using errcode = 'P0002'; end if;

  -- 和定时间（set_game_time）同时发生时，等它做完再看
  select * into game from public.games where id = p_game for update;
  if game.time_set then return; end if;
  new_start := least(greatest(to_timestamp(floor(extract(epoch from now()) / 1800) * 1800), game.window_start),
                     game.window_end - make_interval(mins => game.duration_minutes));
  new_end := new_start + make_interval(mins => game.duration_minutes);
  update public.games set starts_at = new_start, ends_at = new_end, time_set = true where id = p_game;
  update public.rooms set starts_at = new_start, ends_at = new_end, time_set = true where game_id = p_game;
  for player in select user_id from public.game_players where game_id = p_game loop
    perform public.withdraw_invites_for(player.user_id, p_game);
    continue when player.user_id = me;
    perform public.notify(player.user_id, 'game_time_set', '{name} set the time', '{when} · {court}', '/app/games/' || p_game || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me)) || public.slot(new_start, game.venue_id));
  end loop;
end
$$;

-- 报赛果：没定具体时间的球局要先定时间（签到会自动定）
create or replace function public.report_result(p_game uuid, p_outcome public.result_outcome, p_score text default null,
                                                p_team1_games int default null, p_team2_games int default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  score text := nullif(btrim(coalesce(p_score, '')), '');
  outcome public.result_outcome := p_outcome;
begin
  if not exists (select 1 from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = auth.uid()
                 where g.id = p_game and g.status = 'scheduled' and now() between g.starts_at and g.ends_at + interval '7 days') then
    raise exception 'cannot_report' using errcode = 'P0002';
  end if;
  if not (select g.time_set from public.games g where g.id = p_game) then
    raise exception 'time_not_set' using errcode = '22023';
  end if;
  if score is not null and (char_length(score) > 40 or score !~ '^[0-9 :,/-]+$') then
    raise exception 'invalid_score' using errcode = '22023';
  end if;
  if (p_team1_games is null) <> (p_team2_games is null)
     or (p_team1_games is not null and (least(p_team1_games, p_team2_games) < 0 or p_team1_games + p_team2_games not between 1 and 30)) then
    raise exception 'invalid_games' using errcode = '22023';
  end if;
  if p_team1_games is not null then
    outcome := (case when p_team1_games > p_team2_games then 'team1' when p_team2_games > p_team1_games then 'team2' else 'friendly' end)::public.result_outcome;
  end if;
  perform 1 from public.games where id = p_game for update;
  if (select r.status from public.game_result(p_game) r) = 'verified' then raise exception 'result_locked' using errcode = '22023'; end if;
  insert into public.result_reports (game_id, reporter_id, outcome, score, team1_games, team2_games)
    values (p_game, auth.uid(), outcome, case when outcome is null then null else score end,
            case when outcome is not null then p_team1_games::smallint end, case when outcome is not null then p_team2_games::smallint end)
    on conflict (game_id, reporter_id) do update
      set outcome = excluded.outcome, score = excluded.score, team1_games = excluded.team1_games, team2_games = excluded.team2_games,
          updated_at = now();
  return (select r.status from public.game_result(p_game) r);
end
$$;
