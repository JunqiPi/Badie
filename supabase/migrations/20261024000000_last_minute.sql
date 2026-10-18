-- 临时局：开赛前 2.5 小时内也能约（最晚开赛前 30 分钟），规则和 iOS 的 MatchTiming 一致。
-- - 普通请求开赛前 2 小时就结束了，所以临时局配到的都是此刻也在找人的球友
-- - 确认期限 5–10 分钟（离开赛不到 1 小时给 5 分钟），最晚开赛前 20 分钟全部确认，到点没约成就结束
-- - 普通请求到点没约成时，通知里提示可以转成临时局（客户端用同样的条件再发一次）

alter table public.match_tickets add column last_minute boolean not null default false;

-- 确认期限：开赛前 2.5 小时内按临时局给 5–10 分钟
create or replace function public.offer_respond_by(p_start timestamptz, p_now timestamptz, p_tz text)
returns timestamptz language sql stable set search_path = '' as $$
  select case
    when p_start - p_now < interval '150 minutes' then
      least(p_now + case when p_start - p_now < interval '1 hour' then interval '5 minutes' else interval '10 minutes' end,
            p_start - interval '20 minutes')
    else least(p_start - interval '2 hours', case
      when extract(hour from local) >= 23 then (date_trunc('day', local) + interval '1 day 9 hours') at time zone p_tz
      when extract(hour from local) < 8 then (date_trunc('day', local) + interval '9 hours') at time zone p_tz
      else raw end) end
  from (select raw, raw at time zone p_tz as local
        from (select p_now + case when p_start - p_now >= interval '26 hours' then interval '12 hours'
                                  when p_start - p_now >= interval '6 hours' then interval '2 hours'
                                  else interval '30 minutes' end as raw) r) w
$$;

