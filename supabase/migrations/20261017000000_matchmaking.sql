-- 约球核心：等级 → 约球请求 → 后台匹配 → 多方确认 → 球局 → 签到 → 赛果
-- 规则与 iOS 一致（Badie-iOS/docs/DESIGN.md §10、§13、§14，MockBackend+Matchmaking.swift）。这一版先不做：
-- 临时局（开赛前 2.5 小时内）、双打补位（有人没确认时整组作废，已确认的人优先重新排队）、互评。
--
-- 安全：这些表客户端一律不能直接读写，全部走下面的函数，函数里检查身份和规则；
-- 看别人只能看到同一个提议 / 球局里的昵称和等级，看不到谁拒绝了、谁还没回复。

-- ---------------------------------------------------------------------------
-- 等级与资料
-- ---------------------------------------------------------------------------

-- 连续分值：4− = 3.67，4 = 4.00，4+ = 4.33；没做问卷先按 3 级匹配
alter table public.profiles
  add column rating numeric(4, 2) not null default 3 check (rating between 0.66 and 9.34),
  add column assessed_at timestamptz,
  add column assessment jsonb check (pg_column_size(assessment) < 4096);

-- 昵称会出现在匹配卡片上，不能留联系方式或链接（已有数据不回头检查）
alter table public.profiles add constraint profiles_nickname_no_contact
  check (nickname !~* '(https?:|www\.|@|\d{5,})') not valid;

-- 表本身只能读自己的；等级只能通过 save_assessment 改
drop policy "profiles are readable by signed-in users" on public.profiles;
create policy "users read their own profile" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
revoke insert, update on public.profiles from authenticated;
grant insert (id, nickname, country_code), update (nickname, country_code) on public.profiles to authenticated;

-- 问卷最高 6+；90 天内只能重测一次（跳过定级的随时可以补测）
create function public.save_assessment(p_rating numeric, p_answers jsonb)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare
  result public.profiles;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_rating is null or p_rating not between 0.66 and 6.34 then raise exception 'invalid_rating' using errcode = '22023'; end if;
  if exists (select 1 from public.profiles where id = auth.uid() and assessed_at > now() - interval '90 days') then
    raise exception 'retake_too_soon' using errcode = '22023';
  end if;
  update public.profiles set rating = round(p_rating * 3) / 3, assessed_at = now(), assessment = p_answers
    where id = auth.uid() returning * into result;
  if result.id is null then raise exception 'no_profile' using errcode = 'P0002'; end if;
  return result;
end
$$;

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

create type public.game_mode as enum ('singles', 'doubles');
create type public.ticket_status as enum ('searching', 'offered', 'matched', 'paused', 'expired', 'cancelled');
create type public.seat_response as enum ('pending', 'accepted', 'declined', 'expired');
create type public.offer_status as enum ('open', 'confirmed', 'failed');
create type public.game_status as enum ('scheduled', 'cancelled');
create type public.result_outcome as enum ('team1', 'team2', 'friendly');

-- 约球请求：挂在后台，找到人就生成提议。时间按半点对齐（界面只给半点可选）
create table public.match_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  mode public.game_mode not null,
  starts_at timestamptz not null check (extract(epoch from starts_at)::bigint % 1800 = 0),
  ends_at timestamptz not null check (extract(epoch from ends_at)::bigint % 1800 = 0),
  venue_ids text[] not null check (cardinality(venue_ids) between 1 and 3),
  -- 可接受的水平差（级）：1、2，8 = 不限
  skill_tolerance smallint not null check (skill_tolerance in (1, 2, 8)),
  auto_accept boolean not null default false,
  status public.ticket_status not null default 'searching',
  offer_id uuid,
  game_id uuid,
  -- 因为别人没确认被退回的，下一轮优先
  priority boolean not null default false,
  -- 不再和这些人匹配（我拒绝过或没确认的那组人）；双方任一方排除就不配
  excluded_user_ids uuid[] not null default '{}',
  -- 开赛前 2 小时还没约成就结束
  lock_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (ends_at - starts_at between interval '1 hour' and interval '8 hours')
);

