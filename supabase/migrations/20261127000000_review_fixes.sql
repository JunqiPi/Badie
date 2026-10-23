-- 全面审查的修正（并发和查询）
-- - 本人已有同一时段的球局时不再匹配，确认时再查一次（接了挑战后旧请求还会配成局）
-- - 群聊推送不发给还没批准的申请人
-- - 球群候补递补加锁
-- - 补几处常用查询的索引

create or replace function public.match_ticket(p_ticket uuid, p_now timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  t public.match_tickets;
  my_rating numeric;
  my_gender public.gender;
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
  -- 本人这段时间已经有球局了（比如刚接了挑战）：不再配
  if public.has_game_between(t.user_id, t.starts_at, t.ends_at) then return null; end if;
  -- 混双各按各的等级比；其余按换算后的等级
  select case when t.mixed then rating else public.open_rating(rating, gender) end, gender into my_rating, my_gender
    from public.profiles where id = t.user_id;

  -- 候选：同模式（混双只配混双）、时间重叠 ≥ 30 分钟、有共同球馆、水平差在双方的容忍范围内（1 级 = 3 档）、
  -- 性别合双方的要求、双方都没排除对方、那段时间没有别的球局。优先：被退回的 > 水平接近 > 先来的。
  -- 混双男女各留 6 个候选，免得前几名全是同一性别
  with eligible as (
    select c.id, c.user_id, c.starts_at, c.ends_at, c.venue_ids, c.priority, c.skill_tolerance, c.excluded_user_ids,
           c.play_with, p.gender, x.rating, abs(x.rating - my_rating) as gap, c.created_at,
           row_number() over (order by c.priority desc, abs(x.rating - my_rating), c.created_at) as n,
           row_number() over (partition by p.gender order by c.priority desc, abs(x.rating - my_rating), c.created_at) as n_gender
    from public.match_tickets c join public.profiles p on p.id = c.user_id
    cross join lateral (select case when t.mixed then p.rating else public.open_rating(p.rating, p.gender) end as rating) x
    where c.status = 'searching' and c.mode = t.mode and c.mixed = t.mixed and c.user_id <> t.user_id and c.lock_at > p_now
      and c.starts_at <= t.ends_at - interval '30 minutes' and c.ends_at >= t.starts_at + interval '30 minutes'
      and c.venue_ids && t.venue_ids
      and not c.user_id = any (t.excluded_user_ids) and not t.user_id = any (c.excluded_user_ids)
      and public.accepts(t.play_with, p.gender) and public.accepts(c.play_with, my_gender)
      and (not t.mixed or p.gender is not null)
      and abs(round((x.rating - my_rating) * 3)) <= least(t.skill_tolerance, c.skill_tolerance) * 3
      and not public.has_game_between(c.user_id, t.starts_at, t.ends_at)),
  candidates as (select * from eligible where case when t.mixed then n_gender <= 6 else n <= 8 end)
  select case
    when t.mode = 'singles' then (select array[t.id, c.id] from candidates c order by c.priority desc, c.gap, c.created_at limit 1)
    -- 双打：另外三人彼此也要满足上面的条件（含性别要求），并且有一家四个人都能去的球馆；混双要两男两女。
    -- 被退回的多、水平集中的优先
    else (select array[t.id, a.id, b.id, c.id]
          from candidates a join candidates b on b.id > a.id join candidates c on c.id > b.id
          where a.user_id <> b.user_id and a.user_id <> c.user_id and b.user_id <> c.user_id
            and least(t.ends_at, a.ends_at, b.ends_at, c.ends_at) - greatest(t.starts_at, a.starts_at, b.starts_at, c.starts_at) >= interval '30 minutes'
            and exists (select 1 from unnest(t.venue_ids) v where v = any (a.venue_ids) and v = any (b.venue_ids) and v = any (c.venue_ids))
            and not array[a.user_id, b.user_id, c.user_id] && (a.excluded_user_ids || b.excluded_user_ids || c.excluded_user_ids)
            and public.accepts(a.play_with, b.gender) and public.accepts(b.play_with, a.gender)
            and public.accepts(a.play_with, c.gender) and public.accepts(c.play_with, a.gender)
            and public.accepts(b.play_with, c.gender) and public.accepts(c.play_with, b.gender)
            and (not t.mixed or (select count(*) filter (where g = 'male') = 2 and count(*) filter (where g = 'female') = 2
                                 from unnest(array[my_gender, a.gender, b.gender, c.gender]) g))
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

  -- 分队：按换算后的水平排第 1、4 的一队，第 2、3 的一队（单打就是各一队）。
  -- 混双：强的男生配弱一点的女生，另一队反过来。开了自动接受的直接算确认
  insert into public.match_seats (offer_id, user_id, ticket_id, team, response, respond_by, responded_at)
    select new_offer, m.user_id, m.id,
           case when t.mixed then case when (m.gender = 'male') = (m.rank_in_gender = 1) then 1 else 2 end
                when m.rank in (1, 4) then 1 else 2 end,
           case when m.auto_accept then 'accepted'::public.seat_response else 'pending' end,
           respond_by, case when m.auto_accept then p_now end
    from (select mt.*, p.gender,
                 row_number() over (order by public.open_rating(p.rating, p.gender) desc, mt.id) as rank,
                 row_number() over (partition by p.gender order by p.rating desc, mt.id) as rank_in_gender
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

create or replace function public.finalize_offer(p_offer uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  o public.match_offers;
  new_game uuid;
  seat record;
begin
  select * into o from public.match_offers where id = p_offer and status = 'open' for update;
  if o.id is null or exists (select 1 from public.match_seats where offer_id = p_offer and response <> 'accepted') then
    return null;
  end if;
  -- 确认期间有人约了同一时段的别的球局：这次不成，其余人重新排队
  if exists (select 1 from public.match_seats s where s.offer_id = p_offer and public.has_game_between(s.user_id, o.starts_at, o.ends_at)) then
    perform public.fail_offer(p_offer, now());
    return null;
  end if;

  insert into public.games (mode, starts_at, ends_at, venue_id, offer_id)
    values (o.mode, o.starts_at, o.ends_at, o.venue_id, o.id) returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, s.user_id, s.team, p.rating
    from public.match_seats s join public.profiles p on p.id = s.user_id where s.offer_id = p_offer;
  update public.match_offers set status = 'confirmed', game_id = new_game where id = p_offer;
  update public.match_tickets set status = 'matched', game_id = new_game, offer_id = null
    where id in (select ticket_id from public.match_seats where offer_id = p_offer);

  for seat in select user_id from public.match_seats where offer_id = p_offer loop
    perform public.notify(seat.user_id, 'matched', 'Game confirmed', '{when} · {court}. Everyone confirmed.',
      '/app/games/' || new_game || '/', public.slot(o.starts_at, o.venue_id));
  end loop;
  return new_game;
end
$$;

create or replace function public.queue_chat_push(p_kind text, p_id uuid, p_thread text, p_sender uuid, p_body text)
returns void language sql security definer set search_path = '' as $$
  with members as (
    select p_id as user_id where p_kind = 'dm'
    union select gp.user_id from public.game_players gp where p_kind = 'game' and gp.game_id = p_id
    union select m.user_id from public.group_members m where p_kind = 'group' and m.group_id = p_id and not m.pending
  ), info as (
    select coalesce((select nickname from public.profiles where id = p_sender), '') as sender,
           case p_kind when 'group' then (select name from public.play_groups where id = p_id)
                       when 'game' then (select v.name from public.games g join public.venues v on v.id = g.venue_id where g.id = p_id)
           end as place,
           case when p_kind <> 'dm' then (select count(*)::int from members) end as total
  )
  insert into public.chat_pushes (user_id, thread, sender_id, title, body, link, group_name, members)
  select m.user_id, p_thread, p_sender,
         case when p_kind = 'dm' then i.sender else coalesce(i.place, i.sender) end,
         case when p_kind = 'dm' then p_body else i.sender || ': ' || p_body end,
         '/messages/' || p_kind || '/' || case when p_kind = 'dm' then p_sender else p_id end || '/',
         i.place, i.total
  from members m cross join info i
  where m.user_id <> p_sender
    and exists (select 1 from public.push_devices d where d.user_id = m.user_id)
    and not exists (select 1 from public.blocks b
                    where (b.blocker = m.user_id and b.blocked = p_sender) or (b.blocker = p_sender and b.blocked = m.user_id))
$$;

create or replace function public.promote_waitlist(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  promoted uuid;
begin
  -- 锁住场次：两个人同时退出时只递补一次、不会补错人
  perform 1 from public.group_sessions where id = p_session for update;
  select gs.*, g.name, g.venue_id into s from public.group_sessions gs join public.play_groups g on g.id = gs.group_id where gs.id = p_session;
  if (select count(*) from public.session_signups where session_id = p_session and not waitlisted) >= s.capacity then return; end if;
  update public.session_signups set waitlisted = false
    where session_id = p_session and waitlisted and user_id = (select user_id from public.session_signups where session_id = p_session and waitlisted
                                                order by signed_up_at limit 1)
    returning user_id into promoted;
  if promoted is not null then
    perform public.notify(promoted, 'group', 'You’re in: {group}', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.',
      '/app/groups/' || s.group_id || '/', public.slot(s.starts_at, s.venue_id) || jsonb_build_object('group', s.name));
  end if;
end
$$;

-- related() 按人查匹配座位；资料卡算胜率按时间筛球局；未读通知数；评价提醒和邮件的定时任务
create index match_seats_user_idx on public.match_seats (user_id);
create index games_starts_idx on public.games (starts_at) where status = 'scheduled';
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;
create index games_review_pending_idx on public.games (ends_at) where status = 'scheduled' and not review_prompted;

-- 昵称里不能有 #：“Kai#12” 会被当成昵称 Kai、编号 12。写入时去掉（已有的昵称下次改名时生效）
create or replace function public.assign_tag()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.nickname := btrim(replace(new.nickname, '#', ''));
  if new.tag is null or exists (select 1 from public.profiles
                                where lower(nickname) = lower(new.nickname) and tag = new.tag and id <> new.id) then
    new.tag := public.free_tag(new.nickname, new.id);
  end if;
  if new.friend_code is null then new.friend_code := public.new_friend_code(); end if;
  return new;
end
$$;