-- 匹配：只改提议的锁定时间和最短确认时间（有临时局的组：开赛前 20 分钟、至少 3 分钟），其余不变
create or replace function public.match_ticket(p_ticket uuid, p_now timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  t public.match_tickets;
  my_rating numeric;
  picked uuid[];
  slot_start timestamptz;
  slot_end timestamptz;
  venue text;
  tz text;
  hurried boolean;
  offer_lock timestamptz;
  respond_by timestamptz;
  new_offer uuid;
  seat record;
begin
  select * into t from public.match_tickets
    where id = p_ticket and status = 'searching' and lock_at > p_now for update skip locked;
  if t.id is null then return null; end if;
  select rating into my_rating from public.profiles where id = t.user_id;

  -- 候选：同模式、时间重叠 ≥ 30 分钟、有共同球馆、水平差在双方的容忍范围内（1 级 = 3 档）、
  -- 双方都没排除对方、那段时间没有别的球局。优先：被退回的 > 水平接近 > 先来的
  with candidates as (
    select c.id, c.user_id, c.starts_at, c.ends_at, c.venue_ids, c.priority, c.skill_tolerance, c.excluded_user_ids,
           p.rating, abs(p.rating - my_rating) as gap, c.created_at
    from public.match_tickets c join public.profiles p on p.id = c.user_id
    where c.status = 'searching' and c.mode = t.mode and c.user_id <> t.user_id and c.lock_at > p_now
      and c.starts_at <= t.ends_at - interval '30 minutes' and c.ends_at >= t.starts_at + interval '30 minutes'
      and c.venue_ids && t.venue_ids
      and not c.user_id = any (t.excluded_user_ids) and not t.user_id = any (c.excluded_user_ids)
      and abs(round((p.rating - my_rating) * 3)) <= least(t.skill_tolerance, c.skill_tolerance) * 3
      and not public.has_game_between(c.user_id, t.starts_at, t.ends_at)
    order by c.priority desc, gap, c.created_at
    limit 8)
  select case
    when t.mode = 'singles' then (select array[t.id, c.id] from candidates c order by c.priority desc, c.gap, c.created_at limit 1)
    -- 双打：另外三人彼此也要满足上面的条件，并且有一家四个人都能去的球馆；被退回的多、水平集中的优先
    else (select array[t.id, a.id, b.id, c.id]
          from candidates a join candidates b on b.id > a.id join candidates c on c.id > b.id
          where a.user_id <> b.user_id and a.user_id <> c.user_id and b.user_id <> c.user_id
            and least(t.ends_at, a.ends_at, b.ends_at, c.ends_at) - greatest(t.starts_at, a.starts_at, b.starts_at, c.starts_at) >= interval '30 minutes'
            and exists (select 1 from unnest(t.venue_ids) v where v = any (a.venue_ids) and v = any (b.venue_ids) and v = any (c.venue_ids))
            and not array[a.user_id, b.user_id, c.user_id] && (a.excluded_user_ids || b.excluded_user_ids || c.excluded_user_ids)
            and round((greatest(a.rating, b.rating, c.rating, my_rating) - least(a.rating, b.rating, c.rating, my_rating)) * 3)
                <= least(t.skill_tolerance, a.skill_tolerance, b.skill_tolerance, c.skill_tolerance) * 3
          order by a.priority::int + b.priority::int + c.priority::int desc,
                   greatest(a.rating, b.rating, c.rating, my_rating) - least(a.rating, b.rating, c.rating, my_rating),
                   a.gap + b.gap + c.gap
          limit 1)
    end into picked;
  if picked is null then return null; end if;

  -- 锁住选中的请求；有人正被别的匹配占着就这轮放弃，下一轮再来
  if (select count(*) from (select 1 from public.match_tickets
                            where id = any (picked) and status = 'searching' for update skip locked) l) < cardinality(picked) then
    return null;
  end if;

  -- 时间：大家共同空闲的开头，最长 2 小时；球馆：按发起人的顺序，第一家大家都能去的
  select max(starts_at), least(min(ends_at), max(starts_at) + interval '2 hours'), bool_or(last_minute)
    into slot_start, slot_end, hurried
    from public.match_tickets where id = any (picked);
  select u.v into venue from unnest(t.venue_ids) with ordinality as u(v, n)
    where not exists (select 1 from public.match_tickets m where m.id = any (picked) and not u.v = any (m.venue_ids))
    order by u.n limit 1;
  select coalesce(time_zone_id, 'UTC') into tz from public.venues where id = venue;
  offer_lock := slot_start - case when hurried then interval '20 minutes' else interval '2 hours' end;
  respond_by := least(public.offer_respond_by(slot_start, p_now, tz), offer_lock);
  -- 来不及回复（普通局少于 10 分钟、临时局少于 3 分钟）就不发提议
  if respond_by - p_now < (case when hurried then interval '3 minutes' else interval '10 minutes' end) then return null; end if;

  insert into public.match_offers (mode, starts_at, ends_at, venue_id, lock_at)
    values (t.mode, slot_start, slot_end, venue, offer_lock) returning id into new_offer;

  -- 分队：按水平排第 1、4 的一队，第 2、3 的一队（单打就是各一队）；开了自动接受的直接算确认
  insert into public.match_seats (offer_id, user_id, ticket_id, team, response, respond_by, responded_at)
    select new_offer, m.user_id, m.id, case when m.rank in (1, 4) then 1 else 2 end,
           case when m.auto_accept then 'accepted'::public.seat_response else 'pending' end,
           respond_by, case when m.auto_accept then p_now end
    from (select mt.*, row_number() over (order by p.rating desc, mt.id) as rank
          from public.match_tickets mt join public.profiles p on p.id = mt.user_id where mt.id = any (picked)) m;
  update public.match_tickets set status = 'offered', offer_id = new_offer, priority = false where id = any (picked);

  if public.finalize_offer(new_offer) is not null then return new_offer; end if;

  for seat in select user_id, response from public.match_seats where offer_id = new_offer loop
    if seat.response = 'accepted' then
      perform public.notify(seat.user_id, 'offer_auto', 'Match found, accepted for you',
        '{when} · {court}. Waiting for the others to confirm.', '/app/play/', public.slot(slot_start, venue));
    else
      perform public.notify(seat.user_id, 'offer', 'Match found, please confirm', '{when} · {court}. Confirm by {by}.', '/app/play/',
        public.slot(slot_start, venue) || jsonb_build_object('by', jsonb_build_object('at', respond_by, 'tz', tz)));
    end if;
  end loop;
  return new_offer;
end
$$;

-- 到点没约成的普通请求：提示还可以转成临时局
create or replace function public.process_matchmaking(p_now timestamptz default now())
returns void language plpgsql security definer set search_path = '' as $$
declare
  seat record;
  item record;
begin
  -- 没在期限内回复：本人的请求暂停（不再给不在线的人发提议，回来点一下就继续），这组作废
  for seat in update public.match_seats s set response = 'expired'
              from public.match_offers o
              where o.id = s.offer_id and o.status = 'open' and s.response = 'pending' and s.respond_by <= p_now
              returning s.user_id, s.ticket_id, o.starts_at, o.venue_id loop
    update public.match_tickets set status = 'paused', offer_id = null where id = seat.ticket_id and status = 'offered';
    perform public.notify(seat.user_id, 'missed', 'You missed a match',
      '{when} · {court}. Your request is paused. Open Badie to keep looking.', '/app/play/', public.slot(seat.starts_at, seat.venue_id));
  end loop;

  for item in select o.id from public.match_offers o
              where o.status = 'open'
                and (o.lock_at <= p_now or exists (select 1 from public.match_seats s where s.offer_id = o.id and s.response = 'expired')) loop
    perform public.fail_offer(item.id, p_now);
  end loop;

  -- 到锁定时间还没约成：结束，不计入任何记录（正在确认中的等提议有结果再说）
  for item in update public.match_tickets set status = 'expired'
              where status in ('searching', 'paused') and lock_at <= p_now
              returning user_id, starts_at, venue_ids[1] as venue_id, last_minute loop
    perform public.notify(item.user_id, 'expired', 'No game this time',
      case when item.last_minute then 'We couldn’t find players for {when} · {court}. Nothing counts against you.'
           else 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.' end,
      '/app/play/', public.slot(item.starts_at, item.venue_id));
  end loop;

  for item in select id from public.match_tickets where status = 'searching' order by priority desc, created_at loop
    perform public.match_ticket(item.id, p_now);
  end loop;
end
$$;

-- 发起：最晚开赛前 30 分钟；2.5 小时内的是临时局（开赛前 20 分钟锁定）
create or replace function public.submit_ticket(p_mode public.game_mode, p_starts_at timestamptz, p_ends_at timestamptz,
                                                p_venue_ids text[], p_skill_tolerance int, p_auto_accept boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  venues text[];
  hurried boolean := p_starts_at < now() + interval '150 minutes';
  new_ticket uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if not exists (select 1 from public.profiles where id = me) then raise exception 'no_profile' using errcode = 'P0002'; end if;
  if p_starts_at < now() + interval '30 minutes' then raise exception 'too_soon' using errcode = '22023'; end if;
  if p_starts_at > now() + interval '14 days' then raise exception 'too_far' using errcode = '22023'; end if;
  if p_ends_at - p_starts_at not between interval '1 hour' and interval '8 hours'
     or extract(epoch from p_starts_at)::bigint % 1800 <> 0 or extract(epoch from p_ends_at)::bigint % 1800 <> 0 then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;

  -- 合并过的球馆换成保留的那家；隐藏的、不存在的去掉
  select array_agg(distinct coalesce(v.merged_into, v.id)) into venues
    from public.venues v where v.id = any (p_venue_ids) and not v.hidden_pending_review;
  if coalesce(cardinality(venues), 0) not between 1 and 3 then raise exception 'invalid_venues' using errcode = '22023'; end if;

  -- 防刷：同时最多 5 个在找的请求，每天最多发 20 个；同一时间不能重复约
  if (select count(*) from public.match_tickets where user_id = me and status in ('searching', 'offered', 'paused')) >= 5
     or (select count(*) from public.match_tickets where user_id = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;
  if exists (select 1 from public.match_tickets where user_id = me and status in ('searching', 'offered', 'paused')
             and starts_at < p_ends_at and p_starts_at < ends_at)
     or public.has_game_between(me, p_starts_at, p_ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  insert into public.match_tickets (user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, auto_accept, lock_at, last_minute)
    values (me, p_mode, p_starts_at, p_ends_at, venues, p_skill_tolerance, p_auto_accept,
            p_starts_at - case when hurried then interval '20 minutes' else interval '2 hours' end, hurried)
    returning id into new_ticket;
  perform public.match_ticket(new_ticket, now());
  return new_ticket;
end
$$;

create or replace function public.my_matchmaking()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at), '[]') from (
    select t.starts_at, jsonb_build_object(
      'id', t.id, 'mode', t.mode, 'starts_at', t.starts_at, 'ends_at', t.ends_at, 'status', t.status,
      'skill_tolerance', t.skill_tolerance, 'auto_accept', t.auto_accept, 'lock_at', t.lock_at, 'game_id', t.game_id,
      'last_minute', t.last_minute,
      'venues', (select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'tz', v.time_zone_id))
                 from public.venues v where v.id = any (t.venue_ids)),
      'offer', (select jsonb_build_object(
          'id', o.id, 'starts_at', o.starts_at, 'ends_at', o.ends_at, 'respond_by', me.respond_by, 'my_response', me.response,
          'lock_at', o.lock_at,
          'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id),
          'accepted', (select count(*) from public.match_seats s where s.offer_id = o.id and s.response = 'accepted'),
          'players', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'team', s.team,
                                                          'me', s.user_id = auth.uid()) order by s.team, p.rating desc)
                      from public.match_seats s join public.profiles p on p.id = s.user_id where s.offer_id = o.id))
        from public.match_offers o join public.venues v on v.id = o.venue_id
        join public.match_seats me on me.offer_id = o.id and me.user_id = auth.uid()
        where o.id = t.offer_id and o.status = 'open')
    ) as item
    from public.match_tickets t
    where t.user_id = auth.uid() and (t.status in ('searching', 'offered', 'paused') or t.lock_at > now() - interval '1 day')
  ) items