create index match_tickets_searching_idx on public.match_tickets (mode, starts_at) where status = 'searching';
create index match_tickets_user_idx on public.match_tickets (user_id, created_at);

create table public.match_offers (
  id uuid primary key default gen_random_uuid(),
  mode public.game_mode not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  venue_id text not null references public.venues (id),
  status public.offer_status not null default 'open',
  lock_at timestamptz not null,
  game_id uuid,
  created_at timestamptz not null default now()
);

create index match_offers_open_idx on public.match_offers (lock_at) where status = 'open';

create table public.match_seats (
  offer_id uuid not null references public.match_offers (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  ticket_id uuid not null references public.match_tickets (id) on delete cascade,
  team smallint not null check (team in (1, 2)),
  response public.seat_response not null default 'pending',
  respond_by timestamptz not null,
  responded_at timestamptz,
  primary key (offer_id, user_id)
);

create index match_seats_ticket_idx on public.match_seats (ticket_id);
create index match_seats_pending_idx on public.match_seats (respond_by) where response = 'pending';

create table public.games (
  id uuid primary key default gen_random_uuid(),
  mode public.game_mode not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  venue_id text not null references public.venues (id),
  status public.game_status not null default 'scheduled',
  offer_id uuid references public.match_offers (id),
  created_at timestamptz not null default now()
);

create table public.game_players (
  game_id uuid not null references public.games (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  team smallint not null check (team in (1, 2)),
  -- 开局时的等级（以后改了等级不影响这局的展示）
  rating numeric(4, 2) not null,
  checked_in_at timestamptz,
  cancelled_at timestamptz,
  -- 开赛前 2 小时内取消 = 临时取消，计入履约记录
  late_cancel boolean not null default false,
  primary key (game_id, user_id)
);

create index game_players_user_idx on public.game_players (user_id);

-- 赛果申报：outcome 为空 = 记不清了（不算确认，也不算分歧）
create table public.result_reports (
  game_id uuid not null references public.games (id) on delete cascade,
  reporter_id uuid not null references auth.users (id) on delete cascade,
  outcome public.result_outcome,
  updated_at timestamptz not null default now(),
  primary key (game_id, reporter_id)
);

create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  link text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  emailed_at timestamptz
);

create index notifications_user_idx on public.notifications (user_id, id desc);
create index notifications_unsent_idx on public.notifications (id) where emailed_at is null;

alter table public.match_tickets enable row level security;
alter table public.match_offers enable row level security;
alter table public.match_seats enable row level security;
alter table public.games enable row level security;
alter table public.game_players enable row level security;
alter table public.result_reports enable row level security;
alter table public.notifications enable row level security;

-- 不靠项目的默认授权：客户端对这些表没有任何权限，只有通知能被本人直接读
revoke all on public.match_tickets, public.match_offers, public.match_seats, public.games, public.game_players,
  public.result_reports, public.notifications from anon, authenticated;
create policy "users read their own notifications" on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
grant select (id, kind, title, body, link, created_at, read_at) on public.notifications to authenticated;
grant all on public.match_tickets, public.match_offers, public.match_seats, public.games, public.game_players,
  public.result_reports, public.notifications to service_role;

-- ---------------------------------------------------------------------------
-- 内部工具（客户端不能直接调用）
-- ---------------------------------------------------------------------------

create function public.notify(p_user uuid, p_kind text, p_title text, p_body text, p_link text default null)
returns void language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, kind, title, body, link) values (p_user, p_kind, p_title, p_body, p_link)
$$;

-- “Sat, Oct 18, 7:00 PM · Bay Badminton Center”（球馆当地时间）
create function public.slot_text(p_start timestamptz, p_venue text)
returns text language sql stable security definer set search_path = '' as $$
  select to_char(p_start at time zone coalesce(v.time_zone_id, 'UTC'), 'Dy, Mon FMDD, FMHH12:MI AM') || ' · ' || v.name
  from public.venues v where v.id = p_venue
$$;

