-- 按天看人：一次右滑很多张怎么办
-- - 同一天最多同时等 3 个人回复（单打邀请、双打邀请合起来算），超过报 too_many_invites
-- - 时间撞上我别的邀请也能发：谁先接受就和谁打；成局后，和这场时间重叠的其他邀请自动撤回，对方的请求接着找人，并收到通知

-- 我在这一天（按球馆时区）还在等回复的邀请个数
create function public.pending_invites(p_user uuid, p_starts_at timestamptz, p_tz text)
returns int language sql stable security definer set search_path = '' as $$
  select (select count(*) from public.match_offers o
          where o.invited_by = p_user and o.status = 'open'
            and (o.starts_at at time zone p_tz)::date = (p_starts_at at time zone p_tz)::date)::int
       + (select count(*) from public.room_invites i join public.rooms r on r.id = i.room_id
          where i.invited_by = p_user and r.status = 'open' and r.starts_at is not null
            and (r.starts_at at time zone p_tz)::date = (p_starts_at at time zone p_tz)::date
            and not exists (select 1 from public.room_members m where m.room_id = r.id and m.user_id = i.user_id))::int
$$;
revoke execute on function public.pending_invites(uuid, timestamptz, text) from public, anon, authenticated;

create or replace function public.invite_ticket(p_ticket uuid, p_venue text, p_starts_at timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  t public.match_tickets;
  slot_end timestamptz;
  hurried boolean;
  tz text;
  lock_time timestamptz;
  respond_by timestamptz;
  mine uuid;
  offer uuid;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  -- 同一个人的邀请排队处理：同时点两张卡不会都约上、时间撞在一起
  perform pg_advisory_xact_lock(hashtextextended('invite:' || me::text, 0));
  select * into t from public.match_tickets where id = p_ticket for update;
  if t.id is null or t.status <> 'searching' or t.mode <> 'singles' or t.lock_at <= now() + interval '30 minutes'
     or not public.can_invite(me, t)
     or exists (select 1 from public.candidate_skips s where s.viewer = me and s.ticket_id = t.id) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if not p_venue = any (t.venue_ids) or extract(epoch from p_starts_at)::bigint % 1800 <> 0 then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  slot_end := least(t.ends_at, p_starts_at + interval '2 hours');
  if p_starts_at < greatest(t.starts_at, now() + interval '30 minutes') or slot_end - p_starts_at < interval '1 hour' then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  -- 我这个时间正在找人的单打请求：直接用它去约（没约成会照常接着找）；别的撞车（等确认中的、暂停的、双打、已有球局）不行
  select id into mine from public.match_tickets
    where user_id = me and status = 'searching' and mode = 'singles' and starts_at < slot_end and p_starts_at < ends_at
    order by created_at limit 1;
  -- 时间撞上我别的邀请没关系（谁先接受就和谁打，其余的自动撤回）；撞上别的请求、已有球局不行
  if exists (select 1 from public.match_tickets m where m.user_id = me and m.status in ('searching', 'offered', 'paused')
             and m.starts_at < slot_end and p_starts_at < m.ends_at and m.id is distinct from mine
             and not (m.status = 'offered' and m.offer_id in (select o.id from public.match_offers o where o.invited_by = me and o.status = 'open')))
     or public.has_game_between(me, p_starts_at, slot_end) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  select coalesce(time_zone_id, 'UTC') into tz from public.venues where id = p_venue;
  if public.pending_invites(me, p_starts_at, tz) >= 3 then
    raise exception 'too_many_invites' using errcode = '54000';
  end if;
  if (select count(*) from public.match_tickets where user_id = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;

  hurried := p_starts_at < now() + interval '150 minutes';
  lock_time := p_starts_at - case when hurried then interval '20 minutes' else interval '2 hours' end;
  respond_by := least(public.offer_respond_by(p_starts_at, now(), tz), lock_time);
  if respond_by < now() + interval '3 minutes' then raise exception 'too_soon' using errcode = '22023'; end if;

  if mine is null then
    -- 只为这次邀请建的请求：没约成就自动取消（见 invite_only_tickets 触发器），不会变成我没设过的公开请求
    insert into public.match_tickets (user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, auto_accept, lock_at, last_minute, status, invite_only)
      values (me, 'singles', p_starts_at, slot_end, array[p_venue], 8, false, lock_time, hurried, 'offered', true)
      returning id into mine;
  else
    update public.match_tickets set status = 'offered' where id = mine;
  end if;
  insert into public.match_offers (mode, starts_at, ends_at, venue_id, lock_at, invited_by)
    values ('singles', p_starts_at, slot_end, p_venue, lock_time, me) returning id into offer;
  insert into public.match_seats (offer_id, user_id, ticket_id, team, response, respond_by, responded_at)
    values (offer, me, mine, 1, 'accepted', respond_by, now()), (offer, t.user_id, t.id, 2, 'pending', respond_by, null);
  update public.match_tickets set offer_id = offer where id = mine;
  update public.match_tickets set status = 'offered', offer_id = offer where id = t.id;
  insert into public.candidate_skips (viewer, ticket_id) values (me, t.id) on conflict do nothing;

  perform public.notify(t.user_id, 'offer', '{name} wants to play', '{when} · {court}. Confirm by {by}.', '/app/play/',
    public.slot(p_starts_at, p_venue) || jsonb_build_object('name', (select nickname from public.profiles where id = me),
                                                              'by', jsonb_build_object('at', respond_by, 'tz', tz)));
  return offer;
end
$$;


create or replace function public.invite_doubles(p_ticket uuid, p_venue text, p_starts_at timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  t public.match_tickets;
  slot_end timestamptz;
  mine int;
  theirs int;
  room uuid;
  tz text;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('invite:' || me::text, 0));
  select * into t from public.match_tickets where id = p_ticket for update;
  if t.id is null or t.status <> 'searching' or t.mode <> 'doubles' or t.lock_at <= now() + interval '30 minutes'
     or not public.can_invite(me, t)
     or exists (select 1 from public.candidate_skips s where s.viewer = me and s.ticket_id = t.id)
     -- 同一个人一天只约一次
     or exists (select 1 from public.room_invites i where i.invited_by = me and i.user_id = t.user_id and i.created_at > now() - interval '1 day') then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if not p_venue = any (t.venue_ids) or extract(epoch from p_starts_at)::bigint % 1800 <> 0 then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  slot_end := least(t.ends_at, p_starts_at + interval '2 hours');
  if p_starts_at < greatest(t.starts_at, now() + interval '30 minutes') or slot_end - p_starts_at < interval '1 hour' then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  if (select count(*) from public.room_invites where invited_by = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;
  select coalesce(time_zone_id, 'UTC') into tz from public.venues where id = p_venue;
  if public.pending_invites(me, p_starts_at, tz) >= 3 then
    raise exception 'too_many_invites' using errcode = '54000';
  end if;
  mine := public.room_level(me, t.play_with, t.mixed);
  theirs := public.room_level(t.user_id, t.play_with, t.mixed);
  room := public.create_room('doubles', 'public', p_venue, p_starts_at, slot_end,
                             greatest(1, least(mine, theirs) - 1), least(9, greatest(mine, theirs) + 1),
                             '{}', '', t.play_with, t.mixed);
  insert into public.room_invites (room_id, user_id, invited_by) values (room, t.user_id, me) on conflict do nothing;
  perform public.notify(t.user_id, 'room', '{name} invited you to play', '{when} · {court}. Open Badie to join.',
    '/app/rooms/' || room || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = me)) || coalesce(public.slot(p_starts_at, p_venue), '{}'));
  -- 这张卡片约过了，不再出现
  insert into public.candidate_skips (viewer, ticket_id) values (me, p_ticket) on conflict do nothing;
  return room;
end
$$;


-- 我成局了：和这场时间重叠、我发出去还在等回复的邀请自动撤回（这场本身的那份除外）
create function public.withdraw_overlapping_invites()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  g public.games;
  o record;
  seat record;
begin
  select * into g from public.games where id = new.game_id;
  for o in select mo.id, mo.starts_at, mo.venue_id from public.match_offers mo
           where mo.status = 'open' and mo.invited_by = new.user_id
             and mo.starts_at < g.ends_at and g.starts_at < mo.ends_at
             and not exists (select 1 from public.match_seats s
                             join public.game_players gp on gp.user_id = s.user_id and gp.game_id = new.game_id
                             where s.offer_id = mo.id and s.user_id <> new.user_id)
  loop
    update public.match_offers set status = 'failed' where id = o.id;
    -- 两边的请求都回到“在找人”（只为邀请建的那份会被 invite_only_tickets 触发器自动取消）
    update public.match_tickets m set status = 'searching', offer_id = null
      from public.match_seats s where s.offer_id = o.id and s.ticket_id = m.id and m.status = 'offered';
    for seat in select s.user_id from public.match_seats s where s.offer_id = o.id and s.user_id <> new.user_id loop
      perform public.notify(seat.user_id, 'requeued', 'Invite withdrawn', '{name} already has a game at {when}. Your request is still on.',
        '/app/play/', public.slot(o.starts_at, o.venue_id) || jsonb_build_object('name', (select nickname from public.profiles where id = new.user_id)));
    end loop;
  end loop;
  return null;
end
$$;
create trigger game_players_withdraw_invites after insert on public.game_players
  for each row execute function public.withdraw_overlapping_invites();

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', 'Invite withdrawn', '邀请已撤回'), ('zh-Hans', '{name} already has a game at {when}. Your request is still on.', '{name} 已经约到 {when} 的球了，你的请求还在继续找。'),
  ('zh-Hant', 'Invite withdrawn', '邀請已撤回'), ('zh-Hant', '{name} already has a game at {when}. Your request is still on.', '{name} 已經約到 {when} 的球了，你的請求還在繼續找。'),
  ('ja', 'Invite withdrawn', '誘いが取り消されました'), ('ja', '{name} already has a game at {when}. Your request is still on.', '{name} さんは {when} にすでに試合が決まりました。あなたのリクエストは引き続き探しています。'),
  ('ko', 'Invite withdrawn', '초대가 취소됐어요'), ('ko', '{name} already has a game at {when}. Your request is still on.', '{name}님은 {when}에 이미 게임이 잡혔어요. 내 요청은 계속 찾고 있어요.'),
  ('hi', 'Invite withdrawn', 'बुलावा वापस लिया गया'), ('hi', '{name} already has a game at {when}. Your request is still on.', '{name} का {when} पर पहले से गेम तय हो गया। आपकी रिक्वेस्ट अब भी चालू है।'),
  ('id', 'Invite withdrawn', 'Ajakan dibatalkan'), ('id', '{name} already has a game at {when}. Your request is still on.', '{name} sudah dapat permainan pada {when}. Permintaanmu masih berjalan.'),
  ('ms', 'Invite withdrawn', 'Ajakan ditarik balik'), ('ms', '{name} already has a game at {when}. Your request is still on.', '{name} sudah ada permainan pada {when}. Permintaan anda masih berjalan.'),
  ('th', 'Invite withdrawn', 'คำชวนถูกยกเลิก'), ('th', '{name} already has a game at {when}. Your request is still on.', '{name} ได้เกมตอน {when} แล้ว คำขอของคุณยังหาต่อให้อยู่'),
  ('vi', 'Invite withdrawn', 'Lời rủ đã bị rút lại'), ('vi', '{name} already has a game at {when}. Your request is still on.', '{name} đã có trận lúc {when}. Yêu cầu của bạn vẫn đang tìm tiếp.')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
