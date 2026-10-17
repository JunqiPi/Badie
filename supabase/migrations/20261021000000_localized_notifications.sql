-- 通知和邮件用收件人的语言：资料里记下界面语言（网页 / App 用什么语言就存什么）。
-- 通知文字写成英文模板 + 参数，写入时翻译成收件人的语言再填参数；时间按球馆当地时间、按语言的习惯格式

alter table public.profiles add column locale text not null default 'en'
  check (locale in ('en', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'id', 'ms', 'th', 'vi', 'hi'));
grant update (locale) on public.profiles to authenticated;

-- 英文模板 → 各语言译文（没有译文就用英文）
create table public.notification_texts (
  locale text not null,
  english text not null,
  translated text not null,
  primary key (locale, english)
);
alter table public.notification_texts enable row level security;
revoke all on public.notification_texts from anon, authenticated;
grant all on public.notification_texts to service_role;

-- 球馆当地时间：“Sat, Oct 18, 7:00 PM” / “10月18日 周六 19:00” / “T7, 18/10 19:00”
create function public.when_text(p_at timestamptz, p_tz text, p_locale text)
returns text language sql stable set search_path = '' as $$
  select case when f.pattern is null then to_char(t.l, 'Dy, Mon FMDD, FMHH12:MI AM')
    else replace(replace(replace(replace(f.pattern, '{M}', extract(month from t.l)::text), '{D}', extract(day from t.l)::text),
                         '{W}', f.days[extract(dow from t.l)::int + 1]), '{T}', to_char(t.l, f.clock)) end
  from (select p_at at time zone coalesce(p_tz, 'UTC') as l) t
  left join (values
    ('zh-Hans', '{M}月{D}日 {W} {T}', '{周日,周一,周二,周三,周四,周五,周六}'::text[], 'HH24:MI'),
    ('zh-Hant', '{M}月{D}日 {W} {T}', '{週日,週一,週二,週三,週四,週五,週六}', 'HH24:MI'),
    ('ja', '{M}月{D}日({W}) {T}', '{日,月,火,水,木,金,土}', 'HH24:MI'),
    ('ko', '{M}월 {D}일 ({W}) {T}', '{일,월,화,수,목,금,토}', 'HH24:MI'),
    ('id', '{W}, {D}/{M} {T}', '{Min,Sen,Sel,Rab,Kam,Jum,Sab}', 'HH24.MI'),
    ('ms', '{W}, {D}/{M} {T}', '{Ahd,Isn,Sel,Rab,Kha,Jum,Sab}', 'HH24:MI'),
    ('th', '{W} {D}/{M} {T}', '{อา.,จ.,อ.,พ.,พฤ.,ศ.,ส.}', 'HH24:MI'),
    ('vi', '{W}, {D}/{M} {T}', '{CN,T2,T3,T4,T5,T6,T7}', 'HH24:MI'),
    ('hi', '{W}, {D}/{M}, {T}', '{रवि,सोम,मंगल,बुध,गुरु,शुक्र,शनि}', 'FMHH12:MI am')
  ) f (locale, pattern, days, clock) on f.locale = p_locale
$$;

-- 翻译模板并一次性填参数（昵称里就算写了 {when} 也不会被再替换）：
-- 时间参数是 {"at": …, "tz": …}，其他参数原样填入
create function public.render_text(p_locale text, p_text text, p_params jsonb default '{}')
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(string_agg(case when jsonb_typeof(v) = 'object' then public.when_text((v ->> 'at')::timestamptz, v ->> 'tz', p_locale)
                                  when v is not null then v #>> '{}'
                                  else part end, '' order by n), '')
  from regexp_matches(coalesce((select translated from public.notification_texts where locale = p_locale and english = p_text), p_text),
                      '\{\w+\}|[^{]+|\{', 'g') with ordinality as m(token, n),
       lateral (select m.token[1] as part) p,
       lateral (select case when p.part ~ '^\{\w+\}$' then p_params -> substr(p.part, 2, length(p.part) - 2) end as v) x
$$;

-- 通知里的“时间 · 球馆”：{when} 是球馆当地时间，{court} 是球馆名
create function public.slot(p_start timestamptz, p_venue text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('when', jsonb_build_object('at', p_start, 'tz', coalesce(v.time_zone_id, 'UTC')), 'court', v.name)
  from public.venues v where v.id = p_venue
$$;

drop function public.notify(uuid, text, text, text, text);
create function public.notify(p_user uuid, p_kind text, p_title text, p_body text, p_link text default null, p_params jsonb default '{}')
returns void language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, kind, title, body, link)
  select p_user, p_kind, public.render_text(l.locale, p_title, p_params), public.render_text(l.locale, p_body, p_params), p_link
  from (select coalesce((select locale from public.profiles where id = p_user), 'en') as locale) l
$$;

-- ---------------------------------------------------------------------------
-- 发通知的函数改用模板 + 参数（其余逻辑不变）
-- ---------------------------------------------------------------------------

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

  insert into public.games (mode, starts_at, ends_at, venue_id, offer_id)
    values (o.mode, o.starts_at, o.ends_at, o.venue_id, o.id) returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, s.user_id, s.team, p.rating
    from public.match_seats s join public.profiles p on p.id = s.user_id where s.offer_id = p_offer;
  update public.match_offers set status = 'confirmed', game_id = new_game where id = p_offer;
  update public.match_tickets set status = 'matched', game_id = new_game, offer_id = null
    where id in (select ticket_id from public.match_seats where offer_id = p_offer);

  for seat in select user_id from public.match_seats where offer_id = p_offer loop
    perform public.notify(seat.user_id, 'matched', 'Game on!', '{when} · {court}. Everyone confirmed.',
      '/app/games/' || new_game || '/', public.slot(o.starts_at, o.venue_id));
  end loop;
  return new_game;
end
$$;

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
  select max(starts_at), least(min(ends_at), max(starts_at) + interval '2 hours') into slot_start, slot_end
    from public.match_tickets where id = any (picked);
  select u.v into venue from unnest(t.venue_ids) with ordinality as u(v, n)
    where not exists (select 1 from public.match_tickets m where m.id = any (picked) and not u.v = any (m.venue_ids))
    order by u.n limit 1;
  select coalesce(time_zone_id, 'UTC') into tz from public.venues where id = venue;
  respond_by := public.offer_respond_by(slot_start, p_now, tz);
  -- 来不及回复（少于 10 分钟）就不发提议
  if respond_by - p_now < interval '10 minutes' then return null; end if;

  insert into public.match_offers (mode, starts_at, ends_at, venue_id, lock_at)
    values (t.mode, slot_start, slot_end, venue, slot_start - interval '2 hours') returning id into new_offer;

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