-- 确认期限：离开赛 ≥26 小时给 12 小时，≥6 小时给 2 小时，更近给 30 分钟；
-- 落在球馆当地夜里（23:00–8:00）的顺延到早上 9 点；都不晚于锁定时间（开赛前 2 小时）
create function public.offer_respond_by(p_start timestamptz, p_now timestamptz, p_tz text)
returns timestamptz language sql stable set search_path = '' as $$
  select least(p_start - interval '2 hours', case
      when extract(hour from local) >= 23 then (date_trunc('day', local) + interval '1 day 9 hours') at time zone p_tz
      when extract(hour from local) < 8 then (date_trunc('day', local) + interval '9 hours') at time zone p_tz
      else raw end)
  from (select raw, raw at time zone p_tz as local
        from (select p_now + case when p_start - p_now >= interval '26 hours' then interval '12 hours'
                                  when p_start - p_now >= interval '6 hours' then interval '2 hours'
                                  else interval '30 minutes' end as raw) r) w
$$;

-- 这段时间里已经有球局
create function public.has_game_between(p_user uuid, p_start timestamptz, p_end timestamptz)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.game_players gp join public.games g on g.id = gp.game_id
    where gp.user_id = p_user and g.status = 'scheduled' and g.starts_at < p_end and p_start < g.ends_at)
$$;

-- 全部确认：生成球局。返回球局 id（还有人没确认返回 null）
create function public.finalize_offer(p_offer uuid)
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
    perform public.notify(seat.user_id, 'matched', 'Game on!',
      public.slot_text(o.starts_at, o.venue_id) || '. Everyone confirmed.', '/app/games/' || new_game || '/');
  end loop;
  return new_game;
end
$$;

-- 为一个在找的请求找人；找到就生成提议。返回提议 id（没找到返回 null）
create function public.match_ticket(p_ticket uuid, p_now timestamptz)
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
        public.slot_text(slot_start, venue) || '. Waiting for the others to confirm.', '/app/play/');
    else
      perform public.notify(seat.user_id, 'offer', 'Match found, please confirm',
        public.slot_text(slot_start, venue) || '. Confirm by ' || to_char(respond_by at time zone tz, 'Dy FMHH12:MI AM') || '.',
        '/app/play/');
    end if;
  end loop;
  return new_offer;
end
$$;

-- 约不成：拒绝或没回复的人以后不再和这组人配；其余的人退回去重新找（已确认的优先），不说是谁没来
create function public.fail_offer(p_offer uuid, p_now timestamptz)
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
      'Not everyone could make ' || public.slot_text(o.starts_at, o.venue_id) || '. We’re finding you another game.', '/app/play/');
    perform public.match_ticket(seat.ticket_id, p_now);
  end loop;
end
$$;

-- 每分钟跑一次：处理超时、锁定、过期，再给还在找的请求匹配一轮
create function public.process_matchmaking(p_now timestamptz default now())
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
      public.slot_text(seat.starts_at, seat.venue_id) || '. Your request is paused. Open Badie to keep looking.', '/app/play/');
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
      'We couldn’t find players for ' || public.slot_text(item.starts_at, item.venue_id) || '. Nothing counts against you.', '/app/play/');
  end loop;

  for item in select id from public.match_tickets where status = 'searching' order by priority desc, created_at loop
    perform public.match_ticket(item.id, p_now);
  end loop;
end
$$;