$$;

insert into public.notification_texts (locale, english, translated) values
  ('zh-Hans', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   '{when} · {court} 没找到合适的球友。不影响你的任何记录。还想打的话，可以转成临时局找此刻也在找人的球友。'),
  ('zh-Hant', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   '{when} · {court} 沒找到合適的球友。不影響你的任何紀錄。還想打的話，可以轉成臨時局找此刻也在找人的球友。'),
  ('ja', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   '{when} · {court} は相手が見つかりませんでした。記録には影響しません。まだプレーしたいなら、今すぐ探している人と今すぐゲームを試せます。'),
  ('ko', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   '{when} · {court}에 맞는 플레이어를 찾지 못했어요. 기록에는 영향이 없어요. 그래도 치고 싶다면 지금 찾고 있는 사람과 번개 게임을 해 보세요.'),
  ('id', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   'Kami tidak menemukan pemain untuk {when} · {court}. Tidak memengaruhi catatanmu. Masih mau main? Coba cari game dadakan.'),
  ('ms', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   'Kami tidak menemui pemain untuk {when} · {court}. Ia tidak menjejaskan rekod anda. Masih mahu bermain? Cuba cari permainan saat akhir.'),
  ('th', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   'ไม่พบผู้เล่นสำหรับ {when} · {court} ไม่มีผลต่อประวัติของคุณ ถ้ายังอยากเล่น ลองหาเกมด่วนกับคนที่กำลังหาอยู่ตอนนี้'),
  ('vi', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   'Không tìm được người chơi cho {when} · {court}. Không ảnh hưởng đến hồ sơ của bạn. Vẫn muốn chơi? Thử tìm trận gấp.'),
  ('hi', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   '{when} · {court} के लिए खिलाड़ी नहीं मिले। इसका आपके रिकॉर्ड पर कोई असर नहीं। अब भी खेलना है? लास्ट-मिनट सर्च आज़माएँ।');