create or replace function public.fail_offer(p_offer uuid, p_now timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare
  o public.match_offers;
  seat record;
begin
  select * into o from public.match_offers where id = p_offer and status = 'open' for update;
  if o.id is null then return; end if;
  update public.match_offers set status = 'failed' where id = p_offer;

  update public.match_tickets m
    set excluded_user_ids = array(select distinct x from unnest(m.excluded_user_ids || array(
          select s.user_id from public.match_seats s where s.offer_id = p_offer and s.user_id <> m.user_id)) x)
    where m.id in (select ticket_id from public.match_seats where offer_id = p_offer and response in ('declined', 'expired'));

  update public.match_tickets m set status = 'searching', offer_id = null, priority = s.response = 'accepted'
    from public.match_seats s
    where s.offer_id = p_offer and s.ticket_id = m.id and s.response in ('accepted', 'pending') and m.status = 'offered';

  for seat in select s.user_id, s.ticket_id from public.match_seats s join public.match_tickets m on m.id = s.ticket_id
              where s.offer_id = p_offer and s.response in ('accepted', 'pending') and m.status = 'searching' and m.lock_at > p_now loop
    perform public.notify(seat.user_id, 'requeued', 'Still looking',
      'Not everyone could make {when} · {court}. We’re finding you another game.', '/app/play/', public.slot(o.starts_at, o.venue_id));
    perform public.match_ticket(seat.ticket_id, p_now);
  end loop;
end
$$;

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
              returning user_id, starts_at, venue_ids[1] as venue_id loop
    perform public.notify(item.user_id, 'expired', 'No game this time',
      'We couldn’t find players for {when} · {court}. Nothing counts against you.', '/app/play/', public.slot(item.starts_at, item.venue_id));
  end loop;

  for item in select id from public.match_tickets where status = 'searching' order by priority desc, created_at loop
    perform public.match_ticket(item.id, p_now);
  end loop;
end
$$;

create or replace function public.cancel_game(p_game uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.games;
  other record;
  requeued boolean;
begin
  select * into g from public.games where id = p_game and status = 'scheduled' for update;
  if g.id is null or g.starts_at <= now()
     or not exists (select 1 from public.game_players where game_id = p_game and user_id = auth.uid()) then
    raise exception 'cannot_cancel' using errcode = 'P0002';
  end if;
  update public.game_players set cancelled_at = now(), late_cancel = g.starts_at - now() < interval '2 hours'
    where game_id = p_game and user_id = auth.uid();
  update public.games set status = 'cancelled' where id = p_game;

  for other in select gp.user_id from public.game_players gp where gp.game_id = p_game and gp.user_id <> auth.uid() loop
    update public.match_tickets set status = 'searching', game_id = null, priority = true
      where game_id = p_game and user_id = other.user_id and lock_at > now();
    requeued := found;
    perform public.notify(other.user_id, 'cancelled', 'Game cancelled',
      case when requeued then 'A player can’t make {when} · {court}. We’re finding you another game.' else 'A player can’t make {when} · {court}.' end,
      '/app/games/', public.slot(g.starts_at, g.venue_id));
  end loop;
  perform public.match_ticket(t.id, now()) from public.match_tickets t where t.game_id is null and t.status = 'searching'
    and t.id in (select ticket_id from public.match_seats where offer_id = g.offer_id);
end
$$;

create or replace function public.make_friends(a uuid, b uuid, p_title text, p_body text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.friendships (user_a, user_b) values (least(a, b), greatest(a, b)) on conflict do nothing;
  if not found then return; end if;
  delete from public.friend_requests where (from_id = a and to_id = b) or (from_id = b and to_id = a);
  perform public.notify(a, 'friend', p_title, p_body, '/app/players/' || b || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = b)));
  perform public.notify(b, 'friend', p_title, p_body, '/app/players/' || a || '/',
    jsonb_build_object('name', (select nickname from public.profiles where id = a)));
end
$$;

create or replace function public.prompt_reviews()
returns void language plpgsql security definer set search_path = '' as $$
declare
  g record;
  player record;
begin
  for g in update public.games set review_prompted = true
           where status = 'scheduled' and not review_prompted and ends_at <= now()
           returning id, starts_at, venue_id loop
    for player in select user_id from public.game_players where game_id = g.id loop
      perform public.notify(player.user_id, 'review', 'How was your game?',
        '{when} · {court}. Rate your partners within 48 hours. It stays private.', '/app/games/' || g.id || '/',
        public.slot(g.starts_at, g.venue_id));
    end loop;
  end loop;
end
$$;

create or replace function public.send_friend_request(p_user uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null or p_user = me or not public.related(me, p_user) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if public.are_friends(me, p_user) then return 'friends'; end if;
  if exists (select 1 from public.blocks where blocker = me and blocked = p_user) then raise exception 'blocked' using errcode = '42501'; end if;
  -- 被对方拉黑：照常显示“已申请”，不让对方知道
  if exists (select 1 from public.blocks where blocker = p_user and blocked = me) then return 'requested'; end if;
  if (select count(*) from public.friend_requests where from_id = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;
  if exists (select 1 from public.friend_requests where from_id = p_user and to_id = me) then
    perform public.make_friends(me, p_user, 'New friend', 'You and {name} are now friends.');
    return 'friends';
  end if;
  insert into public.friend_requests (from_id, to_id) values (me, p_user) on conflict do nothing;
  if found then
    perform public.notify(p_user, 'friend_request', 'Friend request', '{name} wants to be friends.', '/app/players/' || me || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me)));
  end if;
  return 'requested';
end
$$;

create or replace function public.promote_waitlist(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  promoted uuid;
begin
  select gs.*, g.name, g.venue_id into s from public.group_sessions gs join public.play_groups g on g.id = gs.group_id where gs.id = p_session;
  if (select count(*) from public.session_signups where session_id = p_session and not waitlisted) >= s.capacity then return; end if;
  update public.session_signups set waitlisted = false
    where session_id = p_session and user_id = (select user_id from public.session_signups where session_id = p_session and waitlisted
                                                order by signed_up_at limit 1)
    returning user_id into promoted;
  if promoted is not null then
    perform public.notify(promoted, 'group', 'You’re in: {group}', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.',
      '/app/groups/' || s.group_id || '/', public.slot(s.starts_at, s.venue_id) || jsonb_build_object('group', s.name));
  end if;
end
$$;

create or replace function public.join_group(p_group uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  g public.play_groups;
  level int;
  organizer record;
begin
  select * into g from public.play_groups where id = p_group;
  if me is null or g.id is null or public.blocked_between(me, g.owner_id) then raise exception 'group_not_found' using errcode = 'P0002'; end if;
  if exists (select 1 from public.group_members where group_id = p_group and user_id = me) then
    return public.group_role_of(p_group, me);
  end if;
  select round(rating) into level from public.profiles where id = me;
  if level is null or level not between g.level_min and g.level_max then raise exception 'level_out_of_range' using errcode = '22023'; end if;
  if (select count(*) from public.group_members where user_id = me) >= 20 then raise exception 'too_many_groups' using errcode = '54000'; end if;

  insert into public.group_members (group_id, user_id, pending) values (p_group, me, g.join_policy = 'approval');
  if g.join_policy = 'approval' then
    for organizer in select user_id from public.group_members where group_id = p_group and role in ('owner', 'organizer') loop
      perform public.notify(organizer.user_id, 'group', 'Join request: {group}', '{name} wants to join.', '/app/groups/' || p_group || '/',
        jsonb_build_object('group', g.name, 'name', (select nickname from public.profiles where id = me)));
    end loop;
    return 'pending';
  end if;
  return 'member';
end
$$;

create or replace function public.respond_join_request(p_group uuid, p_user uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_organizer(p_group, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  if p_accept then
    update public.group_members set pending = false, joined_at = now() where group_id = p_group and user_id = p_user and pending;
    if found then
      perform public.notify(p_user, 'group', 'Welcome to {group}', 'Your request was approved. You can sign up for sessions now.',
        '/app/groups/' || p_group || '/', jsonb_build_object('group', (select name from public.play_groups where id = p_group)));
    end if;
  else
    delete from public.group_members where group_id = p_group and user_id = p_user and pending;
  end if;
end
$$;

create or replace function public.cancel_session(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s record;
  player record;
begin
  select gs.*, g.name, g.venue_id into s from public.group_sessions gs join public.play_groups g on g.id = gs.group_id
    where gs.id = p_session and gs.cancelled_at is null and gs.starts_at > now();
  if s.id is null then raise exception 'session_closed' using errcode = 'P0002'; end if;
  if not public.is_organizer(s.group_id, auth.uid()) then raise exception 'not_organizer' using errcode = '42501'; end if;
  update public.group_sessions set cancelled_at = now() where id = p_session;
  for player in select user_id from public.session_signups where session_id = p_session and user_id <> auth.uid() loop
    perform public.notify(player.user_id, 'group', 'Session cancelled: {group}',
      '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '/app/groups/' || s.group_id || '/',
      public.slot(s.starts_at, s.venue_id) || jsonb_build_object('group', s.name));
  end loop;
end
$$;

create or replace function public.send_challenge(p_target uuid, p_venue text, p_starts_at timestamptz, p_ends_at timestamptz, p_message text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  availability text := public.challenge_availability(p_target);
  venue text;
  new_id uuid;
begin
  if availability = 'hidden' or not public.related(me, p_target) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if availability <> 'available' then raise exception '%', availability using errcode = '22023'; end if;
  if p_starts_at < now() + interval '2 hours' or p_starts_at > now() + interval '14 days' then raise exception 'too_soon' using errcode = '22023'; end if;
  if coalesce(p_message, '') ~* '(https?:|www\.|@|\d{7,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
  select coalesce(merged_into, id) into venue from public.venues where id = p_venue and not hidden_pending_review;
  if venue is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  if public.has_game_between(me, p_starts_at, p_ends_at) then raise exception 'overlapping' using errcode = '23P01'; end if;

  insert into public.challenges (challenger_id, target_id, venue_id, starts_at, ends_at, message, expires_at)
    values (me, p_target, venue, p_starts_at, p_ends_at, btrim(coalesce(p_message, '')),
            least(now() + interval '48 hours', p_starts_at - interval '1 hour'))
    returning id into new_id;
  perform public.notify(p_target, 'challenge', 'Singles challenge', '{name} challenged you: {when} · {court}.', '/app/games/',
    public.slot(p_starts_at, venue) || jsonb_build_object('name', (select nickname from public.profiles where id = me)));
  return new_id;
end
$$;

create or replace function public.respond_challenge(p_challenge uuid, p_accept boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  c public.challenges;
  new_game uuid;
begin
  select * into c from public.challenges where id = p_challenge and target_id = auth.uid() and status = 'pending' and expires_at > now() for update;
  if c.id is null then raise exception 'challenge_closed' using errcode = 'P0002'; end if;
  if not p_accept then
    update public.challenges set status = 'declined', responded_at = now() where id = p_challenge;
    return null;
  end if;
  if public.has_game_between(c.challenger_id, c.starts_at, c.ends_at) or public.has_game_between(c.target_id, c.starts_at, c.ends_at) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  insert into public.games (mode, starts_at, ends_at, venue_id) values ('singles', c.starts_at, c.ends_at, c.venue_id) returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, p.id, case when p.id = c.challenger_id then 1 else 2 end, p.rating
    from public.profiles p where p.id in (c.challenger_id, c.target_id);
  update public.challenges set status = 'accepted', responded_at = now(), game_id = new_game where id = p_challenge;
  perform public.notify(c.challenger_id, 'matched', 'Challenge accepted', '{name} is in: {when} · {court}.', '/app/games/' || new_game || '/',
    public.slot(c.starts_at, c.venue_id) || jsonb_build_object('name', (select nickname from public.profiles where id = c.target_id)));
  return new_game;
end
$$;

-- 邮件的结尾也用收件人的语言
create or replace function public.send_notification_emails()
returns void language plpgsql security definer set search_path = '' as $$
declare
  api_key text;
  emails jsonb;
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name = 'resend_api_key';
  if api_key is null then return; end if;

  with picked as (
    update public.notifications n set emailed_at = now()
    where n.id in (select id from public.notifications
                   where emailed_at is null and kind in ('offer', 'matched', 'cancelled', 'missed')
                     and created_at > now() - interval '1 hour'
                   order by id limit 100 for update skip locked)
    returning n.user_id, n.title, n.body, n.link)
  select jsonb_agg(jsonb_build_object(
      'from', 'Badie <games@badie.rsvp>',
      'to', jsonb_build_array(u.email),
      'subject', p.title,
      'text', p.body || E'\n\nhttps://badie.rsvp' || coalesce(p.link, '/app/') || E'\n\n—\n' ||
              public.render_text(coalesce(pr.locale, 'en'), 'You get this because you asked Badie to find you a game.')))
    into emails
    from picked p join auth.users u on u.id = p.user_id left join public.profiles pr on pr.id = p.user_id
    where u.email is not null;
  if emails is null then return; end if;

  perform net.http_post(url := 'https://api.resend.com/emails/batch', body := emails,
                        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'));
end
$$;

drop function public.slot_text(timestamptz, text);

revoke execute on function public.when_text(timestamptz, text, text), public.render_text(text, text, jsonb),
  public.slot(timestamptz, text), public.notify(uuid, text, text, text, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 译文
-- ---------------------------------------------------------------------------

insert into public.notification_texts (locale, english, translated) values
  ('zh-Hans', 'Game on!', '约成了！'),
  ('zh-Hans', '{when} · {court}. Everyone confirmed.', '{when} · {court}。大家都确认了。'),
  ('zh-Hans', 'Match found, accepted for you', '找到球友了，已替你接受'),
  ('zh-Hans', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court}。等其他人确认。'),
  ('zh-Hans', 'Match found, please confirm', '找到球友了，请确认'),
  ('zh-Hans', '{when} · {court}. Confirm by {by}.', '{when} · {court}。请在 {by} 前确认。'),
  ('zh-Hans', 'Still looking', '还在帮你找'),
  ('zh-Hans', 'Not everyone could make {when} · {court}. We’re finding you another game.', '{when} · {court} 有人去不了，正在帮你另找一场。'),
  ('zh-Hans', 'You missed a match', '错过了一次匹配'),
  ('zh-Hans', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court}。你的约球请求已暂停，打开 Badie 就能继续找。'),
  ('zh-Hans', 'No game this time', '这次没约到'),
  ('zh-Hans', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', '{when} · {court} 没找到合适的球友。不影响你的任何记录。'),
  ('zh-Hans', 'Game cancelled', '球局取消了'),
  ('zh-Hans', 'A player can’t make {when} · {court}.', '有球友去不了 {when} · {court} 了。'),
  ('zh-Hans', 'A player can’t make {when} · {court}. We’re finding you another game.', '有球友去不了 {when} · {court} 了，正在帮你另找一场。'),
  ('zh-Hans', 'You both want to play again', '你们都想再约'),
  ('zh-Hans', 'You and {name} are now friends. Message them to set up the next game.', '你和 {name} 成了球友，发个消息约下一场吧。'),
  ('zh-Hans', 'New friend', '新球友'),
  ('zh-Hans', 'You and {name} are now friends.', '你和 {name} 成了球友。'),
  ('zh-Hans', 'How was your game?', '这场球打得怎么样？'),
  ('zh-Hans', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court}。48 小时内给球友评价，内容不公开。'),
  ('zh-Hans', 'A tip from recent games', '来自最近几场球的小提醒'),
  ('zh-Hans', 'Keep an eye on the people around you and keep your swings safe.', '挥拍时留意身边的人，注意安全。'),
  ('zh-Hans', 'Keep it friendly on court. Everyone is here to enjoy the game.', '场上友好交流，大家都是来享受打球的。'),
  ('zh-Hans', 'In doubles, share the court and let your partner play their shots.', '双打时注意分区，让搭档也有球打。'),
  ('zh-Hans', 'Settle up court fees soon after the game.', '打完球记得及时结清场地费。'),
  ('zh-Hans', 'Friend request', '好友申请'),
  ('zh-Hans', '{name} wants to be friends.', '{name} 想加你为球友。'),
  ('zh-Hans', 'You’re in: {group}', '候补成功：{group}'),
  ('zh-Hans', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', '{when} · {court} 空出了位置，你已报上名。去不了请尽早取消。'),
  ('zh-Hans', 'Join request: {group}', '入群申请：{group}'),
  ('zh-Hans', '{name} wants to join.', '{name} 申请加入。'),
  ('zh-Hans', 'Welcome to {group}', '欢迎加入 {group}'),
  ('zh-Hans', 'Your request was approved. You can sign up for sessions now.', '你的申请已通过，现在可以报名了。'),
  ('zh-Hans', 'Session cancelled: {group}', '活动取消：{group}'),
  ('zh-Hans', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '组织者取消了 {when} · {court} 这场。不影响你的任何记录。'),
  ('zh-Hans', 'Singles challenge', '单打挑战'),
  ('zh-Hans', '{name} challenged you: {when} · {court}.', '{name} 向你发起挑战：{when} · {court}。'),
  ('zh-Hans', 'Challenge accepted', '挑战已接受'),
  ('zh-Hans', '{name} is in: {when} · {court}.', '{name} 接受了挑战：{when} · {court}。'),
  ('zh-Hans', 'You get this because you asked Badie to find you a game.', '你收到这封邮件，是因为你在 Badie 上发起了约球。'),
  ('zh-Hant', 'Game on!', '約成了！'),
  ('zh-Hant', '{when} · {court}. Everyone confirmed.', '{when} · {court}。大家都確認了。'),
  ('zh-Hant', 'Match found, accepted for you', '配對成功，已幫你接受'),
  ('zh-Hant', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court}。正在等其他人確認。'),
  ('zh-Hant', 'Match found, please confirm', '配對成功，請確認'),
  ('zh-Hant', '{when} · {court}. Confirm by {by}.', '{when} · {court}。請在 {by} 前確認。'),
  ('zh-Hant', 'Still looking', '繼續幫你找'),
  ('zh-Hant', 'Not everyone could make {when} · {court}. We’re finding you another game.', '{when} · {court} 有人去不了。我們正在幫你找其他球局。'),
  ('zh-Hant', 'You missed a match', '你錯過了一次配對'),
  ('zh-Hant', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court}。你的請求已暫停，打開 Badie 繼續找。'),
  ('zh-Hant', 'No game this time', '這次沒約成'),
  ('zh-Hant', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', '{when} · {court} 沒有找到球友。這不會對你有任何影響。'),
  ('zh-Hant', 'Game cancelled', '球局已取消'),
  ('zh-Hant', 'A player can’t make {when} · {court}.', '有一位球友無法參加 {when} · {court}。'),
  ('zh-Hant', 'A player can’t make {when} · {court}. We’re finding you another game.', '有一位球友無法參加 {when} · {court}。我們正在幫你找其他球局。'),
  ('zh-Hant', 'You both want to play again', '你們都想再一起打球'),
  ('zh-Hant', 'You and {name} are now friends. Message them to set up the next game.', '你和 {name} 已經是球友了。傳訊息約下一場吧。'),
  ('zh-Hant', 'New friend', '多了一位球友'),
  ('zh-Hant', 'You and {name} are now friends.', '你和 {name} 已經是球友了。'),
  ('zh-Hant', 'How was your game?', '球打得怎麼樣？'),
  ('zh-Hant', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court}。請在 48 小時內評價一起打的球友，內容保密。'),
  ('zh-Hant', 'A tip from recent games', '來自最近球局的小提醒'),
  ('zh-Hant', 'Keep an eye on the people around you and keep your swings safe.', '留意身邊的人，揮拍注意安全。'),
  ('zh-Hant', 'Keep it friendly on court. Everyone is here to enjoy the game.', '場上保持友善，大家都是來享受打球的。'),
  ('zh-Hant', 'In doubles, share the court and let your partner play their shots.', '打雙打時記得分享場地，讓搭檔也打自己的球。'),
  ('zh-Hant', 'Settle up court fees soon after the game.', '打完球後記得盡快結清場地費。'),
  ('zh-Hant', 'Friend request', '好友申請'),
  ('zh-Hant', '{name} wants to be friends.', '{name} 想加你為球友。'),
  ('zh-Hant', 'You’re in: {group}', '遞補成功：{group}'),
  ('zh-Hant', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', '{when} · {court} 有空位了。如果去不了，請提早取消。'),
  ('zh-Hant', 'Join request: {group}', '加入申請：{group}'),
  ('zh-Hant', '{name} wants to join.', '{name} 想加入。'),
  ('zh-Hant', 'Welcome to {group}', '歡迎加入 {group}'),
  ('zh-Hant', 'Your request was approved. You can sign up for sessions now.', '你的申請已通過，現在可以報名場次了。'),
  ('zh-Hant', 'Session cancelled: {group}', '場次已取消：{group}'),
  ('zh-Hant', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '{when} · {court} 已被組織者取消。這不會對你有任何影響。'),
  ('zh-Hant', 'Singles challenge', '單打挑戰'),
  ('zh-Hant', '{name} challenged you: {when} · {court}.', '{name} 向你發起挑戰：{when} · {court}。'),
  ('zh-Hant', 'Challenge accepted', '挑戰已接受'),
  ('zh-Hant', '{name} is in: {when} · {court}.', '{name} 應戰了：{when} · {court}。'),
  ('zh-Hant', 'You get this because you asked Badie to find you a game.', '你會收到這封信，是因為你請 Badie 幫你找球局。'),
  ('ja', 'Game on!', 'ゲーム成立！'),
  ('ja', '{when} · {court}. Everyone confirmed.', '{when} · {court}。全員が確定しました。'),
  ('ja', 'Match found, accepted for you', 'マッチが見つかり、自動で承諾しました'),
  ('ja', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court}。ほかのプレイヤーの確定を待っています。'),
  ('ja', 'Match found, please confirm', 'マッチが見つかりました。確定してください'),
  ('ja', '{when} · {court}. Confirm by {by}.', '{when} · {court}。{by} までに確定してください。'),
  ('ja', 'Still looking', '引き続き探しています'),
  ('ja', 'Not everyone could make {when} · {court}. We’re finding you another game.', '{when} · {court} は全員の都合が合いませんでした。別のゲームを探しています。'),
  ('ja', 'You missed a match', 'マッチを逃しました'),
  ('ja', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court}。リクエストは一時停止中です。探し続けるには Badie を開いてください。'),
  ('ja', 'No game this time', '今回は相手が見つかりませんでした'),
  ('ja', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', '{when} · {court} のプレイヤーが見つかりませんでした。不利になることはありません。'),
  ('ja', 'Game cancelled', 'ゲームが中止になりました'),
  ('ja', 'A player can’t make {when} · {court}.', '{when} · {court} に参加できなくなったプレイヤーがいます。'),
  ('ja', 'A player can’t make {when} · {court}. We’re finding you another game.', '{when} · {court} に参加できなくなったプレイヤーがいます。別のゲームを探しています。'),
  ('ja', 'You both want to play again', 'お互いに「また一緒に」を選びました'),
  ('ja', 'You and {name} are now friends. Message them to set up the next game.', '{name} さんと友達になりました。メッセージを送って次のゲームを決めましょう。'),
  ('ja', 'New friend', '新しい友達'),
  ('ja', 'You and {name} are now friends.', '{name} さんと友達になりました。'),
  ('ja', 'How was your game?', 'ゲームはどうでしたか？'),
  ('ja', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court}。48 時間以内に一緒にプレーした人を評価してください。評価は非公開です。'),
  ('ja', 'A tip from recent games', '最近のゲームからのアドバイス'),
  ('ja', 'Keep an eye on the people around you and keep your swings safe.', '周りの人に気を配り、安全にスイングしましょう。'),
  ('ja', 'Keep it friendly on court. Everyone is here to enjoy the game.', 'コートでは和やかにいきましょう。みんなプレーを楽しみに来ています。'),
  ('ja', 'In doubles, share the court and let your partner play their shots.', 'ダブルスではコートを分け合い、パートナーにも打たせてあげましょう。'),
  ('ja', 'Settle up court fees soon after the game.', 'コート代はゲーム後すぐに精算しましょう。'),
  ('ja', 'Friend request', '友達リクエスト'),
  ('ja', '{name} wants to be friends.', '{name} さんから友達リクエストが届きました。'),
  ('ja', 'You’re in: {group}', '参加確定：{group}'),
  ('ja', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', '{when} · {court} に空きが出ました。参加できない場合は早めにキャンセルしてください。'),
  ('ja', 'Join request: {group}', '参加リクエスト：{group}'),
  ('ja', '{name} wants to join.', '{name} さんが参加を希望しています。'),
  ('ja', 'Welcome to {group}', '{group} へようこそ'),
  ('ja', 'Your request was approved. You can sign up for sessions now.', 'リクエストが承認されました。各回に申し込めるようになりました。'),
  ('ja', 'Session cancelled: {group}', '開催中止：{group}'),
  ('ja', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '{when} · {court} は主催者により中止になりました。不利になることはありません。'),
  ('ja', 'Singles challenge', 'シングルスの挑戦'),
  ('ja', '{name} challenged you: {when} · {court}.', '{name} さんから挑戦が届きました：{when} · {court}。'),
  ('ja', 'Challenge accepted', '挑戦が承諾されました'),
  ('ja', '{name} is in: {when} · {court}.', '{name} さんが承諾しました：{when} · {court}。'),
  ('ja', 'You get this because you asked Badie to find you a game.', 'Badie にゲーム探しをリクエストしたため、このメールをお送りしています。'),
  ('ko', 'Game on!', '게임 성사!'),
  ('ko', '{when} · {court}. Everyone confirmed.', '{when} · {court}. 모두 확정했어요.'),
  ('ko', 'Match found, accepted for you', '매칭됐어요, 자동으로 수락했어요'),
  ('ko', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court}. 다른 플레이어의 확정을 기다리는 중이에요.'),
  ('ko', 'Match found, please confirm', '매칭됐어요, 확정해 주세요'),
  ('ko', '{when} · {court}. Confirm by {by}.', '{when} · {court}. {by}까지 확정해 주세요.'),
  ('ko', 'Still looking', '계속 찾는 중이에요'),
  ('ko', 'Not everyone could make {when} · {court}. We’re finding you another game.', '{when} · {court}에 모두가 올 수는 없었어요. 다른 게임을 찾고 있어요.'),
  ('ko', 'You missed a match', '매칭을 놓쳤어요'),
  ('ko', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court}. 요청이 일시 중지됐어요. 계속 찾으려면 Badie를 여세요.'),
  ('ko', 'No game this time', '이번엔 게임이 없어요'),
  ('ko', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', '{when} · {court}에 맞는 플레이어를 찾지 못했어요. 불이익은 없어요.'),
  ('ko', 'Game cancelled', '게임이 취소됐어요'),
  ('ko', 'A player can’t make {when} · {court}.', '한 플레이어가 {when} · {court}에 올 수 없게 됐어요.'),
  ('ko', 'A player can’t make {when} · {court}. We’re finding you another game.', '한 플레이어가 {when} · {court}에 올 수 없게 됐어요. 다른 게임을 찾고 있어요.'),
  ('ko', 'You both want to play again', '서로 다시 치고 싶어 해요'),
  ('ko', 'You and {name} are now friends. Message them to set up the next game.', '이제 {name} 님과 친구가 됐어요. 메시지를 보내 다음 게임을 잡아 보세요.'),
  ('ko', 'New friend', '새 친구'),
  ('ko', 'You and {name} are now friends.', '이제 {name} 님과 친구가 됐어요.'),
  ('ko', 'How was your game?', '게임은 어땠나요?'),
  ('ko', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court}. 48시간 안에 함께 친 플레이어를 평가해 주세요. 평가는 비공개예요.'),
  ('ko', 'A tip from recent games', '최근 게임에서 드리는 팁'),
  ('ko', 'Keep an eye on the people around you and keep your swings safe.', '주변 사람을 잘 살피고 안전하게 스윙해 주세요.'),
  ('ko', 'Keep it friendly on court. Everyone is here to enjoy the game.', '코트에서는 서로 친절하게 대해 주세요. 모두 게임을 즐기러 온 거예요.'),
  ('ko', 'In doubles, share the court and let your partner play their shots.', '복식에서는 코트를 나눠 쓰고, 파트너가 칠 공은 파트너에게 맡겨 주세요.'),
  ('ko', 'Settle up court fees soon after the game.', '게임이 끝나면 코트비를 빨리 정산해 주세요.'),
  ('ko', 'Friend request', '친구 요청'),
  ('ko', '{name} wants to be friends.', '{name} 님이 친구가 되고 싶어 해요.'),
  ('ko', 'You’re in: {group}', '참석 확정: {group}'),
  ('ko', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', '{when} · {court}에 자리가 났어요. 못 가게 되면 미리 취소해 주세요.'),
  ('ko', 'Join request: {group}', '가입 신청: {group}'),
  ('ko', '{name} wants to join.', '{name} 님이 가입을 신청했어요.'),
  ('ko', 'Welcome to {group}', '{group}에 오신 걸 환영해요'),
  ('ko', 'Your request was approved. You can sign up for sessions now.', '가입 신청이 승인됐어요. 이제 일정에 신청할 수 있어요.'),
  ('ko', 'Session cancelled: {group}', '일정 취소: {group}'),
  ('ko', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '운영자가 {when} · {court} 일정을 취소했어요. 불이익은 없어요.'),
  ('ko', 'Singles challenge', '단식 도전'),
  ('ko', '{name} challenged you: {when} · {court}.', '{name} 님이 도전을 보냈어요: {when} · {court}.'),
  ('ko', 'Challenge accepted', '도전 수락'),
  ('ko', '{name} is in: {when} · {court}.', '{name} 님이 수락했어요: {when} · {court}.'),
  ('ko', 'You get this because you asked Badie to find you a game.', 'Badie에 게임 찾기를 요청하셔서 보내 드리는 메일이에요.'),
  ('id', 'Game on!', 'Game jadi!'),
  ('id', '{when} · {court}. Everyone confirmed.', '{when} · {court}. Semua sudah konfirmasi.'),
  ('id', 'Match found, accepted for you', 'Match ditemukan, otomatis diterima'),
  ('id', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court}. Menunggu konfirmasi pemain lain.'),
  ('id', 'Match found, please confirm', 'Match ditemukan, silakan konfirmasi'),
  ('id', '{when} · {court}. Confirm by {by}.', '{when} · {court}. Konfirmasi paling lambat {by}.'),
  ('id', 'Still looking', 'Masih mencari'),
  ('id', 'Not everyone could make {when} · {court}. We’re finding you another game.', 'Tidak semua pemain bisa ikut {when} · {court}. Kami sedang mencarikan game lain untukmu.'),
  ('id', 'You missed a match', 'Kamu melewatkan match'),
  ('id', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court}. Permintaanmu dijeda. Buka Badie untuk terus mencari.'),
  ('id', 'No game this time', 'Tidak ada game kali ini'),
  ('id', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', 'Kami tidak menemukan pemain untuk {when} · {court}. Ini tidak merugikanmu.'),
  ('id', 'Game cancelled', 'Game dibatalkan'),
  ('id', 'A player can’t make {when} · {court}.', 'Ada pemain yang tidak bisa ikut {when} · {court}.'),
  ('id', 'A player can’t make {when} · {court}. We’re finding you another game.', 'Ada pemain yang tidak bisa ikut {when} · {court}. Kami sedang mencarikan game lain untukmu.'),
  ('id', 'You both want to play again', 'Kalian sama-sama mau main lagi'),
  ('id', 'You and {name} are now friends. Message them to set up the next game.', 'Kamu dan {name} sekarang berteman. Kirim pesan untuk mengatur game berikutnya.'),
  ('id', 'New friend', 'Teman baru'),
  ('id', 'You and {name} are now friends.', 'Kamu dan {name} sekarang berteman.'),
  ('id', 'How was your game?', 'Bagaimana game-mu?'),
  ('id', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court}. Nilai partnermu dalam 48 jam. Penilaianmu tetap privat.'),
  ('id', 'A tip from recent games', 'Saran dari game terbaru'),
  ('id', 'Keep an eye on the people around you and keep your swings safe.', 'Perhatikan orang di sekitarmu dan pastikan ayunan raketmu aman.'),
  ('id', 'Keep it friendly on court. Everyone is here to enjoy the game.', 'Jaga suasana tetap ramah di lapangan. Semua orang datang untuk menikmati permainan.'),
  ('id', 'In doubles, share the court and let your partner play their shots.', 'Saat main ganda, berbagilah lapangan dan biarkan partnermu memainkan pukulannya.'),
  ('id', 'Settle up court fees soon after the game.', 'Lunasi biaya lapangan segera setelah game.'),
  ('id', 'Friend request', 'Permintaan pertemanan'),
  ('id', '{name} wants to be friends.', '{name} ingin berteman.'),
  ('id', 'You’re in: {group}', 'Kamu ikut: {group}'),
  ('id', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', 'Ada slot kosong untuk {when} · {court}. Kalau tidak bisa datang, batalkan lebih awal.'),
  ('id', 'Join request: {group}', 'Permintaan bergabung: {group}'),
  ('id', '{name} wants to join.', '{name} ingin bergabung.'),
  ('id', 'Welcome to {group}', 'Selamat datang di {group}'),
  ('id', 'Your request was approved. You can sign up for sessions now.', 'Permintaanmu disetujui. Sekarang kamu bisa mendaftar ke sesi.'),
  ('id', 'Session cancelled: {group}', 'Sesi dibatalkan: {group}'),
  ('id', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '{when} · {court} dibatalkan oleh penyelenggara. Ini tidak merugikanmu.'),
  ('id', 'Singles challenge', 'Tantangan tunggal'),
  ('id', '{name} challenged you: {when} · {court}.', '{name} menantangmu: {when} · {court}.'),
  ('id', 'Challenge accepted', 'Tantangan diterima'),
  ('id', '{name} is in: {when} · {court}.', '{name} ikut: {when} · {court}.'),
  ('id', 'You get this because you asked Badie to find you a game.', 'Kamu menerima ini karena meminta Badie mencarikan game untukmu.'),
  ('ms', 'Game on!', 'Permainan jadi!'),
  ('ms', '{when} · {court}. Everyone confirmed.', '{when} · {court}. Semua orang sudah sahkan.'),
  ('ms', 'Match found, accepted for you', 'Padanan ditemui, diterima untuk anda'),
  ('ms', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court}. Menunggu yang lain mengesahkan.'),
  ('ms', 'Match found, please confirm', 'Padanan ditemui, sila sahkan'),
  ('ms', '{when} · {court}. Confirm by {by}.', '{when} · {court}. Sahkan sebelum {by}.'),
  ('ms', 'Still looking', 'Masih mencari'),
  ('ms', 'Not everyone could make {when} · {court}. We’re finding you another game.', 'Bukan semua orang dapat hadir pada {when} · {court}. Kami sedang carikan permainan lain untuk anda.'),
  ('ms', 'You missed a match', 'Anda terlepas padanan'),
  ('ms', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court}. Permintaan anda dijeda. Buka Badie untuk terus mencari.'),
  ('ms', 'No game this time', 'Tiada permainan kali ini'),
  ('ms', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', 'Kami tidak menemui pemain untuk {when} · {court}. Ini tidak menjejaskan rekod anda.'),
  ('ms', 'Game cancelled', 'Permainan dibatalkan'),
  ('ms', 'A player can’t make {when} · {court}.', 'Seorang pemain tidak dapat hadir pada {when} · {court}.'),
  ('ms', 'A player can’t make {when} · {court}. We’re finding you another game.', 'Seorang pemain tidak dapat hadir pada {when} · {court}. Kami sedang carikan permainan lain untuk anda.'),
  ('ms', 'You both want to play again', 'Anda berdua mahu main lagi'),
  ('ms', 'You and {name} are now friends. Message them to set up the next game.', 'Anda dan {name} kini berkawan. Hantar mesej kepadanya untuk atur permainan seterusnya.'),
  ('ms', 'New friend', 'Rakan baharu'),
  ('ms', 'You and {name} are now friends.', 'Anda dan {name} kini berkawan.'),
  ('ms', 'How was your game?', 'Bagaimana permainan anda?'),
  ('ms', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court}. Nilai rakan main anda dalam masa 48 jam. Ia kekal sulit.'),
  ('ms', 'A tip from recent games', 'Tip daripada permainan baru-baru ini'),
  ('ms', 'Keep an eye on the people around you and keep your swings safe.', 'Perhatikan orang di sekeliling anda dan pastikan hayunan anda selamat.'),
  ('ms', 'Keep it friendly on court. Everyone is here to enjoy the game.', 'Kekal mesra di gelanggang. Semua orang datang untuk menikmati permainan.'),
  ('ms', 'In doubles, share the court and let your partner play their shots.', 'Dalam beregu, kongsi gelanggang dan beri pasangan anda peluang membuat pukulannya.'),
  ('ms', 'Settle up court fees soon after the game.', 'Bayar bahagian sewa gelanggang anda sejurus selepas permainan.'),
  ('ms', 'Friend request', 'Permintaan rakan'),
  ('ms', '{name} wants to be friends.', '{name} mahu menjadi rakan anda.'),
  ('ms', 'You’re in: {group}', 'Anda dapat tempat: {group}'),
  ('ms', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', 'Ada tempat kosong untuk {when} · {court}. Jika anda tidak dapat hadir, batalkan awal-awal.'),
  ('ms', 'Join request: {group}', 'Permintaan menyertai: {group}'),
  ('ms', '{name} wants to join.', '{name} mahu menyertai.'),
  ('ms', 'Welcome to {group}', 'Selamat datang ke {group}'),
  ('ms', 'Your request was approved. You can sign up for sessions now.', 'Permintaan anda telah diluluskan. Anda kini boleh mendaftar untuk sesi.'),
  ('ms', 'Session cancelled: {group}', 'Sesi dibatalkan: {group}'),
  ('ms', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', '{when} · {court} dibatalkan oleh penganjur. Ini tidak menjejaskan rekod anda.'),
  ('ms', 'Singles challenge', 'Cabaran perseorangan'),
  ('ms', '{name} challenged you: {when} · {court}.', '{name} mencabar anda: {when} · {court}.'),
  ('ms', 'Challenge accepted', 'Cabaran diterima'),
  ('ms', '{name} is in: {when} · {court}.', '{name} setuju bermain: {when} · {court}.'),
  ('ms', 'You get this because you asked Badie to find you a game.', 'Anda menerima ini kerana anda meminta Badie mencarikan permainan untuk anda.'),
  ('th', 'Game on!', 'นัดสำเร็จ!'),
  ('th', '{when} · {court}. Everyone confirmed.', '{when} · {court} ทุกคนยืนยันแล้ว'),
  ('th', 'Match found, accepted for you', 'เจอคู่แล้ว ตอบรับให้แล้ว'),
  ('th', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court} รอคนอื่นยืนยัน'),
  ('th', 'Match found, please confirm', 'เจอคู่แล้ว กรุณายืนยัน'),
  ('th', '{when} · {court}. Confirm by {by}.', '{when} · {court} ยืนยันภายใน {by}'),
  ('th', 'Still looking', 'กำลังหาต่อ'),
  ('th', 'Not everyone could make {when} · {court}. We’re finding you another game.', 'บางคนไป {when} · {court} ไม่ได้ เรากำลังหาเกมใหม่ให้คุณ'),
  ('th', 'You missed a match', 'คุณพลาดการจับคู่'),
  ('th', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court} คำขอของคุณถูกหยุดชั่วคราว เปิด Badie เพื่อหาต่อ'),
  ('th', 'No game this time', 'ครั้งนี้ยังไม่มีเกม'),
  ('th', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', 'เราหาผู้เล่นสำหรับ {when} · {court} ไม่เจอ ไม่มีผลเสียกับคุณ'),
  ('th', 'Game cancelled', 'เกมถูกยกเลิก'),
  ('th', 'A player can’t make {when} · {court}.', 'มีผู้เล่นคนหนึ่งไป {when} · {court} ไม่ได้'),
  ('th', 'A player can’t make {when} · {court}. We’re finding you another game.', 'มีผู้เล่นคนหนึ่งไป {when} · {court} ไม่ได้ เรากำลังหาเกมใหม่ให้คุณ'),
  ('th', 'You both want to play again', 'คุณทั้งคู่อยากเล่นด้วยกันอีก'),
  ('th', 'You and {name} are now friends. Message them to set up the next game.', 'คุณกับ {name} เป็นเพื่อนกันแล้ว ส่งข้อความนัดเกมถัดไปได้เลย'),
  ('th', 'New friend', 'เพื่อนใหม่'),
  ('th', 'You and {name} are now friends.', 'คุณกับ {name} เป็นเพื่อนกันแล้ว'),
  ('th', 'How was your game?', 'เกมเป็นยังไงบ้าง?'),
  ('th', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court} ให้คะแนนเพื่อนร่วมเกมภายใน 48 ชั่วโมง ข้อมูลนี้เป็นความลับ'),
  ('th', 'A tip from recent games', 'คำแนะนำจากเกมช่วงนี้'),
  ('th', 'Keep an eye on the people around you and keep your swings safe.', 'คอยระวังคนรอบตัว และเหวี่ยงไม้อย่างปลอดภัย'),
  ('th', 'Keep it friendly on court. Everyone is here to enjoy the game.', 'เล่นกันอย่างเป็นมิตรในสนาม ทุกคนมาเพื่อสนุกกับเกม'),
  ('th', 'In doubles, share the court and let your partner play their shots.', 'เวลาเล่นคู่ แบ่งคอร์ทกันเล่น และให้คู่ของคุณได้ตีลูกของเขาเอง'),
  ('th', 'Settle up court fees soon after the game.', 'หลังจบเกม จ่ายค่าคอร์ทให้เรียบร้อยโดยเร็ว'),
  ('th', 'Friend request', 'คำขอเป็นเพื่อน'),
  ('th', '{name} wants to be friends.', '{name} อยากเป็นเพื่อนกับคุณ'),
  ('th', 'You’re in: {group}', 'ได้ที่แล้ว: {group}'),
  ('th', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', 'มีที่ว่างสำหรับ {when} · {court} แล้ว ถ้าไปไม่ได้ ให้ยกเลิกแต่เนิ่นๆ'),
  ('th', 'Join request: {group}', 'คำขอเข้าร่วม: {group}'),
  ('th', '{name} wants to join.', '{name} ขอเข้าร่วม'),
  ('th', 'Welcome to {group}', 'ยินดีต้อนรับสู่ {group}'),
  ('th', 'Your request was approved. You can sign up for sessions now.', 'คำขอของคุณได้รับอนุมัติแล้ว ลงชื่อเข้ารอบได้เลย'),
  ('th', 'Session cancelled: {group}', 'รอบถูกยกเลิก: {group}'),
  ('th', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', 'ผู้จัดยกเลิกรอบ {when} · {court} แล้ว ไม่มีผลเสียกับคุณ'),
  ('th', 'Singles challenge', 'คำท้าตีเดี่ยว'),
  ('th', '{name} challenged you: {when} · {court}.', '{name} ท้าคุณ: {when} · {court}'),
  ('th', 'Challenge accepted', 'รับคำท้าแล้ว'),
  ('th', '{name} is in: {when} · {court}.', '{name} ตกลงเล่น: {when} · {court}'),
  ('th', 'You get this because you asked Badie to find you a game.', 'คุณได้รับอีเมลนี้เพราะขอให้ Badie หาเกมให้'),
  ('vi', 'Game on!', 'Đã chốt trận!'),
  ('vi', '{when} · {court}. Everyone confirmed.', '{when} · {court}. Mọi người đã xác nhận.'),
  ('vi', 'Match found, accepted for you', 'Đã ghép được trận, tự động chấp nhận'),
  ('vi', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court}. Đang chờ những người khác xác nhận.'),
  ('vi', 'Match found, please confirm', 'Đã ghép được trận, hãy xác nhận'),
  ('vi', '{when} · {court}. Confirm by {by}.', '{when} · {court}. Xác nhận trước {by}.'),
  ('vi', 'Still looking', 'Vẫn đang tìm'),
  ('vi', 'Not everyone could make {when} · {court}. We’re finding you another game.', 'Không phải ai cũng tham gia được {when} · {court}. Chúng tôi đang tìm trận khác cho bạn.'),
  ('vi', 'You missed a match', 'Bạn đã bỏ lỡ một lượt ghép'),
  ('vi', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court}. Yêu cầu của bạn đã tạm dừng. Mở Badie để tiếp tục tìm.'),
  ('vi', 'No game this time', 'Lần này chưa có trận'),
  ('vi', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', 'Chúng tôi chưa tìm được người chơi cho {when} · {court}. Không có gì bị tính vào hồ sơ của bạn.'),
  ('vi', 'Game cancelled', 'Trận đã bị hủy'),
  ('vi', 'A player can’t make {when} · {court}.', 'Một người chơi không thể tham gia {when} · {court}.'),
  ('vi', 'A player can’t make {when} · {court}. We’re finding you another game.', 'Một người chơi không thể tham gia {when} · {court}. Chúng tôi đang tìm trận khác cho bạn.'),
  ('vi', 'You both want to play again', 'Cả hai đều muốn chơi lại'),
  ('vi', 'You and {name} are now friends. Message them to set up the next game.', 'Bạn và {name} đã là bạn bè. Nhắn tin để hẹn trận tiếp theo nhé.'),
  ('vi', 'New friend', 'Bạn mới'),
  ('vi', 'You and {name} are now friends.', 'Bạn và {name} đã là bạn bè.'),
  ('vi', 'How was your game?', 'Trận đấu thế nào?'),
  ('vi', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court}. Hãy đánh giá bạn chơi cùng trong vòng 48 giờ. Đánh giá được giữ riêng tư.'),
  ('vi', 'A tip from recent games', 'Một góp ý từ các trận gần đây'),
  ('vi', 'Keep an eye on the people around you and keep your swings safe.', 'Hãy để ý những người xung quanh và vung vợt an toàn nhé.'),
  ('vi', 'Keep it friendly on court. Everyone is here to enjoy the game.', 'Hãy giữ không khí thân thiện trên sân. Ai cũng đến để tận hưởng trận đấu.'),
  ('vi', 'In doubles, share the court and let your partner play their shots.', 'Khi đánh đôi, hãy chia sẻ sân và để đồng đội đánh những cú của mình.'),
  ('vi', 'Settle up court fees soon after the game.', 'Hãy trả phần tiền sân sớm sau trận nhé.'),
  ('vi', 'Friend request', 'Lời mời kết bạn'),
  ('vi', '{name} wants to be friends.', '{name} muốn kết bạn với bạn.'),
  ('vi', 'You’re in: {group}', 'Bạn đã có chỗ: {group}'),
  ('vi', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', 'Có chỗ trống cho {when} · {court}. Nếu không đi được, hãy hủy sớm.'),
  ('vi', 'Join request: {group}', 'Yêu cầu tham gia: {group}'),
  ('vi', '{name} wants to join.', '{name} muốn tham gia.'),
  ('vi', 'Welcome to {group}', 'Chào mừng bạn đến với {group}'),
  ('vi', 'Your request was approved. You can sign up for sessions now.', 'Yêu cầu của bạn đã được đồng ý. Giờ bạn có thể đăng ký các buổi.'),
  ('vi', 'Session cancelled: {group}', 'Buổi bị hủy: {group}'),
  ('vi', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', 'Buổi {when} · {court} đã bị người tổ chức hủy. Không có gì bị tính vào hồ sơ của bạn.'),
  ('vi', 'Singles challenge', 'Thách đấu đơn'),
  ('vi', '{name} challenged you: {when} · {court}.', '{name} đã thách đấu bạn: {when} · {court}.'),
  ('vi', 'Challenge accepted', 'Đã nhận lời thách đấu'),
  ('vi', '{name} is in: {when} · {court}.', '{name} đã nhận lời: {when} · {court}.'),
  ('vi', 'You get this because you asked Badie to find you a game.', 'Bạn nhận được email này vì đã nhờ Badie tìm trận cho bạn.'),
  ('hi', 'Game on!', 'गेम पक्का!'),
  ('hi', '{when} · {court}. Everyone confirmed.', '{when} · {court}। सबने कन्फ़र्म कर दिया।'),
  ('hi', 'Match found, accepted for you', 'मैच मिला, आपकी ओर से स्वीकार किया गया'),
  ('hi', '{when} · {court}. Waiting for the others to confirm.', '{when} · {court}। बाकियों के कन्फ़र्म करने का इंतज़ार है।'),
  ('hi', 'Match found, please confirm', 'मैच मिला, कृपया कन्फ़र्म करें'),
  ('hi', '{when} · {court}. Confirm by {by}.', '{when} · {court}। {by} तक कन्फ़र्म करें।'),
  ('hi', 'Still looking', 'खोज जारी है'),
  ('hi', 'Not everyone could make {when} · {court}. We’re finding you another game.', '{when} · {court} पर सबका आना नहीं हो सका। आपके लिए दूसरा गेम ढूँढा जा रहा है।'),
  ('hi', 'You missed a match', 'आपसे एक मैच छूट गया'),
  ('hi', '{when} · {court}. Your request is paused. Open Badie to keep looking.', '{when} · {court}। आपकी रिक्वेस्ट रोक दी गई है। खोज जारी रखने के लिए Badie खोलें।'),
  ('hi', 'No game this time', 'इस बार कोई गेम नहीं'),
  ('hi', 'We couldn’t find players for {when} · {court}. Nothing counts against you.', 'हमें {when} · {court} के लिए खिलाड़ी नहीं मिल सके। इसे आपके ख़िलाफ़ नहीं गिना जाता।'),
  ('hi', 'Game cancelled', 'गेम कैंसिल हो गया'),
  ('hi', 'A player can’t make {when} · {court}.', 'एक खिलाड़ी का {when} · {court} पर आना नहीं हो पाएगा।'),
  ('hi', 'A player can’t make {when} · {court}. We’re finding you another game.', 'एक खिलाड़ी का {when} · {court} पर आना नहीं हो पाएगा। आपके लिए दूसरा गेम ढूँढा जा रहा है।'),
  ('hi', 'You both want to play again', 'आप दोनों फिर साथ खेलने को तैयार हैं'),
  ('hi', 'You and {name} are now friends. Message them to set up the next game.', 'आप और {name} अब दोस्त हैं। अगला गेम तय करने के लिए उन्हें मैसेज करें।'),
  ('hi', 'New friend', 'नई दोस्ती'),
  ('hi', 'You and {name} are now friends.', 'आप और {name} अब दोस्त हैं।'),
  ('hi', 'How was your game?', 'आपका गेम कैसा रहा?'),
  ('hi', '{when} · {court}. Rate your partners within 48 hours. It stays private.', '{when} · {court}। 48 घंटे के अंदर अपने पार्टनर को रेट करें। यह निजी रहता है।'),
  ('hi', 'A tip from recent games', 'हाल के गेम से एक सुझाव'),
  ('hi', 'Keep an eye on the people around you and keep your swings safe.', 'अपने आस-पास के लोगों पर नज़र रखें और रैकेट सुरक्षित ढंग से चलाएँ।'),
  ('hi', 'Keep it friendly on court. Everyone is here to enjoy the game.', 'कोर्ट पर माहौल दोस्ताना रखें। यहाँ सब खेल का मज़ा लेने आते हैं।'),
  ('hi', 'In doubles, share the court and let your partner play their shots.', 'डबल्स में कोर्ट शेयर करें और अपने पार्टनर को भी उनके शॉट खेलने दें।'),
  ('hi', 'Settle up court fees soon after the game.', 'गेम के बाद कोर्ट फ़ीस जल्दी चुका दें।'),
  ('hi', 'Friend request', 'फ़्रेंड रिक्वेस्ट'),
  ('hi', '{name} wants to be friends.', '{name} आपसे दोस्ती करना चाहते हैं।'),
  ('hi', 'You’re in: {group}', 'आपकी जगह पक्की: {group}'),
  ('hi', 'A spot opened up for {when} · {court}. If you can’t make it, cancel early.', '{when} · {court} के लिए एक जगह खाली हुई। अगर आना न हो पाए, तो जल्दी कैंसिल करें।'),
  ('hi', 'Join request: {group}', 'शामिल होने की रिक्वेस्ट: {group}'),
  ('hi', '{name} wants to join.', '{name} शामिल होना चाहते हैं।'),
  ('hi', 'Welcome to {group}', '{group} में आपका स्वागत है'),
  ('hi', 'Your request was approved. You can sign up for sessions now.', 'आपकी रिक्वेस्ट मंज़ूर हो गई। अब आपके लिए सेशन का साइन अप खुला है।'),
  ('hi', 'Session cancelled: {group}', 'सेशन कैंसिल: {group}'),
  ('hi', '{when} · {court} was cancelled by the organizer. Nothing counts against you.', 'ऑर्गनाइज़र ने {when} · {court} का सेशन कैंसिल कर दिया। इसे आपके ख़िलाफ़ नहीं गिना जाता।'),
  ('hi', 'Singles challenge', 'सिंगल्स चैलेंज'),
  ('hi', '{name} challenged you: {when} · {court}.', '{name} ने आपको चैलेंज दिया: {when} · {court}।'),
  ('hi', 'Challenge accepted', 'चैलेंज स्वीकार हुआ'),
  ('hi', '{name} is in: {when} · {court}.', '{name} तैयार हैं: {when} · {court}।'),
  ('hi', 'You get this because you asked Badie to find you a game.', 'आपको यह इसलिए मिल रहा है क्योंकि आपने Badie से अपने लिए गेम ढूँढने को कहा था।');