-- 重要的通知（要确认、约成了、取消了、错过了）发邮件。Resend 的 API key 存在 Vault（名字 resend_api_key），
-- 没配就不发；一次最多 100 封，只发 1 小时内的
create function public.send_notification_emails()
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
      'text', p.body || E'\n\nhttps://badie.rsvp' || coalesce(p.link, '/app/') ||
              E'\n\n—\nYou get this because you asked Badie to find you a game.'))
    into emails
    from picked p join auth.users u on u.id = p.user_id where u.email is not null;
  if emails is null then return; end if;

  perform net.http_post(url := 'https://api.resend.com/emails/batch', body := emails,
                        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'));
end
$$;

-- ---------------------------------------------------------------------------
-- 对外的操作
-- ---------------------------------------------------------------------------

create function public.submit_ticket(p_mode public.game_mode, p_starts_at timestamptz, p_ends_at timestamptz,
                                     p_venue_ids text[], p_skill_tolerance int, p_auto_accept boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  venues text[];
  new_ticket uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if not exists (select 1 from public.profiles where id = me) then raise exception 'no_profile' using errcode = 'P0002'; end if;
  -- 最早开赛前 2.5 小时发起（给匹配和确认留时间），最晚两周后
  if p_starts_at < now() + interval '150 minutes' then raise exception 'too_soon' using errcode = '22023'; end if;
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

  insert into public.match_tickets (user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, auto_accept, lock_at)
    values (me, p_mode, p_starts_at, p_ends_at, venues, p_skill_tolerance, p_auto_accept, p_starts_at - interval '2 hours')
    returning id into new_ticket;
  perform public.match_ticket(new_ticket, now());
  return new_ticket;
end
$$;

-- 撤回请求：正在确认中的，算这次来不了（不扣分）
create function public.cancel_ticket(p_ticket uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  t public.match_tickets;
begin
  select * into t from public.match_tickets where id = p_ticket and user_id = auth.uid() for update;
  if t.id is null or t.status not in ('searching', 'offered', 'paused') then raise exception 'not_active' using errcode = 'P0002'; end if;
  update public.match_tickets set status = 'cancelled', offer_id = null where id = p_ticket;
  if t.offer_id is not null then
    update public.match_seats set response = 'declined', responded_at = now() where offer_id = t.offer_id and user_id = t.user_id;
    perform public.fail_offer(t.offer_id, now());
  end if;
end
$$;

-- 错过确认后继续找
create function public.resume_ticket(p_ticket uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.match_tickets set status = 'searching'
    where id = p_ticket and user_id = auth.uid() and status = 'paused' and lock_at > now();
  if not found then raise exception 'not_paused' using errcode = 'P0002'; end if;
  perform public.match_ticket(p_ticket, now());
end
$$;

-- 接受或拒绝提议。拒绝不扣分：我继续找（不再配这组人），其他人重新排队
create function public.respond_offer(p_offer uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  seat public.match_seats;
begin
  select s.* into seat from public.match_seats s join public.match_offers o on o.id = s.offer_id
    where s.offer_id = p_offer and s.user_id = auth.uid() and s.response = 'pending' and s.respond_by > now() and o.status = 'open'
    for update of s;
  if seat.offer_id is null then raise exception 'offer_closed' using errcode = 'P0002'; end if;

  update public.match_seats set response = case when p_accept then 'accepted' else 'declined' end::public.seat_response,
                                responded_at = now()
    where offer_id = p_offer and user_id = seat.user_id;

  if p_accept then
    perform public.finalize_offer(p_offer);
  else
    perform public.fail_offer(p_offer, now());
    update public.match_tickets set status = 'searching', offer_id = null where id = seat.ticket_id and status = 'offered';
    perform public.match_ticket(seat.ticket_id, now());
  end if;
end
$$;

-- 确认后退出：开赛前 2 小时内算临时取消。球局取消，其他人来得及的话优先重新排队
create function public.cancel_game(p_game uuid)
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
      'A player can’t make ' || public.slot_text(g.starts_at, g.venue_id) || '.' ||
      case when requeued then ' We’re finding you another game.' else '' end, '/app/games/');
  end loop;
  perform public.match_ticket(t.id, now()) from public.match_tickets t where t.game_id is null and t.status = 'searching'
    and t.id in (select ticket_id from public.match_seats where offer_id = g.offer_id);
end
$$;

-- 开赛前 30 分钟到结束之间签到
create function public.check_in(p_game uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.game_players gp set checked_in_at = coalesce(gp.checked_in_at, now())
    from public.games g
    where g.id = gp.game_id and gp.game_id = p_game and gp.user_id = auth.uid() and g.status = 'scheduled'
      and now() between g.starts_at - interval '30 minutes' and g.ends_at;
  if not found then raise exception 'cannot_check_in' using errcode = 'P0002'; end if;
end
$$;

-- 赛果状态（与 iOS Ranking.swift resultStatus 一致）：说法不一致 = 有分歧；两队都有人报且一致 = 确认；
-- 某一队全员记不清 = 不计入；结束 7 天后还没结论 = 过期
create function public.game_result(p_game uuid, p_now timestamptz default now())
returns table (status text, outcome public.result_outcome) language sql stable security definer set search_path = '' as $$
  with claims as (
    select r.outcome, gp.team from public.result_reports r
    join public.game_players gp on gp.game_id = r.game_id and gp.user_id = r.reporter_id
    where r.game_id = p_game and r.outcome is not null),
  summary as (select count(distinct outcome) as outcomes, count(distinct team) as teams, min(outcome::text) as outcome from claims)
  select case
      when s.outcomes > 1 then 'disputed'
      when s.teams = 2 then 'verified'
      when exists (select 1 from public.game_players gp
                   left join public.result_reports r on r.game_id = gp.game_id and r.reporter_id = gp.user_id
                   where gp.game_id = p_game group by gp.team
                   having bool_and(r.reporter_id is not null and r.outcome is null)) then 'unsure'
      when p_now > (select ends_at from public.games where id = p_game) + interval '7 days' then 'expired'
      else 'awaiting' end,
    case when s.outcomes = 1 and s.teams = 2 then s.outcome::public.result_outcome end
  from summary s
$$;

-- 报赛果 / 改赛果：开赛后到结束 7 天内、确认之前都能改；outcome 为空 = 记不清了。返回最新状态
create function public.report_result(p_game uuid, p_outcome public.result_outcome)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = auth.uid()
                 where g.id = p_game and g.status = 'scheduled' and now() between g.starts_at and g.ends_at + interval '7 days') then
    raise exception 'cannot_report' using errcode = 'P0002';
  end if;
  perform 1 from public.games where id = p_game for update;
  if (select r.status from public.game_result(p_game) r) = 'verified' then raise exception 'result_locked' using errcode = '22023'; end if;
  insert into public.result_reports (game_id, reporter_id, outcome) values (p_game, auth.uid(), p_outcome)
    on conflict (game_id, reporter_id) do update set outcome = excluded.outcome, updated_at = now();
  return (select r.status from public.game_result(p_game) r);
end
$$;

-- ---------------------------------------------------------------------------
-- 页面数据
-- ---------------------------------------------------------------------------

-- 我的请求（进行中的，加上最近一天结束的），正在确认的附带提议
create function public.my_matchmaking()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at), '[]') from (
    select t.starts_at, jsonb_build_object(
      'id', t.id, 'mode', t.mode, 'starts_at', t.starts_at, 'ends_at', t.ends_at, 'status', t.status,
      'skill_tolerance', t.skill_tolerance, 'auto_accept', t.auto_accept, 'lock_at', t.lock_at, 'game_id', t.game_id,
      'venues', (select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city))
                 from public.venues v where v.id = any (t.venue_ids)),
      'offer', (select jsonb_build_object(
          'id', o.id, 'starts_at', o.starts_at, 'ends_at', o.ends_at, 'respond_by', me.respond_by, 'my_response', me.response,
          'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id),
          'accepted', (select count(*) from public.match_seats s where s.offer_id = o.id and s.response = 'accepted'),
          'players', (select jsonb_agg(jsonb_build_object('nickname', p.nickname, 'rating', p.rating, 'team', s.team,
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

-- 我最近 60 天的球局
create function public.my_games()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at desc), '[]') from (
    select g.starts_at, jsonb_build_object(
      'id', g.id, 'mode', g.mode, 'starts_at', g.starts_at, 'ends_at', g.ends_at, 'status', g.status,
      'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                  'lat', v.lat, 'lon', v.lon,
                                  'pricing', v.pricing, 'country', v.country_code),
      'my_team', me.team, 'checked_in', me.checked_in_at is not null,
      'my_report', (select jsonb_build_object('outcome', r.outcome) from public.result_reports r
                    where r.game_id = g.id and r.reporter_id = auth.uid()),
      'result', (select to_jsonb(gr) from public.game_result(g.id) gr),
      'players', (select jsonb_agg(jsonb_build_object('nickname', p.nickname, 'rating', gp.rating, 'team', gp.team,
                                                      'me', gp.user_id = auth.uid(), 'checked_in', gp.checked_in_at is not null)
                                   order by gp.team, gp.rating desc)
                  from public.game_players gp join public.profiles p on p.id = gp.user_id where gp.game_id = g.id)
    ) as item
    from public.games g
    join public.game_players me on me.game_id = g.id and me.user_id = auth.uid()
    join public.venues v on v.id = g.venue_id
    where g.ends_at > now() - interval '60 days'
  ) items
$$;

-- 我的战绩：本月确认过的胜负（同一组对手每月最多计 3 场）、打过的场次、临时取消次数
create function public.my_record()
returns jsonb language sql stable security definer set search_path = '' as $$
  with mine as (
    select gr.outcome = ('team' || gp.team)::public.result_outcome as won,
           row_number() over (partition by (select array_agg(o.user_id order by o.user_id) from public.game_players o
                                            where o.game_id = g.id and o.team <> gp.team)
                              order by g.starts_at) as nth
    from public.game_players gp join public.games g on g.id = gp.game_id
    cross join lateral public.game_result(g.id) gr
    where gp.user_id = auth.uid() and g.status = 'scheduled' and g.starts_at >= date_trunc('month', now())
      and gr.status = 'verified' and gr.outcome <> 'friendly')
  select jsonb_build_object(
    'wins', (select count(*) from mine where nth <= 3 and won),
    'losses', (select count(*) from mine where nth <= 3 and not won),
    'games_played', (select count(*) from public.game_players gp join public.games g on g.id = gp.game_id
                     where gp.user_id = auth.uid() and g.status = 'scheduled' and g.ends_at < now()),
    'late_cancels', (select count(*) from public.game_players where user_id = auth.uid() and late_cancel))
$$;

create function public.mark_notifications_read()
returns void language sql security definer set search_path = '' as $$
  update public.notifications set read_at = now() where user_id = auth.uid() and read_at is null
$$;

-- ---------------------------------------------------------------------------
-- 权限与定时任务
-- ---------------------------------------------------------------------------

revoke execute on function public.notify(uuid, text, text, text, text), public.slot_text(timestamptz, text),
  public.offer_respond_by(timestamptz, timestamptz, text), public.has_game_between(uuid, timestamptz, timestamptz),
  public.finalize_offer(uuid), public.match_ticket(uuid, timestamptz), public.fail_offer(uuid, timestamptz),
  public.process_matchmaking(timestamptz), public.send_notification_emails(), public.game_result(uuid, timestamptz)
  from public, anon, authenticated;

revoke execute on function public.save_assessment(numeric, jsonb),
  public.submit_ticket(public.game_mode, timestamptz, timestamptz, text[], int, boolean), public.cancel_ticket(uuid),
  public.resume_ticket(uuid), public.respond_offer(uuid, boolean), public.cancel_game(uuid), public.check_in(uuid),
  public.report_result(uuid, public.result_outcome), public.my_matchmaking(), public.my_games(), public.my_record(),
  public.mark_notifications_read()
  from public, anon;
grant execute on function public.save_assessment(numeric, jsonb),
  public.submit_ticket(public.game_mode, timestamptz, timestamptz, text[], int, boolean), public.cancel_ticket(uuid),
  public.resume_ticket(uuid), public.respond_offer(uuid, boolean), public.cancel_game(uuid), public.check_in(uuid),
  public.report_result(uuid, public.result_outcome), public.my_matchmaking(), public.my_games(), public.my_record(),
  public.mark_notifications_read()
  to authenticated;

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('process-matchmaking', '* * * * *', 'select public.process_matchmaking()');
select cron.schedule('send-notification-emails', '* * * * *', 'select public.send_notification_emails()');
