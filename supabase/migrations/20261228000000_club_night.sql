-- 球群当晚的排场、比赛和收款（iPhone 1.0.7，需求见 Badie-iOS/docs/CLUB_NIGHT.md）
-- - 排场：球群某一场的“当晚”页。到场名单就是这一场的报名（现场加的人也记成一行访客报名），排人的规则全在这里
--   （night_pick）：先挑今晚场数最少的，一样多挑等得最久的；晚到、休息回来的人从在场最少的场数算起
-- - 比赛：独立的循环赛（单打循环、双打固定搭档、双打轮换搭档、分组循环 + 决赛），对阵在开始时排好，哪片场地空了就上下一场
-- - 收款：场次上的“每人多少钱”、报名那一行上的已付；收款方式在“我的”里填，钱不经过 Badie
-- - 帮手：组织者每晚（每场比赛）最多点 3 个注册用户，能排场、输比分，不能收款、结束或删除；当晚结束 3 小时后自动失效
-- - 公开看板（/live/<码>/）不用登录，只有名字；排场的看板当晚结束 24 小时后失效，比赛的最终排名留 7 天
-- - 旧版 App：推送和通知文字自己写全了，链接是现有的球群页；比赛的通知是新类型 match

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

-- 到场和收款记在报名那一行上：名单、收款都只有一份
alter table public.session_signups
  add column attendance text check (attendance in ('here', 'resting', 'left')),  -- 空 = 还没到
  add column queued_at timestamptz,                    -- 开始等的时间（到了、打完、休息回来）
  add column games_credit smallint not null default 0, -- 晚到、休息回来的人补的场数（从在场最少的算起）
  add column next_up boolean not null default false,   -- 组织者手动放到下一场
  add column owes boolean,                             -- 空 = 按规则（标了到场的人；没用排场就是报上名的人），true 加回来，false 不用付
  add column paid_at timestamptz,
  add column paid_self boolean not null default false, -- “我付了”是自己标的
  add column pay_token_hash text unique;               -- 访客提醒邮件里付款链接的凭证（哈希）

-- 每人多少钱（下一周同一场默认上次的数），提醒没付的人的时间（12 小时一次）
alter table public.group_sessions
  add column fee numeric(7, 2) check (fee > 0 and fee <= 1000),
  add column fee_reminded_at timestamptz;

-- 收款方式（“我的 → 收款方式”）：只给同一场的人看，公开网页上不出现；访客在自己报过名的设备上看不到 Zelle
create table public.payment_handles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  venmo text check (venmo ~ '^[A-Za-z0-9_-]{5,30}$'),
  cashapp text check (cashapp ~ '^[A-Za-z][A-Za-z0-9]{0,19}$'),
  paypal text check (paypal ~ '^[A-Za-z0-9]{1,20}$'),
  zelle text check (char_length(zelle) between 5 and 254),
  updated_at timestamptz not null default now()
);

-- 排场：一场球一行（第一次打开设置时建）
create table public.club_nights (
  session_id uuid primary key references public.group_sessions (id) on delete cascade,
  courts smallint not null default 2 check (courts between 1 and 12),
  doubles boolean not null default true,
  balance boolean not null default false,              -- 按实力分队
  started_at timestamptz,
  helpers uuid[] not null default '{}' check (cardinality(helpers) <= 3),
  match_id uuid,                                       -- 正在打的比赛：排场先停
  board_code text not null unique default public.new_guest_code(),
  undo jsonb,                                          -- 最后一步怎么撤（10 秒内）
  undo_until timestamptz
);

-- 排场里的每一场：players 是报名那一行的 id，双打前两个一队、后两个一队
create table public.night_games (
  id bigint generated always as identity primary key,
  session_id uuid not null references public.club_nights (session_id) on delete cascade,
  court smallint not null,
  players uuid[] not null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  score text check (char_length(score) <= 40)
);
create index night_games_session_idx on public.night_games (session_id);
-- 一片场地同时只有一场：两台手机同时排同一片场地，后到的失败
create unique index night_games_open_court_idx on public.night_games (session_id, court) where ended_at is null;

-- 比赛
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  session_id uuid references public.group_sessions (id) on delete set null,  -- 从“当晚”开的
  name text not null check (char_length(name) between 1 and 40),
  venue_id text references public.venues (id),
  courts smallint not null check (courts between 1 and 12),
  format text not null check (format in ('singles', 'fixed', 'rotating', 'groups')),
  doubles boolean not null default false,              -- 排名按队：双打固定搭档、两人一队的分组循环
  points smallint not null check (points in (11, 15, 21)),
  best_of smallint not null check (best_of in (1, 3)),
  win_by_two boolean not null default true,
  rounds smallint not null check (rounds between 1 and 127),  -- 排了几轮（只打几轮时少于完整循环）
  pools smallint check (pools between 2 and 4),
  advance smallint check (advance between 1 and 2),
  helpers uuid[] not null default '{}' check (cardinality(helpers) <= 3),
  board_code text not null unique default public.new_guest_code(),
  status text not null default 'live' check (status in ('live', 'done')),
  tie_at_cut boolean not null default false,           -- 分组出线卡在并列上：组织者可以改谁出线
  undo jsonb,
  undo_until timestamptz,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);
create index matches_owner_idx on public.matches (owner_id, created_at desc);
create index matches_session_idx on public.matches (session_id) where session_id is not null;

alter table public.club_nights add constraint club_nights_match_fkey
  foreign key (match_id) references public.matches (id) on delete set null;

create table public.match_players (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  name text not null check (char_length(name) between 1 and 24),
  rating numeric,
  seq smallint not null,                               -- 加入的先后，排对阵和显示都按它
  team smallint,                                       -- 固定搭档：同一个数是一队
  pool smallint,                                       -- 分组循环：第几组
  withdrawn_at timestamptz,
  unique (match_id, user_id)
);
create index match_players_match_idx on public.match_players (match_id, seq);
create index match_players_user_idx on public.match_players (user_id);

-- 对阵：side_a / side_b 是 match_players 的 id；scores 是每局两个数 [a1, b1, a2, b2, …]
create table public.match_games (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.matches (id) on delete cascade,
  round smallint not null,
  seq smallint not null,
  stage text not null default 'pool' check (stage in ('pool', 'semi', 'final')),
  pool smallint,
  side_a uuid[] not null,
  side_b uuid[] not null,
  court smallint,
  status text not null default 'queued' check (status in ('queued', 'playing', 'done', 'cancelled', 'skipped')),
  started_at timestamptz,
  scores smallint[],
  winner smallint check (winner in (1, 2)),
  walkover boolean not null default false,             -- 退赛：算对方赢，不计分
  scored_by uuid references auth.users (id) on delete set null,
  edited_by uuid references auth.users (id) on delete set null,
  flagged boolean not null default false,              -- 有球员点了“不对”
  version int not null default 0
);
create index match_games_match_idx on public.match_games (match_id, round, seq);

-- 只推送、不进通知列表的消息（“轮到你了”）：同一个 collapse 的在锁屏上互相替换。推送服务取走就删
create table public.live_pushes (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  body text not null,
  link text not null,
  collapse text not null,
  created_at timestamptz not null default now()
);

alter table public.payment_handles enable row level security;
alter table public.club_nights enable row level security;
alter table public.night_games enable row level security;
alter table public.matches enable row level security;
alter table public.match_players enable row level security;
alter table public.match_games enable row level security;
alter table public.live_pushes enable row level security;
revoke all on public.payment_handles, public.club_nights, public.night_games, public.matches, public.match_players,
  public.match_games, public.live_pushes from anon, authenticated;
grant all on public.payment_handles, public.club_nights, public.night_games, public.matches, public.match_players,
  public.match_games, public.live_pushes to service_role;

create trigger live_pushes_push after insert on public.live_pushes
  referencing new table as fresh for each statement execute function public.push_new_notifications();

-- 推送服务取活：原来的通知和聊天推送，加上 live_pushes（带 collapse，取走就删，2 分钟前的直接丢掉）
create or replace function public.claim_push_batch()
returns jsonb language sql security definer set search_path = '' as $$
  with picked as (
    update public.notifications n set push_tried_at = now()
    where n.id in (select x.id from public.notifications x
                   where x.push_tried_at is null and x.created_at > now() - interval '2 minutes'
                     and exists (select 1 from public.push_devices d where d.user_id = x.user_id)
                   order by x.id limit 200 for update skip locked)
    returning n.id, n.user_id, n.title, n.body, n.link
  ), chats as (
    delete from public.chat_pushes c
    where c.id in (select x.id from public.chat_pushes x order by x.id limit 200 for update skip locked)
    returning c.*
  ), lives as (
    delete from public.live_pushes l
    where l.id in (select x.id from public.live_pushes x order by x.id limit 200 for update skip locked)
    returning l.*
  )
  select coalesce(jsonb_agg(item), '[]') from (
    select jsonb_build_object('id', p.id, 'kind', d.kind, 'token', d.token, 'keys', d.keys,
                              'title', p.title, 'body', p.body, 'link', p.link) as item
    from picked p join public.push_devices d on d.user_id = p.user_id
    union all
    select jsonb_build_object('id', null, 'kind', d.kind, 'token', d.token, 'keys', d.keys,
                              'title', c.title, 'body', c.body, 'link', c.link,
                              'chat', jsonb_build_object('thread', c.thread, 'sender', c.sender_id, 'name', pr.nickname,
                                                         'avatar', pr.avatar_path, 'group', c.group_name, 'members', c.members))
    from chats c join public.push_devices d on d.user_id = c.user_id left join public.profiles pr on pr.id = c.sender_id
    where c.created_at > now() - interval '2 minutes'
    union all
    select jsonb_build_object('id', null, 'kind', d.kind, 'token', d.token, 'keys', d.keys,
                              'title', l.title, 'body', l.body, 'link', l.link, 'collapse', l.collapse)
    from lives l join public.push_devices d on d.user_id = l.user_id
    where l.created_at > now() - interval '2 minutes'
  ) items
$$;
revoke execute on function public.claim_push_batch() from public, anon, authenticated;
grant execute on function public.claim_push_batch() to service_role;

-- ---------------------------------------------------------------------------
-- 共用的小工具（都不对外）
-- ---------------------------------------------------------------------------

-- 一条只推送的消息，按收件人的语言
create function public.live_push(p_user uuid, p_title text, p_body text, p_link text, p_collapse text, p_params jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.live_pushes (user_id, title, body, link, collapse)
  select p_user, public.render_text(l.locale, p_title, p_params), public.render_text(l.locale, p_body, p_params), p_link, p_collapse
  from (select coalesce((select locale from public.profiles where id = p_user), 'en') as locale) l
  where exists (select 1 from public.push_devices d where d.user_id = p_user)
$$;

-- 名字：2–20 个字，不能留电话和链接，过不当词（和访客报名一样）
create function public.clean_player_name(p_name text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare
  clean text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
begin
  if char_length(clean) not between 2 and 20 then raise exception 'invalid_guest_name' using errcode = '22023'; end if;
  if clean ~* '(https?:|www\.|@|\d{5,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
  if public.has_offensive(clean) then raise exception 'objectionable_content' using errcode = '22023'; end if;
  return clean;
end
$$;

-- 金额写成 “$12” / “$12.50”
create function public.money_text(p_amount numeric)
returns text language sql immutable set search_path = '' as $$
  select '$' || case when p_amount = trunc(p_amount) then trunc(p_amount)::text else to_char(p_amount, 'FM999990.00') end
$$;

-- 比分里一边的总分：scores 是 [a1, b1, a2, b2, …]，side 1 取单数位，2 取双数位
create function public.side_points(p_scores smallint[], p_side int)
returns int language sql immutable set search_path = '' as $$
  select coalesce(sum(p_scores[i]), 0)::int from generate_subscripts(p_scores, 1) i where i % 2 = p_side % 2
$$;

-- 按规则判比分：合规就返回赢的一边（1 / 2），不合规返回空。
-- 一局：先到分的赢；要领先 2 分时到分后拉开 2 分，或者打到封顶（21 → 30、15 → 21、11 → 15）；三局两胜：先赢两局，赢了就不再有下一局
create function public.score_winner(p_scores int[], p_points int, p_best_of int, p_win_by_two boolean)
returns smallint language plpgsql immutable set search_path = '' as $$
declare
  cap int := case p_points when 21 then 30 when 15 then 21 else 15 end;
  wins int[] := array[0, 0];
  hi int;
  lo int;
  need int := p_best_of / 2 + 1;
begin
  if p_scores is null or cardinality(p_scores) = 0 or cardinality(p_scores) % 2 = 1 or cardinality(p_scores) > 2 * p_best_of then
    return null;
  end if;
  for i in 1..cardinality(p_scores) / 2 loop
    -- 已经有人赢够了还在填下一局
    if wins[1] = need or wins[2] = need then return null; end if;
    hi := greatest(p_scores[2 * i - 1], p_scores[2 * i]);
    lo := least(p_scores[2 * i - 1], p_scores[2 * i]);
    if lo < 0 or hi = lo then return null; end if;
    if not (case when not p_win_by_two then hi = p_points
                 else (hi = p_points and lo <= p_points - 2) or (hi > p_points and hi <= cap and (hi - lo = 2 or (hi = cap and lo = cap - 1))) end) then
      return null;
    end if;
    if p_scores[2 * i - 1] > p_scores[2 * i] then wins[1] := wins[1] + 1; else wins[2] := wins[2] + 1; end if;
  end loop;
  return case when wins[1] = need then 1 when wins[2] = need then 2 end;
end
$$;

-- 不按规则时（时间到没打完）谁赢：赢的局多的；局数一样看总分；还一样就判不了
create function public.loose_winner(p_scores int[])
returns smallint language sql immutable set search_path = '' as $$
  select case when w.a > w.b then 1 when w.b > w.a then 2
              when public.side_points(p_scores::smallint[], 1) > public.side_points(p_scores::smallint[], 2) then 1
              when public.side_points(p_scores::smallint[], 2) > public.side_points(p_scores::smallint[], 1) then 2 end::smallint
  from (select count(*) filter (where p_scores[2 * i - 1] > p_scores[2 * i]) as a,
               count(*) filter (where p_scores[2 * i - 1] < p_scores[2 * i]) as b
        from generate_series(1, cardinality(p_scores) / 2) i) w
$$;

-- 循环赛一轮的对阵（圆桌法）：m 个位置（双数），第 r 轮（从 0 起）。m - 1 轮里每两个位置正好碰一次
create function public.round_robin_pairs(p_m int, p_round int)
returns table (a int, b int) language sql immutable set search_path = '' as $$
  select p_round % (p_m - 1), p_m - 1
  union all
  select (p_round + i) % (p_m - 1), (p_round - i + p_m - 1) % (p_m - 1) from generate_series(1, p_m / 2 - 1) i
$$;

revoke execute on function public.live_push(uuid, text, text, text, text, jsonb), public.clean_player_name(text),
  public.money_text(numeric), public.side_points(smallint[], int), public.score_winner(int[], int, int, boolean),
  public.loose_winner(int[]), public.round_robin_pairs(int, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 排场
-- ---------------------------------------------------------------------------

-- 我在这一场的角色：球群的组织者，或者当晚的帮手（结束 3 小时后失效）
create function public.night_role(p_session uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case when public.is_organizer(gs.group_id, auth.uid()) then 'organizer'
              when auth.uid() = any(n.helpers) and now() < gs.ends_at + interval '3 hours' then 'helper' end
  from public.group_sessions gs left join public.club_nights n on n.session_id = gs.id
  where gs.id = p_session
$$;

-- 改排场前的检查：有权限，而且是当晚（开场前 1 小时到结束后 3 小时）
create function public.night_guard(p_session uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare
  role text := public.night_role(p_session);
begin
  if role is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  if not exists (select 1 from public.group_sessions where id = p_session and cancelled_at is null
                 and now() between starts_at - interval '1 hour' and ends_at + interval '3 hours') then
    raise exception 'night_closed' using errcode = 'P0002';
  end if;
  return role;
end
$$;

-- 今晚的人：名字（同名的加数字：“Tony 2”）、到场、今晚打了几场（games 是真打的，eff 加上补的）、在不在场上。
-- 没到场也没候补的报名都在；实力：注册用户的等级，访客按在场的人的平均（没有就 3）
create function public.night_people(p_session uuid)
returns table (id uuid, user_id uuid, name text, guest boolean, attendance text, waitlisted boolean, games int, eff int,
               queued_at timestamptz, signed_up_at timestamptz, next_up boolean, on_court smallint, rating numeric)
language sql stable security definer set search_path = '' as $$
  with plays as (
    select x.sid, count(*)::int as games, max(g.court) filter (where g.ended_at is null) as on_court
    from public.night_games g cross join lateral unnest(g.players) x(sid)
    where g.session_id = p_session group by x.sid
  ), people as (
    select su.id, su.user_id, coalesce(p.nickname, su.guest_name) as base, su.user_id is null as guest, su.attendance, su.waitlisted,
           coalesce(pl.games, 0) as games, coalesce(pl.games, 0) + su.games_credit as eff, su.queued_at, su.signed_up_at, su.next_up,
           pl.on_court, p.rating
    from public.session_signups su
    left join public.profiles p on p.id = su.user_id
    left join plays pl on pl.sid = su.id
    where su.session_id = p_session and (su.user_id is null or p.id is not null)
  )
  select id, user_id,
         case when n > 1 then base || ' ' || n else base end, guest, attendance, waitlisted, games, eff, queued_at, signed_up_at, next_up, on_court,
         coalesce(rating, avg(rating) filter (where attendance = 'here') over (), 3)
  from (select *, row_number() over (partition by lower(base) order by signed_up_at) as n from people) x
$$;

-- 两个人今晚当过几次搭档
create function public.night_partnered(p_session uuid, p_a uuid, p_b uuid)
returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.night_games
  where session_id = p_session and (players[1:2] @> array[p_a, p_b] or players[3:4] @> array[p_a, p_b])
$$;

-- 下一场挑谁（排人的规则只在这里）：等着的人（到了、不在场上、不在 p_exclude 里）里，
-- 手动放到下一场的先，再按今晚场数（含补的）少的、等得久的。最后一个人在场数一样的人里挑，尽量不让同一组人重复。
-- 双打再分队：尽量不和今晚搭档过的人再搭；开了“按实力分队”时两队实力尽量接近。人不够返回空
create function public.night_pick(p_session uuid, p_exclude uuid[] default '{}')
returns uuid[] language plpgsql stable security definer set search_path = '' as $$
declare
  n public.club_nights;
  need int;
  ids uuid[];
  effs int[];
  forced boolean[];
  picked uuid[];
  best uuid[];
  best_cost numeric;
  cost numeric;
  option uuid[];
  r jsonb := '{}'::jsonb;
begin
  select * into n from public.club_nights where session_id = p_session;
  need := case when n.doubles then 4 else 2 end;
  select array_agg(p.id order by p.next_up desc, p.eff, p.queued_at nulls first, p.signed_up_at),
         array_agg(p.eff order by p.next_up desc, p.eff, p.queued_at nulls first, p.signed_up_at),
         array_agg(p.next_up order by p.next_up desc, p.eff, p.queued_at nulls first, p.signed_up_at)
    into ids, effs, forced
  from public.night_people(p_session) p
  where p.attendance = 'here' and p.on_court is null and not p.id = any(coalesce(p_exclude, '{}'));
  if coalesce(cardinality(ids), 0) < need then return null; end if;

  picked := ids[1:need];
  -- 这一组人以前一起打过：换成场数一样、等得稍短的下一个人
  for i in need + 1..cardinality(ids) loop
    exit when effs[i] <> effs[need] or forced[need]
      or not exists (select 1 from public.night_games g where g.session_id = p_session
                     and g.players @> picked and cardinality(g.players) = need);
    picked := ids[1:need - 1] || ids[i];
  end loop;
  if not n.doubles then return picked; end if;

  select jsonb_object_agg(p.id, p.rating) into r from public.night_people(p_session) p where p.id = any(picked);
  -- 四个人分两队只有三种分法
  foreach option slice 1 in array array[[picked[1], picked[2], picked[3], picked[4]],
                                        [picked[1], picked[3], picked[2], picked[4]],
                                        [picked[1], picked[4], picked[2], picked[3]]] loop
    cost := 10 * (public.night_partnered(p_session, option[1], option[2]) + public.night_partnered(p_session, option[3], option[4]));
    if n.balance then
      cost := cost + abs((r ->> option[1]::text)::numeric + (r ->> option[2]::text)::numeric
                         - (r ->> option[3]::text)::numeric - (r ->> option[4]::text)::numeric);
    end if;
    if best is null or cost < best_cost then best := option; best_cost := cost; end if;
  end loop;
  return best;
end
$$;

-- 空着的场地排上人（排场开始了、没在打比赛时）。上场的注册球员收一条“轮到你了”（同一晚的互相替换）。返回新开的几场
create function public.night_fill(p_session uuid)
returns bigint[] language plpgsql security definer set search_path = '' as $$
declare
  n public.club_nights;
  picked uuid[];
  started bigint[] := '{}'::bigint[];
  game bigint;
  names jsonb;
  player record;
  link text := '/app/groups/' || (select group_id from public.group_sessions where id = p_session) || '/';
begin
  select * into n from public.club_nights where session_id = p_session for update;
  if n.started_at is null or exists (select 1 from public.matches m where m.id = n.match_id and m.status = 'live') then
    return started;
  end if;
  for c in 1..n.courts loop
    continue when exists (select 1 from public.night_games where session_id = p_session and court = c and ended_at is null);
    picked := public.night_pick(p_session);
    exit when picked is null;
    insert into public.night_games (session_id, court, players) values (p_session, c, picked) returning id into game;
    started := started || game;
    update public.session_signups set next_up = false where id = any(picked);

    select jsonb_object_agg(p.id, p.name) into names from public.night_people(p_session) p where p.id = any(picked);
    for player in
      select su.user_id, x.i::int as i from unnest(picked) with ordinality x(id, i) join public.session_signups su on su.id = x.id
      where su.user_id is not null and su.attendance = 'here'
    loop
      perform public.live_push(player.user_id, 'Your turn: Court {court}',
        case when cardinality(picked) = 2 then 'Against {a}.' else 'With {partner}, against {a} and {b}.' end, link,
        'night:' || p_session,
        case when cardinality(picked) = 2 then jsonb_build_object('court', c, 'a', names ->> picked[3 - player.i]::text)
             else jsonb_build_object('court', c,
                    'partner', names ->> picked[case player.i when 1 then 2 when 2 then 1 when 3 then 4 else 3 end]::text,
                    'a', names ->> picked[case when player.i <= 2 then 3 else 1 end]::text,
                    'b', names ->> picked[case when player.i <= 2 then 4 else 2 end]::text) end);
    end loop;
  end loop;
  return started;
end
$$;

-- 撤销要用的：这一晚每个人的排队状态
create function public.night_snapshot(p_session uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'queued_at', queued_at, 'next_up', next_up)), '[]')
  from public.session_signups where session_id = p_session
$$;

revoke execute on function public.night_role(uuid), public.night_guard(uuid), public.night_people(uuid),
  public.night_partnered(uuid, uuid, uuid), public.night_pick(uuid, uuid[]), public.night_fill(uuid),
  public.night_snapshot(uuid) from public, anon, authenticated;

-- 当晚页（组织者和帮手）。还没设置过时 started 为 false、用默认的场地数
create function public.night_state(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  role text := public.night_role(p_session);
  n public.club_nights;
  s record;
  first uuid[];
  second uuid[];
begin
  if role is null then return null; end if;
  select gs.id, gs.group_id, gs.starts_at, gs.ends_at, g.name, v.name as venue, v.time_zone_id as tz into s
    from public.group_sessions gs join public.play_groups g on g.id = gs.group_id
    join public.venues v on v.id = coalesce(gs.venue_id, g.venue_id) where gs.id = p_session;
  select * into n from public.club_nights where session_id = p_session;
  if n.started_at is not null then
    first := public.night_pick(p_session);
    second := public.night_pick(p_session, first);
  end if;
  return jsonb_build_object(
    'session_id', s.id, 'group_id', s.group_id, 'group', s.name, 'venue', s.venue, 'tz', s.tz,
    'starts_at', s.starts_at, 'ends_at', s.ends_at, 'role', role,
    'open', now() between s.starts_at - interval '1 hour' and s.ends_at + interval '3 hours',
    'started', n.started_at is not null, 'courts', coalesce(n.courts, 2), 'doubles', coalesce(n.doubles, true),
    'balance', coalesce(n.balance, false), 'board_code', n.board_code,
    'match_id', (select m.id from public.matches m where m.id = n.match_id),
    'match_live', exists (select 1 from public.matches m where m.id = n.match_id and m.status = 'live'),
    'helpers', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname)), '[]')
                from public.profiles p where p.id = any(n.helpers)),
    'undo_until', case when n.undo_until > now() then n.undo_until end,
    'people', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', p.id, 'name', p.name, 'user_id', p.user_id, 'guest', p.guest, 'status', coalesce(p.attendance, 'absent'),
                 'waitlisted', p.waitlisted, 'games', p.games, 'on_court', p.on_court, 'next_up', p.next_up)
               order by p.waitlisted, p.signed_up_at), '[]') from public.night_people(p_session) p),
    'games', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'court', g.court, 'players', g.players, 'started_at', g.started_at)
                                        order by g.court), '[]')
              from public.night_games g where g.session_id = p_session and g.ended_at is null),
    'next', case when first is null then '[]'::jsonb when second is null then jsonb_build_array(first)
                 else jsonb_build_array(first, second) end);
end
$$;

-- 设置：几片场地、单打 / 双打、按实力分队（随时能改；减场地时正在打的打完再收）
create function public.night_settings(p_session uuid, p_courts int, p_doubles boolean, p_balance boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.night_guard(p_session);
  if p_courts not between 1 and 12 then raise exception 'invalid_courts' using errcode = '22023'; end if;
  insert into public.club_nights (session_id, courts, doubles, balance)
    values (p_session, p_courts, coalesce(p_doubles, true), coalesce(p_balance, false))
    on conflict (session_id) do update set courts = excluded.courts, doubles = excluded.doubles, balance = excluded.balance;
  perform public.night_fill(p_session);
end
$$;

-- 开始排场：空着的场地马上排上人
create function public.night_start(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.night_guard(p_session);
  insert into public.club_nights (session_id, started_at) values (p_session, now())
    on conflict (session_id) do update set started_at = coalesce(public.club_nights.started_at, now());
  perform public.night_fill(p_session);
end
$$;

-- 点名：到了 / 休息 / 走了 / 没到（空）。p_signups 为空 = “全到了”（报上名、还没标的人）。
-- 到了（包括休息回来）的人从在场的人里最少的场数算起，排在等候的最后；候补的人标到了就不再是候补。
-- 正在场上的人标走了或休息，打完这场再离开
create function public.night_mark(p_session uuid, p_signups uuid[], p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  low int;
begin
  perform public.night_guard(p_session);
  if p_status is not null and p_status not in ('here', 'resting', 'left') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  if p_signups is null then
    select array_agg(id) into p_signups from public.session_signups
      where session_id = p_session and attendance is null and not waitlisted;
  end if;
  if p_status = 'here' then
    select min(p.eff) into low from public.night_people(p_session) p where p.attendance = 'here' and not p.id = any(p_signups);
    update public.session_signups su
      set attendance = 'here', waitlisted = false, queued_at = now(),
          games_credit = greatest(su.games_credit, coalesce(low, 0) - (select count(*) from public.night_games g
                                                                       where g.session_id = p_session and su.id = any(g.players)))
      where su.session_id = p_session and su.id = any(p_signups) and su.attendance is distinct from 'here';
  else
    update public.session_signups set attendance = p_status, next_up = false
      where session_id = p_session and id = any(p_signups);
  end if;
  if exists (select 1 from public.club_nights where session_id = p_session) then perform public.night_fill(p_session); end if;
end
$$;

-- 现场加人（访客，不用账号）：记成一行访客报名，标到了。连点两次（30 秒内同一个名字）只加一个。返回报名那一行的 id
create function public.night_add(p_session uuid, p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  clean text;
  low int;
  added uuid;
begin
  perform public.night_guard(p_session);
  clean := public.clean_player_name(p_name);
  perform 1 from public.group_sessions where id = p_session for update;
  select id into added from public.session_signups
    where session_id = p_session and lower(guest_name) = lower(clean) and signed_up_at > now() - interval '30 seconds';
  if added is not null then return added; end if;
  select min(p.eff) into low from public.night_people(p_session) p where p.attendance = 'here';
  insert into public.session_signups (session_id, waitlisted, guest_name, guest_token_hash, attendance, queued_at, games_credit)
    values (p_session, false, clean, public.guest_token_hash(encode(extensions.gen_random_bytes(18), 'base64')), 'here', now(), coalesce(low, 0))
    returning id into added;
  if exists (select 1 from public.club_nights where session_id = p_session) then perform public.night_fill(p_session); end if;
  return added;
end
$$;

-- 打完了：可以带比分；四个人回到等候的最后，这片场地排上下一场。
-- 已经打完的再按一次（另一台手机、网不好重试）报 court_changed，不会多空出一片场地
create function public.night_finish(p_game bigint, p_score text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.night_games;
  before jsonb;
  started bigint[];
  clean_score text := nullif(btrim(coalesce(p_score, '')), '');
begin
  select * into g from public.night_games where id = p_game;
  if g.id is null then raise exception 'court_changed' using errcode = 'P0002'; end if;
  perform public.night_guard(g.session_id);
  if clean_score is not null and (char_length(clean_score) > 40 or clean_score !~ '^[0-9 :,/-]+$') then
    raise exception 'invalid_score' using errcode = '22023';
  end if;
  perform 1 from public.club_nights where session_id = g.session_id for update;
  update public.night_games set ended_at = now(), score = clean_score where id = p_game and ended_at is null;
  if not found then raise exception 'court_changed' using errcode = 'P0002'; end if;
  before := public.night_snapshot(g.session_id);
  update public.session_signups set queued_at = now() where id = any(g.players) and attendance = 'here';
  started := public.night_fill(g.session_id);
  update public.club_nights
    set undo = jsonb_build_object('kind', 'finish', 'game', p_game, 'started', started, 'people', before), undo_until = now() + interval '10 seconds'
    where session_id = g.session_id;
end
$$;

-- 换人：场上的 p_out 换成等着的 p_in（p_out 回到原来的位置，这场不算他的）
create function public.night_swap(p_game bigint, p_out uuid, p_in uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.night_games;
  before jsonb;
begin
  select * into g from public.night_games where id = p_game;
  if g.id is null then raise exception 'court_changed' using errcode = 'P0002'; end if;
  perform public.night_guard(g.session_id);
  perform 1 from public.club_nights where session_id = g.session_id for update;
  select * into g from public.night_games where id = p_game;
  if g.ended_at is not null or not p_out = any(g.players) then raise exception 'court_changed' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.night_people(g.session_id) p where p.id = p_in and p.attendance = 'here' and p.on_court is null) then
    raise exception 'not_waiting' using errcode = '22023';
  end if;
  before := public.night_snapshot(g.session_id);
  update public.night_games set players = array_replace(players, p_out, p_in) where id = p_game;
  update public.session_signups set next_up = false where id = p_in;
  update public.club_nights
    set undo = jsonb_build_object('kind', 'swap', 'game', p_game, 'players', g.players, 'people', before), undo_until = now() + interval '10 seconds'
    where session_id = g.session_id;
end
$$;

-- 手动排：放到下一场（p_next），或者跳过（排到等候的最后）
create function public.night_bump(p_signup uuid, p_next boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  session uuid := (select session_id from public.session_signups where id = p_signup);
begin
  perform public.night_guard(session);
  update public.session_signups
    set next_up = coalesce(p_next, false), queued_at = case when p_next then queued_at else now() end
    where id = p_signup;
end
$$;

-- 撤销最后一步（10 秒内）：打完了 → 这场接着打、刚排上的那场撤掉；换人 → 换回来
create function public.night_undo(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  n public.club_nights;
begin
  perform public.night_guard(p_session);
  select * into n from public.club_nights where session_id = p_session for update;
  if n.undo is null or n.undo_until < now() then raise exception 'nothing_to_undo' using errcode = 'P0002'; end if;
  delete from public.night_games
    where session_id = p_session and ended_at is null and id in (select jsonb_array_elements_text(n.undo -> 'started')::bigint);
  if n.undo ->> 'kind' = 'finish' then
    update public.night_games set ended_at = null, score = null where id = (n.undo ->> 'game')::bigint;
  else
    update public.night_games set players = array(select jsonb_array_elements_text(n.undo -> 'players')::uuid)
      where id = (n.undo ->> 'game')::bigint;
  end if;
  update public.session_signups su set queued_at = (x ->> 'queued_at')::timestamptz, next_up = (x ->> 'next_up')::boolean
    from jsonb_array_elements(n.undo -> 'people') x where su.id = (x ->> 'id')::uuid;
  update public.club_nights set undo = null, undo_until = null where session_id = p_session;
end
$$;

-- 帮手（组织者点，最多 3 个到场的注册用户）。新点的人收到推送和通知
create function public.night_helpers(p_session uuid, p_users uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  old uuid[];
  s record;
  helper uuid;
begin
  if public.night_guard(p_session) <> 'organizer' then raise exception 'not_organizer' using errcode = '42501'; end if;
  p_users := array(select distinct x from unnest(coalesce(p_users, '{}')) x);
  if cardinality(p_users) > 3 then raise exception 'too_many_helpers' using errcode = '22023'; end if;
  if exists (select 1 from unnest(p_users) x where not exists (select 1 from public.session_signups
                                                              where session_id = p_session and user_id = x)) then
    raise exception 'not_attending' using errcode = '22023';
  end if;
  insert into public.club_nights (session_id) values (p_session) on conflict (session_id) do nothing;
  select helpers into old from public.club_nights where session_id = p_session for update;
  update public.club_nights set helpers = p_users where session_id = p_session;
  select gs.group_id, gs.starts_at, g.name, coalesce(gs.venue_id, g.venue_id) as court into s
    from public.group_sessions gs join public.play_groups g on g.id = gs.group_id where gs.id = p_session;
  foreach helper in array p_users loop
    continue when helper = any(old) or helper = auth.uid();
    perform public.notify(helper, 'group', '{name} asked you to help tonight', '{group} · {when}. You can run the courts and enter scores.',
      '/app/groups/' || s.group_id || '/',
      public.slot(s.starts_at, s.court) || jsonb_build_object('group', s.name, 'name', (select nickname from public.profiles where id = auth.uid())));
  end loop;
end
$$;

-- 比赛打完，回到排场
create function public.night_resume(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.night_guard(p_session);
  update public.club_nights set match_id = null where session_id = p_session;
  perform public.night_fill(p_session);
end
$$;

revoke execute on function public.night_state(uuid), public.night_settings(uuid, int, boolean, boolean), public.night_start(uuid),
  public.night_mark(uuid, uuid[], text), public.night_add(uuid, text), public.night_finish(bigint, text),
  public.night_swap(bigint, uuid, uuid), public.night_bump(uuid, boolean), public.night_undo(uuid),
  public.night_helpers(uuid, uuid[]), public.night_resume(uuid) from public, anon;
grant execute on function public.night_state(uuid), public.night_settings(uuid, int, boolean, boolean), public.night_start(uuid),
  public.night_mark(uuid, uuid[], text), public.night_add(uuid, text), public.night_finish(bigint, text),
  public.night_swap(bigint, uuid, uuid), public.night_bump(uuid, boolean), public.night_undo(uuid),
  public.night_helpers(uuid, uuid[]), public.night_resume(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 收款
-- ---------------------------------------------------------------------------

-- 谁收钱：填金额的那个组织者，没填过就是群主
alter table public.group_sessions add column fee_by uuid references auth.users (id) on delete set null;

-- 每人多少钱：这一场填的，没填就用同一个每周场次上一次填的
create function public.session_fee(p_session uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(gs.fee, (select p.fee from public.group_sessions p where p.schedule_id = gs.schedule_id and p.starts_at < gs.starts_at
                                                                     and p.fee is not null order by p.starts_at desc limit 1))
  from public.group_sessions gs where gs.id = p_session
$$;

create function public.session_payee(p_session uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select coalesce(gs.fee_by, g.owner_id) from public.group_sessions gs join public.play_groups g on g.id = gs.group_id where gs.id = p_session
$$;

-- 这一场谁要付：标过到场的人（用了排场）；没用排场就是报上名的人。组织者可以改（不用付 / 加回来），收钱的人自己不用付
create function public.session_payers(p_session uuid)
returns table (id uuid, owes boolean) language sql stable security definer set search_path = '' as $$
  select su.id,
         su.user_id is distinct from public.session_payee(p_session)
         and coalesce(su.owes, case when bool_or(su.attendance is not null) over () then su.attendance is not null else not su.waitlisted end)
  from public.session_signups su where su.session_id = p_session
$$;

-- 收钱的人的收款方式（p_zelle：注册用户能看到 Zelle，访客看不到）
create function public.payee_handles(p_user uuid, p_zelle boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object('venmo', h.venmo, 'cashapp', h.cashapp, 'paypal', h.paypal,
                                              'zelle', case when p_zelle then h.zelle end))
  from public.payment_handles h where h.user_id = p_user
$$;

-- 收款的时间：组织者开场前 1 小时到结束后 30 天
create function public.pay_guard(p_session uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_organizer((select group_id from public.group_sessions where id = p_session), auth.uid()) then
    raise exception 'not_organizer' using errcode = '42501';
  end if;
  if not exists (select 1 from public.group_sessions where id = p_session and cancelled_at is null
                 and now() between starts_at - interval '1 hour' and ends_at + interval '30 days') then
    raise exception 'night_closed' using errcode = 'P0002';
  end if;
end
$$;

revoke execute on function public.session_fee(uuid), public.session_payee(uuid), public.session_payers(uuid),
  public.payee_handles(uuid, boolean), public.pay_guard(uuid) from public, anon, authenticated;

-- 我的收款方式
create function public.my_payment_handles()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(public.payee_handles(auth.uid(), true), '{}')
$$;

-- 改收款方式：都可以不填。Venmo 去掉 @，Cash App 去掉 $，PayPal 只要 paypal.me/ 后面那段
create function public.set_payment_handles(p_venmo text, p_cashapp text, p_paypal text, p_zelle text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  venmo text := nullif(regexp_replace(btrim(coalesce(p_venmo, '')), '^@', ''), '');
  cashapp text := nullif(regexp_replace(btrim(coalesce(p_cashapp, '')), '^\$', ''), '');
  paypal text := nullif(regexp_replace(btrim(coalesce(p_paypal, '')), '^(https?://)?(www\.)?paypal\.me/', '', 'i'), '');
  zelle text := nullif(btrim(coalesce(p_zelle, '')), '');
begin
  if auth.uid() is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  if venmo !~ '^[A-Za-z0-9_-]{5,30}$' then raise exception 'invalid_venmo' using errcode = '22023'; end if;
  if cashapp !~ '^[A-Za-z][A-Za-z0-9]{0,19}$' then raise exception 'invalid_cashapp' using errcode = '22023'; end if;
  if paypal !~ '^[A-Za-z0-9]{1,20}$' then raise exception 'invalid_paypal' using errcode = '22023'; end if;
  if zelle !~ '^([^@\s]+@[^@\s]+\.[^@\s]+|\+?[0-9 ()-]{10,20})$' then raise exception 'invalid_zelle' using errcode = '22023'; end if;
  if coalesce(venmo, cashapp, paypal, zelle) is null then
    delete from public.payment_handles where user_id = auth.uid();
  else
    insert into public.payment_handles (user_id, venmo, cashapp, paypal, zelle) values (auth.uid(), venmo, cashapp, paypal, zelle)
      on conflict (user_id) do update set venmo = excluded.venmo, cashapp = excluded.cashapp, paypal = excluded.paypal,
                                          zelle = excluded.zelle, updated_at = now();
  end if;
end
$$;

-- 当晚 → 收款（组织者）：每人多少钱、谁要付、谁付了（自己标的单独写）、能不能提醒
create function public.night_pay(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.group_sessions;
begin
  perform public.pay_guard(p_session);
  select * into s from public.group_sessions where id = p_session;
  return jsonb_build_object(
    'amount', public.session_fee(p_session), 'amount_set', s.fee is not null,
    'payee', (select nickname from public.profiles where id = public.session_payee(p_session)),
    'payee_is_me', public.session_payee(p_session) = auth.uid(),
    'has_handles', exists (select 1 from public.payment_handles where user_id = public.session_payee(p_session)),
    'reminded_at', s.fee_reminded_at,
    'can_remind', now() >= s.starts_at and now() < s.ends_at + interval '7 days'
                  and (s.fee_reminded_at is null or s.fee_reminded_at < now() - interval '12 hours'),
    'people', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', p.id, 'name', p.name, 'guest', p.guest, 'status', coalesce(p.attendance, 'absent'),
                 'email', su.guest_email is not null, 'owes', py.owes, 'paid', su.paid_at is not null, 'paid_self', su.paid_self)
               order by p.name), '[]')
               from public.night_people(p_session) p join public.session_signups su on su.id = p.id
               join public.session_payers(p_session) py on py.id = p.id
               where py.owes or su.paid_at is not null or not p.waitlisted or p.attendance is not null));
end
$$;

-- 每人多少钱（空 = 不填）。填的人就是收钱的人
create function public.set_session_fee(p_session uuid, p_amount numeric)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.pay_guard(p_session);
  if p_amount is not null and (p_amount <= 0 or p_amount > 1000) then raise exception 'invalid_amount' using errcode = '22023'; end if;
  update public.group_sessions set fee = round(p_amount, 2), fee_by = auth.uid() where id = p_session;
end
$$;

-- 组织者标已付 / 改回没付（包括改回球员自己标的）
create function public.mark_signup_paid(p_signup uuid, p_paid boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.pay_guard((select session_id from public.session_signups where id = p_signup));
  update public.session_signups set paid_at = case when p_paid then coalesce(paid_at, now()) end, paid_self = false where id = p_signup;
end
$$;

-- 组织者改谁要付：false 不用付，true 加回来，空 = 按规则
create function public.set_signup_owes(p_signup uuid, p_owes boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.pay_guard((select session_id from public.session_signups where id = p_signup));
  update public.session_signups set owes = p_owes where id = p_signup;
end
$$;

-- 提醒没付的：注册用户收推送和通知，留了邮箱的访客收邮件（带付款链接）。同一场 12 小时一次，结束 7 天后不能再提醒。
-- 返回提醒了几个人
create function public.remind_unpaid(p_session uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare
  s record;
  params jsonb;
  person record;
  token text;
  emails jsonb := '[]'::jsonb;
  reminded int := 0;
begin
  perform public.pay_guard(p_session);
  select gs.id, gs.group_id, gs.starts_at, gs.ends_at, gs.fee_reminded_at, g.name, g.guest_code, coalesce(gs.venue_id, g.venue_id) as court into s
    from public.group_sessions gs join public.play_groups g on g.id = gs.group_id where gs.id = p_session for update of gs;
  if now() < s.starts_at or now() >= s.ends_at + interval '7 days' then raise exception 'night_closed' using errcode = 'P0002'; end if;
  if s.fee_reminded_at > now() - interval '12 hours' then raise exception 'reminded_recently' using errcode = '54000'; end if;
  params := public.slot(s.starts_at, s.court) || jsonb_build_object(
    'group', s.name, 'name', (select nickname from public.profiles where id = public.session_payee(p_session)),
    'amount', coalesce(public.money_text(public.session_fee(p_session)), ''));
  for person in
    select su.id, su.user_id, su.guest_email from public.session_signups su join public.session_payers(p_session) py on py.id = su.id
    where py.owes and su.paid_at is null
  loop
    if person.user_id is not null then
      perform public.notify(person.user_id, 'group', 'Court fee: {group}',
        case when params ->> 'amount' = '' then '{when} · Pay {name}.' else '{when} · {amount} each, paid to {name}.' end,
        '/app/groups/' || s.group_id || '/', params);
      reminded := reminded + 1;
    elsif person.guest_email is not null then
      token := translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_');
      update public.session_signups set pay_token_hash = public.guest_token_hash(token) where id = person.id;
      emails := emails || jsonb_build_array(public.guest_email(person.id, 'Court fee: {group}',
        case when params ->> 'amount' = '' then '{when} · {court}. Pay {name} here:' else '{when} · {court}. {amount} each, paid to {name}. Pay here:' end,
        'https://badie.rsvp/pay/' || token || '/'));
      reminded := reminded + 1;
    end if;
  end loop;
  -- guest_email 只填 {when}、{court}、{group}：金额和收钱的人这里补上
  perform public.send_guest_emails((select jsonb_agg(jsonb_build_object('to', e ->> 'to', 'subject', e ->> 'subject',
                                                                         'text', replace(replace(e ->> 'text', '{amount}', params ->> 'amount'), '{name}', params ->> 'name')))
                                    from jsonb_array_elements(emails) e));
  update public.group_sessions set fee_reminded_at = now() where id = p_session;
  return reminded;
end
$$;

revoke execute on function public.my_payment_handles(), public.set_payment_handles(text, text, text, text), public.night_pay(uuid),
  public.set_session_fee(uuid, numeric), public.mark_signup_paid(uuid, boolean), public.set_signup_owes(uuid, boolean),
  public.remind_unpaid(uuid) from public, anon;
grant execute on function public.my_payment_handles(), public.set_payment_handles(text, text, text, text), public.night_pay(uuid),
  public.set_session_fee(uuid, numeric), public.mark_signup_paid(uuid, boolean), public.set_signup_owes(uuid, boolean),
  public.remind_unpaid(uuid) to authenticated;

-- 付钱的人：“我付了”直接算已付（标成自己标的，组织者能改回）。p_paid = false 是点错了改回来
create function public.i_paid(p_session uuid, p_paid boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- 自己只能标没付的、改回自己标的；组织者标的不动
  update public.session_signups set paid_at = case when p_paid then now() end, paid_self = p_paid
    where session_id = p_session and user_id = auth.uid() and ((p_paid and paid_at is null) or (not p_paid and paid_self));
  if not found and not exists (select 1 from public.session_signups where session_id = p_session and user_id = auth.uid()) then
    raise exception 'signup_not_found' using errcode = 'P0002';
  end if;
end
$$;

-- 访客的付款（不登录）：这台设备上报名的凭证，或者提醒邮件里的付款链接。
-- 开场后到结束后 24 小时（付款链接 7 天）、这一场要付、有金额或者收款方式时才返回。不给 Zelle
create function public.guest_payment(p_tokens text[])
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'token', t.token, 'session_id', gs.id, 'group', g.name, 'starts_at', gs.starts_at, 'ends_at', gs.ends_at,
      'venue', v.name, 'tz', v.time_zone_id, 'to', (select nickname from public.profiles where id = public.session_payee(gs.id)),
      'amount', public.session_fee(gs.id), 'handles', coalesce(public.payee_handles(public.session_payee(gs.id), false), '{}'),
      'paid', su.paid_at is not null) order by gs.starts_at), '[]')
  from unnest(p_tokens[1:50]) t(token)
  join public.session_signups su on su.user_id is null
    and (su.guest_token_hash = public.guest_token_hash(t.token) or su.pay_token_hash = public.guest_token_hash(t.token))
  join public.group_sessions gs on gs.id = su.session_id
  join public.play_groups g on g.id = gs.group_id
  join public.venues v on v.id = coalesce(gs.venue_id, g.venue_id)
  where gs.cancelled_at is null and now() >= gs.starts_at
    and now() < gs.ends_at + case when su.pay_token_hash = public.guest_token_hash(t.token) then interval '7 days' else interval '24 hours' end
    and (select py.owes from public.session_payers(gs.id) py where py.id = su.id)
    and (public.session_fee(gs.id) is not null or public.payee_handles(public.session_payee(gs.id), false) <> '{}')
$$;

create function public.guest_i_paid(p_token text, p_paid boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.session_signups set paid_at = case when p_paid then now() end, paid_self = p_paid
    where user_id is null and (guest_token_hash = public.guest_token_hash(p_token) or pay_token_hash = public.guest_token_hash(p_token))
      and ((p_paid and paid_at is null) or (not p_paid and paid_self));
end
$$;

revoke execute on function public.i_paid(uuid, boolean), public.guest_payment(text[]), public.guest_i_paid(text, boolean) from public;
grant execute on function public.i_paid(uuid, boolean) to authenticated;
grant execute on function public.guest_payment(text[]), public.guest_i_paid(text, boolean) to anon, authenticated;

-- 访客邮箱：开了收款（填了金额）的场次留到付清或结束后 7 天（先到为准），其余照旧结束一天后删
select cron.schedule('guest-emails', '27 * * * *', $$
  update public.session_signups su set guest_email = null from public.group_sessions gs
  where gs.id = su.session_id and su.guest_email is not null and gs.ends_at < now() - interval '1 day'
    and (su.paid_at is not null or public.session_fee(gs.id) is null or gs.ends_at < now() - interval '7 days'
         or su.owes is false or (su.owes is null and su.attendance is null and su.waitlisted))$$);

-- ---------------------------------------------------------------------------
-- 球员和球群页
-- ---------------------------------------------------------------------------

-- 球群页的当天：开场前 1 小时到结束后 24 小时的场次（组织者 7 天，方便收款）。
-- can_run：组织者和帮手显示“排场”；board：排场开始后成员看“看排场”；pay：我要付的钱；unpaid：组织者看还有几个人没付
create function public.group_tonight(p_group uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  organizer boolean := public.is_organizer(p_group, me);
begin
  if me is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', gs.id, 'starts_at', gs.starts_at, 'ends_at', gs.ends_at,
      'can_run', public.night_role(gs.id) is not null and now() between gs.starts_at - interval '1 hour' and gs.ends_at + interval '3 hours',
      'board', case when n.started_at is not null and now() < gs.ends_at + interval '1 hour' then n.board_code end,
      'pay', (select jsonb_build_object('to', pr.nickname, 'amount', public.session_fee(gs.id),
                                        'handles', coalesce(public.payee_handles(pr.id, true), '{}'),
                                        'paid', su.paid_at is not null, 'paid_self', su.paid_self)
              from public.session_signups su join public.session_payers(gs.id) py on py.id = su.id
              join public.profiles pr on pr.id = public.session_payee(gs.id)
              where su.session_id = gs.id and su.user_id = me and py.owes and now() >= gs.starts_at and now() < gs.ends_at + interval '24 hours'
                and (public.session_fee(gs.id) is not null or exists (select 1 from public.payment_handles h where h.user_id = pr.id))),
      'unpaid', case when organizer then (select count(*) from public.session_payers(gs.id) py join public.session_signups su on su.id = py.id
                                          where py.owes and su.paid_at is null) end)
      order by gs.starts_at)
    from public.group_sessions gs left join public.club_nights n on n.session_id = gs.id
    where gs.group_id = p_group and gs.cancelled_at is null
      and now() between gs.starts_at - interval '1 hour' and gs.ends_at + case when organizer then interval '7 days' else interval '24 hours' end
      and (organizer or public.night_role(gs.id) is not null or public.group_role_of(p_group, me) = 'member')), '[]');
end
$$;

revoke execute on function public.group_tonight(uuid) from public, anon;
grant execute on function public.group_tonight(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 比赛
-- ---------------------------------------------------------------------------

-- 从“当晚”开的比赛记一下是哪一行报名（看板上的“我是…”和访客的凭证对得上）
alter table public.match_players add column signup_id uuid references public.session_signups (id) on delete set null;

-- 我的角色：建的人（或那一晚的组织者）organizer；帮手 helper（结束 3 小时后失效）；参赛的注册用户 player
create function public.match_role(p_match uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case when m.owner_id = auth.uid() or (m.session_id is not null and public.night_role(m.session_id) = 'organizer') then 'organizer'
              when (auth.uid() = any(m.helpers) or (m.session_id is not null and public.night_role(m.session_id) = 'helper'))
                   and (m.status = 'live' or m.ended_at > now() - interval '3 hours') then 'helper'
              when exists (select 1 from public.match_players p where p.match_id = m.id and p.user_id = auth.uid()) then 'player' end
  from public.matches m where m.id = p_match
$$;

-- 排名的单位：双打固定搭档（和两人一队的分组循环）是一队，其余是一个人。key：一个人是 id，一队是 t<队号>
create function public.match_entries(p_match uuid)
returns table (key text, name text, members uuid[], pool smallint, seed int, withdrawn boolean, rating numeric)
language sql stable security definer set search_path = '' as $$
  select x.key, string_agg(x.name, ' · ' order by x.seq), array_agg(x.id order by x.seq), min(x.pool), min(x.seq),
         bool_or(x.withdrawn_at is not null), avg(coalesce(x.rating, 3))
  from (select mp.*, case when m.format = 'fixed' or (m.format = 'groups' and m.doubles) then 't' || mp.team else mp.id::text end as key
        from public.match_players mp join public.matches m on m.id = mp.match_id where mp.match_id = p_match) x
  group by x.key
$$;

-- 积分榜：按胜率（打的场数一样时就是胜场），再看净胜分、总得分；两人（两队）还分不开看他们之间的胜负，三人以上写并列。
-- p_all = false 只算小组赛（分组循环的出线），true 连淘汰赛一起算。分组循环每组单独排
create function public.match_standings(p_match uuid, p_all boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  rows jsonb[];
  r jsonb;
  result jsonb := '[]'::jsonb;
  i int := 1;
  j int;
  pos int := 0;
  a_wins int;
  b_wins int;
begin
  select array_agg(to_jsonb(t) order by coalesce(t.pool, 0), t.rate desc nulls last, t.diff desc, t.pf desc, t.seed) into rows from (
    with sides as (
      select g.id, 1 as side, g.side_a as members, g.winner, public.side_points(g.scores, 1) as pf, public.side_points(g.scores, 2) as pa
      from public.match_games g where g.match_id = p_match and g.status = 'done' and (p_all or g.stage = 'pool')
      union all
      select g.id, 2, g.side_b, g.winner, public.side_points(g.scores, 2), public.side_points(g.scores, 1)
      from public.match_games g where g.match_id = p_match and g.status = 'done' and (p_all or g.stage = 'pool')
    )
    select e.key, e.name, e.members, e.pool, e.seed, e.withdrawn, count(s.id)::int as played,
           (count(s.id) filter (where s.winner = s.side))::int as wins, (count(s.id) filter (where s.winner <> s.side))::int as losses,
           coalesce(sum(s.pf), 0)::int as pf, coalesce(sum(s.pa), 0)::int as pa, coalesce(sum(s.pf - s.pa), 0)::int as diff,
           (count(s.id) filter (where s.winner = s.side))::numeric / nullif(count(s.id), 0) as rate
    from public.match_entries(p_match) e left join sides s on s.members @> e.members
    group by e.key, e.name, e.members, e.pool, e.seed, e.withdrawn
  ) t;
  while i <= coalesce(cardinality(rows), 0) loop
    if i = 1 or (rows[i] ->> 'pool') is distinct from (rows[i - 1] ->> 'pool') then pos := 0; end if;
    -- 和前一个人三项都一样的算一组
    j := i;
    while j < cardinality(rows) and (rows[j + 1] ->> 'pool') is not distinct from (rows[i] ->> 'pool')
          and (rows[j + 1] ->> 'rate') is not distinct from (rows[i] ->> 'rate')
          and rows[j + 1] ->> 'diff' = rows[i] ->> 'diff' and rows[j + 1] ->> 'pf' = rows[i] ->> 'pf' loop
      j := j + 1;
    end loop;
    if j = i + 1 then
      select count(*) filter (where (g.side_a @> x.a and g.side_b @> x.b and g.winner = 1) or (g.side_b @> x.a and g.side_a @> x.b and g.winner = 2)),
             count(*) filter (where (g.side_a @> x.b and g.side_b @> x.a and g.winner = 1) or (g.side_b @> x.b and g.side_a @> x.a and g.winner = 2))
        into a_wins, b_wins
        from public.match_games g,
             lateral (select array(select jsonb_array_elements_text(rows[i] -> 'members')::uuid) as a,
                             array(select jsonb_array_elements_text(rows[j] -> 'members')::uuid) as b) x
        where g.match_id = p_match and g.status = 'done' and (p_all or g.stage = 'pool');
      if b_wins > a_wins then r := rows[i]; rows[i] := rows[j]; rows[j] := r; end if;
      if a_wins <> b_wins then
        result := result || (rows[i] || jsonb_build_object('rank', pos + 1, 'tied', false))
                   || (rows[j] || jsonb_build_object('rank', pos + 2, 'tied', false));
        pos := pos + 2;
        i := j + 1;
        continue;
      end if;
    end if;
    for k in i..j loop
      result := result || (rows[k] || jsonb_build_object('rank', pos + 1, 'tied', j > i));
    end loop;
    pos := pos + j - i + 1;
    i := j + 1;
  end loop;
  return result;
end
$$;

-- 最终排名：分组循环是决赛的胜者、负者，半决赛输的两个并列第 3，其余按小组赛的成绩；其他赛制就是积分榜
create function public.match_ranking(p_match uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  m public.matches;
  table_all jsonb;
  podium text[] := '{}'::text[];
  ranks int[] := '{}'::int[];
  f record;
begin
  select * into m from public.matches where id = p_match;
  table_all := public.match_standings(p_match, true);
  if m.format <> 'groups' or not exists (select 1 from public.match_games where match_id = p_match and stage <> 'pool') then
    return table_all;
  end if;
  select g.side_a, g.side_b, g.winner into f from public.match_games g where g.match_id = p_match and g.stage = 'final' and g.status = 'done';
  if f.winner is not null then
    podium := array[(select e ->> 'key' from jsonb_array_elements(table_all) e
                     where (e -> 'members') = to_jsonb(case when f.winner = 1 then f.side_a else f.side_b end)),
                    (select e ->> 'key' from jsonb_array_elements(table_all) e
                     where (e -> 'members') = to_jsonb(case when f.winner = 1 then f.side_b else f.side_a end))];
    ranks := array[1, 2];
  end if;
  -- 半决赛输的
  select podium || coalesce(array_agg(e ->> 'key'), '{}'), ranks || coalesce(array_agg(3), '{}') into podium, ranks
    from public.match_games g join jsonb_array_elements(table_all) e
      on (e -> 'members') = to_jsonb(case when g.winner = 1 then g.side_b else g.side_a end)
    where g.match_id = p_match and g.stage = 'semi' and g.status = 'done';
  return (
    select jsonb_agg(x.e || jsonb_build_object('rank', x.rank, 'tied', x.tied) order by x.rank, x.ord)
    from (select t.e, t.ord,
                 coalesce(ranks[array_position(podium, t.e ->> 'key')],
                          row_number() over (order by case when t.e ->> 'key' = any(podium) then 0 else 1 end,
                                                      (t.e ->> 'rate')::numeric desc nulls last, (t.e ->> 'diff')::int desc,
                                                      (t.e ->> 'pf')::int desc)) as rank,
                 coalesce(ranks[array_position(podium, t.e ->> 'key')] = 3 and (select count(*) from unnest(ranks) z where z = 3) > 1, false) as tied
          from jsonb_array_elements(table_all) with ordinality t(e, ord)) x);
end
$$;

-- 每轮几场、一共几轮（建之前的预计，也用来定排几轮）
create function public.match_plan(p_format text, p_players int, p_doubles boolean, p_pools int)
returns table (full_rounds int, per_round int) language sql immutable set search_path = '' as $$
  select case when p_format = 'rotating' then p_players + p_players % 2 - 1
              when p_format = 'groups' then size + size % 2 - 1
              else entries + entries % 2 - 1 end,
         case when p_format = 'rotating' then p_players / 4
              when p_format = 'groups' then (entries / 2)
              else entries / 2 end
  from (select case when p_format = 'fixed' or (p_format = 'groups' and p_doubles) then p_players / 2 else p_players end as entries) e,
       lateral (select (e.entries + coalesce(p_pools, 2) - 1) / coalesce(p_pools, 2) as size) s
$$;

-- 预计几轮、多少分钟：每轮按场地数分几批，每批 21 分 15 分钟、15 分 10 分钟、11 分 7 分钟（三局两胜乘 2.5）；分组循环加上淘汰赛
create function public.match_preview(p_format text, p_players int, p_courts int, p_points int, p_best_of int,
                                     p_doubles boolean default false, p_pools int default null, p_advance int default null,
                                     p_rounds int default null)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('full_rounds', p.full_rounds, 'rounds', r.rounds + k.rounds,
                            'minutes', ceil((r.rounds * ceil(p.per_round::numeric / greatest(p_courts, 1)) + k.batches)
                                            * case p_points when 21 then 15 when 15 then 10 else 7 end
                                            * case when p_best_of = 3 then 2.5 else 1 end))
  from public.match_plan(p_format, p_players, p_doubles, p_pools) p,
       lateral (select greatest(case when p_format = 'groups' then p.full_rounds else least(p.full_rounds, coalesce(p_rounds, p.full_rounds)) end, 0) as rounds) r,
       lateral (select case when p_format <> 'groups' then 0 when coalesce(p_pools, 2) * coalesce(p_advance, 1) = 2 then 1 else 2 end as rounds,
                       case when p_format <> 'groups' then 0 when coalesce(p_pools, 2) * coalesce(p_advance, 1) = 2 then 1
                            else ceil(2.0 / greatest(p_courts, 1)) + 1 end as batches) k
$$;

-- 循环赛的对阵（单打循环、双打固定搭档、分组循环的小组赛）：每组按种子排好，圆桌法排 rounds 轮；单数时每轮一个人（一队）轮空
create function public.match_schedule_rr(p_match uuid)
returns void language sql security definer set search_path = '' as $$
  with e as (
    select x.*, (row_number() over (partition by coalesce(x.pool, 0) order by x.seed) - 1)::int as idx
    from public.match_entries(p_match) x
  ), pools as (
    select coalesce(pool, 0) as pool, (count(*) + count(*) % 2)::int as m from e group by coalesce(pool, 0)
  )
  insert into public.match_games (match_id, round, seq, pool, side_a, side_b)
  select p_match, r + 1, row_number() over (partition by r order by ps.pool, pr.a), nullif(ps.pool, 0), a.members, b.members
  from pools ps
  cross join lateral generate_series(0, least(ps.m - 2, (select rounds from public.matches where id = p_match) - 1)) r
  cross join lateral public.round_robin_pairs(ps.m, r) pr
  join e a on coalesce(a.pool, 0) = ps.pool and a.idx = pr.a
  join e b on coalesce(b.pool, 0) = ps.pool and b.idx = pr.b
$$;

-- 双打轮换搭档：从第 p_from 轮排到最后一轮（开始时排全部；有人退出、加入后重排没开始的轮次）。
-- 每轮：人数不是 4 的倍数时，轮空最少的人轮空（一样多的按轮次错开）；
-- 剩下的人配搭档：先给“还没搭过的人”最少的人配，挑搭过最少的；再把两队配成一场，挑交手最少的。每轮 O(n²)
create function public.match_schedule_rotating(p_match uuid, p_from int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  ids uuid[];
  n int;
  partners int[];
  rivals int[];
  played int[];
  g record;
  ia int;
  ib int;
  un int[];
  fresh int[];
  pairs int[];
  a int;
  q int;
  best int;
  best_key int;
  key int;
  t int;
  game_no int;
  r0 int;
begin
  select * into m from public.matches where id = p_match;
  delete from public.match_games where match_id = p_match and status = 'queued' and round >= p_from;
  select array_agg(id order by seq) into ids from public.match_players where match_id = p_match and withdrawn_at is null;
  n := coalesce(cardinality(ids), 0);
  if n < 4 then return; end if;
  partners := array_fill(0, array[n * n]);
  rivals := array_fill(0, array[n * n]);
  played := array_fill(0, array[n]);
  -- 以前的轮次：谁和谁搭过、交过手，每人打了几场（轮空 = 轮数 - 打的场数）
  for g in select side_a, side_b from public.match_games where match_id = p_match and status <> 'cancelled' and round < p_from loop
    for x in 1..2 loop
      ia := array_position(ids, case when x = 1 then g.side_a[1] else g.side_b[1] end);
      ib := array_position(ids, case when x = 1 then g.side_a[2] else g.side_b[2] end);
      if ia is not null then played[ia] := played[ia] + 1; end if;
      if ib is not null then played[ib] := played[ib] + 1; end if;
      if ia is not null and ib is not null then
        partners[(ia - 1) * n + ib] := partners[(ia - 1) * n + ib] + 1;
        partners[(ib - 1) * n + ia] := partners[(ib - 1) * n + ia] + 1;
      end if;
    end loop;
    foreach ia in array array[array_position(ids, g.side_a[1]), array_position(ids, g.side_a[2])] loop
      foreach ib in array array[array_position(ids, g.side_b[1]), array_position(ids, g.side_b[2])] loop
        if ia is not null and ib is not null then
          rivals[(ia - 1) * n + ib] := rivals[(ia - 1) * n + ib] + 1;
          rivals[(ib - 1) * n + ia] := rivals[(ib - 1) * n + ia] + 1;
        end if;
      end loop;
    end loop;
  end loop;

  for r in p_from..m.rounds loop
    r0 := r - 1;
    -- 轮空：轮空过的次数 = 已经过去的轮数 - 打的场数
    select coalesce(array_agg(i order by (r0 - played[i]), ((i - 1 - r0 * (n % 4)) % n + n) % n), '{}') into un
      from generate_series(1, n) i;
    un := un[n % 4 + 1:n];
    un := array(select x from unnest(un) x order by x);
    -- 配搭档
    fresh := array_fill(0, array[n]);
    foreach a in array un loop
      fresh[a] := (select count(*) from unnest(un) y where y <> a and partners[(a - 1) * n + y] = 0);
    end loop;
    pairs := '{}';
    while cardinality(un) > 0 loop
      best := null;
      foreach a in array un loop
        key := fresh[a] * 100 + ((a - 1 + r0) % n);
        if best is null or key < best_key then best := a; best_key := key; end if;
      end loop;
      a := best;
      un := array_remove(un, a);
      foreach q in array un loop
        if partners[(a - 1) * n + q] = 0 then fresh[q] := fresh[q] - 1; end if;
      end loop;
      best := null;
      foreach q in array un loop
        key := partners[(a - 1) * n + q] * 10000 + fresh[q] * 100 + ((q - a + r0) % n + n) % n;
        if best is null or key < best_key then best := q; best_key := key; end if;
      end loop;
      q := best;
      un := array_remove(un, q);
      foreach t in array un loop
        if partners[(q - 1) * n + t] = 0 then fresh[t] := fresh[t] - 1; end if;
      end loop;
      pairs := pairs || array[a, q];
      partners[(a - 1) * n + q] := partners[(a - 1) * n + q] + 1;
      partners[(q - 1) * n + a] := partners[(q - 1) * n + a] + 1;
      played[a] := played[a] + 1;
      played[q] := played[q] + 1;
    end loop;
    -- 两队配成一场：第一队挑交手最少的另一队
    game_no := 0;
    while cardinality(pairs) > 0 loop
      best := null;
      t := 3;
      while t < cardinality(pairs) loop
        key := rivals[(pairs[1] - 1) * n + pairs[t]] + rivals[(pairs[1] - 1) * n + pairs[t + 1]]
             + rivals[(pairs[2] - 1) * n + pairs[t]] + rivals[(pairs[2] - 1) * n + pairs[t + 1]];
        if best is null or key < best_key then best := t; best_key := key; end if;
        t := t + 2;
      end loop;
      game_no := game_no + 1;
      insert into public.match_games (match_id, round, seq, side_a, side_b)
        values (p_match, r, game_no, array[ids[pairs[1]], ids[pairs[2]]], array[ids[pairs[best]], ids[pairs[best + 1]]]);
      foreach ia in array pairs[1:2] loop
        foreach ib in array pairs[best:best + 1] loop
          rivals[(ia - 1) * n + ib] := rivals[(ia - 1) * n + ib] + 1;
          rivals[(ib - 1) * n + ia] := rivals[(ib - 1) * n + ia] + 1;
        end loop;
      end loop;
      pairs := pairs[3:best - 1] || pairs[best + 2:cardinality(pairs)];
    end loop;
  end loop;
end
$$;

-- 分组循环的淘汰赛：小组赛打完后，每组前 advance 名（3 组时加一个成绩最好的第 2 名）出线。
-- 2 个人直接打决赛；4 个人打半决赛（1 号种子打 4 号，同组的错开）。出线卡在并列上时标出来，组织者可以改
create function public.match_knockout(p_match uuid, p_seeds text[] default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  table_pool jsonb := public.match_standings(p_match);
  seeds jsonb[];
  round_no int := (select coalesce(max(round), 0) + 1 from public.match_games where match_id = p_match and stage = 'pool');
  cut_tie boolean := false;
  rival int := 4;
begin
  select * into m from public.matches where id = p_match;
  -- 每组的第几名：rank 并列时按积分榜的顺序
  with placed as (
    select e, row_number() over (partition by e ->> 'pool' order by ord) as place
    from jsonb_array_elements(table_pool) with ordinality x(e, ord)
    where not (e ->> 'withdrawn')::boolean
  ), picked as (
    select e, place from placed where place <= m.advance
    union all
    -- 3 组时：第 2 名里成绩最好的一个
    (select e, place from placed where m.pools = 3 and m.advance = 1 and place = 2
     order by (e ->> 'rate')::numeric desc nulls last, (e ->> 'diff')::int desc, (e ->> 'pf')::int desc limit 1)
  )
  select array_agg(e order by place, (e ->> 'rate')::numeric desc nulls last, (e ->> 'diff')::int desc, (e ->> 'pf')::int desc)
    into seeds from picked;
  if p_seeds is not null then
    seeds := array(select e from unnest(p_seeds) with ordinality s(key, i) join jsonb_array_elements(table_pool) e on e ->> 'key' = s.key
                   order by s.i);
    if cardinality(seeds) <> cardinality(p_seeds) or cardinality(seeds) not in (2, 4) then
      raise exception 'invalid_qualifiers' using errcode = '22023';
    end if;
  else
    -- 出线的最后一名和没出线的第一名并列
    cut_tie := exists (
      select 1 from jsonb_array_elements(table_pool) x join jsonb_array_elements(table_pool) y
        on x ->> 'pool' = y ->> 'pool' and x ->> 'rank' = y ->> 'rank' and x ->> 'key' <> y ->> 'key'
      where x ->> 'key' = any(array(select s ->> 'key' from unnest(seeds) s))
        and not y ->> 'key' = any(array(select s ->> 'key' from unnest(seeds) s)) and not (y ->> 'withdrawn')::boolean);
  end if;
  if coalesce(cardinality(seeds), 0) < 2 then return; end if;
  update public.matches set tie_at_cut = cut_tie where id = p_match;
  if cardinality(seeds) = 2 then
    insert into public.match_games (match_id, round, seq, stage, side_a, side_b)
      values (p_match, round_no, 1, 'final', array(select jsonb_array_elements_text(seeds[1] -> 'members')::uuid),
              array(select jsonb_array_elements_text(seeds[2] -> 'members')::uuid));
  else
    if seeds[1] ->> 'pool' = seeds[4] ->> 'pool' then rival := 3; end if;
    insert into public.match_games (match_id, round, seq, stage, side_a, side_b)
      select p_match, round_no, x.n, 'semi', array(select jsonb_array_elements_text(seeds[x.hi] -> 'members')::uuid),
             array(select jsonb_array_elements_text(seeds[x.lo] -> 'members')::uuid)
      from (values (1, 1, rival), (2, 2, 7 - rival)) x(n, hi, lo);
  end if;
end
$$;

-- 空着的场地排上下一场：按轮次和顺序，有人还在别的场地上打就先上后面的。
-- 从“当晚”开的比赛，排场还没打完的场地先空着。上场的注册球员收一条推送（同一场比赛的互相替换）
create function public.match_fill(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  busy smallint[];
  playing uuid[];
  g record;
  names jsonb;
  player record;
begin
  select * into m from public.matches where id = p_match for update;
  if m.status <> 'live' then return; end if;
  select coalesce(array_agg(court), '{}'), coalesce(array_agg(x), '{}') into busy, playing
    from (select court, unnest(side_a || side_b) as x from public.match_games where match_id = p_match and status = 'playing') b;
  if m.session_id is not null then
    busy := busy || array(select court from public.night_games where session_id = m.session_id and ended_at is null);
  end if;
  select jsonb_object_agg(id, name) into names from public.match_players where match_id = p_match;
  for c in 1..m.courts loop
    continue when c = any(busy);
    select * into g from public.match_games
      where match_id = p_match and status = 'queued' and not (side_a || side_b) && playing order by round, seq limit 1;
    exit when g.id is null;
    update public.match_games set status = 'playing', court = c, started_at = now() where id = g.id;
    playing := playing || g.side_a || g.side_b;
    for player in
      select mp.user_id, mp.id = any(g.side_a) as on_a from public.match_players mp
      where mp.id = any(g.side_a || g.side_b) and mp.user_id is not null and mp.withdrawn_at is null
    loop
      perform public.live_push(player.user_id, 'Your game: Court {court}',
        case when cardinality(g.side_a) = 1 then 'Against {a}.' else 'Against {a} and {b}.' end,
        '/app/matches/' || p_match || '/', 'match:' || p_match,
        jsonb_build_object('court', c,
          'a', names ->> (case when player.on_a then g.side_b else g.side_a end)[1]::text,
          'b', names ->> (case when player.on_a then g.side_b else g.side_a end)[2]::text));
    end loop;
  end loop;
end
$$;

-- 比赛结束：没打的写“没打”，每个参赛的注册用户收到自己的名次
create function public.match_close(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  e jsonb;
  player uuid;
begin
  update public.matches set status = 'done', ended_at = now() where id = p_match and status = 'live' returning * into m;
  if m.id is null then return; end if;
  update public.match_games set status = 'skipped', court = null where match_id = p_match and status in ('queued', 'playing');
  for e in select * from jsonb_array_elements(public.match_ranking(p_match)) loop
    for player in select mp.user_id from public.match_players mp
                  where mp.id in (select jsonb_array_elements_text(e -> 'members')::uuid) and mp.user_id is not null and mp.withdrawn_at is null loop
      perform public.notify(player, 'match', 'Match over: you placed #{rank}', 'Open it to see the final standings.',
        '/app/matches/' || p_match || '/', jsonb_build_object('rank', e ->> 'rank', 'match', m.name));
    end loop;
  end loop;
end
$$;

-- 每次比分、退赛之后：分组循环的小组赛打完就排淘汰赛，半决赛打完排决赛；空场地排上人；都打完了就结束
create function public.match_progress(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
begin
  select * into m from public.matches where id = p_match;
  if m.status <> 'live' then return; end if;
  if m.format = 'groups' and not exists (select 1 from public.match_games where match_id = p_match and status in ('queued', 'playing')) then
    if not exists (select 1 from public.match_games where match_id = p_match and stage <> 'pool') then
      perform public.match_knockout(p_match);
    elsif not exists (select 1 from public.match_games where match_id = p_match and stage = 'final') then
      insert into public.match_games (match_id, round, seq, stage, side_a, side_b)
        select p_match, max(round) + 1, 1, 'final',
               (select case when winner = 1 then side_a else side_b end from public.match_games
                where match_id = p_match and stage = 'semi' order by seq limit 1),
               (select case when winner = 1 then side_a else side_b end from public.match_games
                where match_id = p_match and stage = 'semi' order by seq offset 1 limit 1)
        from public.match_games where match_id = p_match and stage = 'semi' and status = 'done'
        having count(*) = 2;
    end if;
  end if;
  perform public.match_fill(p_match);
  if not exists (select 1 from public.match_games where match_id = p_match and status in ('queued', 'playing')) then
    perform public.match_close(p_match);
  end if;
end
$$;

-- 改比赛前的检查：返回我的角色（organizer / helper），不够的报错
create function public.match_guard(p_match uuid, p_organizer_only boolean default false)
returns text language plpgsql stable security definer set search_path = '' as $$
declare
  role text := public.match_role(p_match);
begin
  if role is null or role = 'player' or (p_organizer_only and role <> 'organizer') then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  return role;
end
$$;

revoke execute on function public.match_role(uuid), public.match_entries(uuid), public.match_standings(uuid, boolean),
  public.match_ranking(uuid), public.match_schedule_rr(uuid), public.match_schedule_rotating(uuid, int),
  public.match_knockout(uuid, text[]), public.match_fill(uuid), public.match_close(uuid), public.match_progress(uuid),
  public.match_guard(uuid, boolean) from public, anon, authenticated;
grant execute on function public.match_preview(text, int, int, int, int, boolean, int, int, int) to anon, authenticated;

-- 比赛页的数据（组织者、帮手、参赛的人和公开看板共用）。p_full：加上比分的版本号、谁填的、谁点了“不对”
create function public.match_view(p_match uuid, p_full boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'kind', 'match', 'id', m.id, 'name', m.name, 'format', m.format, 'doubles', m.doubles, 'points', m.points, 'best_of', m.best_of,
    'win_by_two', m.win_by_two, 'courts', m.courts, 'rounds', m.rounds, 'pools', m.pools, 'advance', m.advance, 'status', m.status,
    'created_at', m.created_at, 'ended_at', m.ended_at, 'board_code', m.board_code, 'session_id', m.session_id,
    'venue', (select v.name from public.venues v where v.id = m.venue_id), 'tie_at_cut', m.tie_at_cut,
    'round', coalesce((select min(round) from public.match_games where match_id = m.id and status in ('queued', 'playing')),
                      (select max(round) from public.match_games where match_id = m.id)),
    'players', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'team', p.team, 'pool', p.pool,
                                                             'withdrawn', p.withdrawn_at is not null) order by p.seq), '[]')
                from public.match_players p where p.match_id = m.id),
    'games', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                'id', g.id, 'round', g.round, 'stage', g.stage, 'pool', g.pool, 'a', g.side_a, 'b', g.side_b, 'court', g.court,
                'status', g.status, 'scores', g.scores, 'winner', g.winner, 'walkover', nullif(g.walkover, false),
                'version', case when p_full then g.version end,
                'scored_by', case when p_full then (select nickname from public.profiles where id = g.scored_by) end,
                'edited_by', case when p_full then (select nickname from public.profiles where id = g.edited_by) end,
                'flagged', case when p_full and g.flagged then true end)) order by g.round, g.seq), '[]')
              from public.match_games g where g.match_id = m.id),
    'standings', public.match_standings(m.id),
    'ranking', case when m.status = 'done' then public.match_ranking(m.id) end)
  from public.matches m where m.id = p_match
$$;

-- 新建一场比赛。p_players：[{user_id} | {signup_id}（从“当晚”开的）| {name}（访客），双打固定搭档可以带 team]，按顺序是种子。
-- 没给搭档的按实力自动配（最强配最弱）；分组循环按实力蛇形分组。开始后参赛的注册用户收到通知
create function public.create_match(p_name text, p_venue text, p_courts int, p_format text, p_points int, p_best_of int,
                                    p_win_by_two boolean, p_players jsonb, p_rounds int default null, p_pools int default null,
                                    p_advance int default null, p_doubles boolean default false, p_session uuid default null,
                                    p_helpers uuid[] default '{}')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  clean_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  teams boolean := p_format = 'fixed' or (p_format = 'groups' and coalesce(p_doubles, false));
  n int := coalesce(jsonb_array_length(case when jsonb_typeof(p_players) = 'array' then p_players end), 0);
  plan record;
  new_match uuid;
  item jsonb;
  k int := 0;
  v_user uuid;
  v_signup uuid;
  v_name text;
  v_rating numeric;
  player record;
begin
  if me is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  if char_length(clean_name) not between 1 and 40 then raise exception 'invalid_match_name' using errcode = '22023'; end if;
  if public.has_offensive(clean_name) then raise exception 'objectionable_content' using errcode = '22023'; end if;
  if p_format is null or p_format not in ('singles', 'fixed', 'rotating', 'groups') or p_points is null or p_points not in (11, 15, 21)
     or p_best_of is null or p_best_of not in (1, 3) or p_courts is null or p_courts not between 1 and 12
     or (p_format = 'groups' and (p_pools is null or p_pools not between 2 and 4 or coalesce(p_advance, 1) not in (1, 2)
                                  or (p_advance = 2 and p_pools <> 2))) then
    raise exception 'invalid_match' using errcode = '22023';
  end if;
  if n not between 2 and 64 or (teams and n % 2 = 1)
     or (p_format in ('fixed', 'rotating') and n < 4) or (p_format = 'groups' and (case when teams then n / 2 else n end) < p_pools * 2) then
    raise exception 'invalid_player_count' using errcode = '22023';
  end if;
  if p_venue is not null and not exists (select 1 from public.venues where id = p_venue) then
    raise exception 'venue_not_found' using errcode = 'P0002';
  end if;
  if p_session is not null then
    perform public.night_guard(p_session);
    if exists (select 1 from public.club_nights c join public.matches m on m.id = c.match_id where c.session_id = p_session and m.status = 'live') then
      raise exception 'match_running' using errcode = '22023';
    end if;
  end if;

  select * into plan from public.match_plan(p_format, n, teams, p_pools);
  insert into public.matches (owner_id, session_id, name, venue_id, courts, format, doubles, points, best_of, win_by_two, rounds, pools, advance)
    values (me, p_session, clean_name, p_venue, p_courts, p_format, teams, p_points, p_best_of, coalesce(p_win_by_two, true),
            greatest(case when p_format = 'groups' then plan.full_rounds else least(plan.full_rounds, coalesce(p_rounds, plan.full_rounds)) end, 1),
            case when p_format = 'groups' then p_pools end, case when p_format = 'groups' then coalesce(p_advance, 1) end)
    returning id into new_match;

  for item in select * from jsonb_array_elements(p_players) loop
    k := k + 1;
    v_user := null; v_signup := null; v_rating := null;
    if item ? 'signup_id' and p_session is not null then
      select p.id, p.user_id, p.name, p.rating into v_signup, v_user, v_name, v_rating
        from public.night_people(p_session) p where p.id = (item ->> 'signup_id')::uuid;
      if v_signup is null then raise exception 'player_not_found' using errcode = 'P0002'; end if;
    elsif item ? 'user_id' then
      select p.id, p.nickname, p.rating into v_user, v_name, v_rating from public.profiles p where p.id = (item ->> 'user_id')::uuid;
      -- 屏蔽了你的人选不到；只能选球友、球群里的人、这一晚到场的人
      if v_user is null or public.blocked_between(me, v_user)
         or not (public.related(me, v_user) or exists (select 1 from public.session_signups where session_id = p_session and user_id = v_user)) then
        raise exception 'player_not_found' using errcode = 'P0002';
      end if;
    else
      v_name := public.clean_player_name(item ->> 'name');
    end if;
    if v_user is not null and exists (select 1 from public.match_players where match_id = new_match and user_id = v_user) then
      raise exception 'duplicate_player' using errcode = '22023';
    end if;
    -- 同名的加数字
    if exists (select 1 from public.match_players where match_id = new_match and lower(name) = lower(v_name)) then
      v_name := left(v_name, 20) || ' ' || (select count(*) + 1 from public.match_players where match_id = new_match and lower(name) like lower(v_name) || '%');
    end if;
    insert into public.match_players (match_id, user_id, signup_id, name, rating, seq, team)
      values (new_match, v_user, v_signup, left(v_name, 24), v_rating, k, case when teams then (item ->> 'team')::smallint end);
  end loop;

  if teams then
    -- 搭档要么都给（每队正好两人），要么都不给（按实力配：最强配最弱）
    if exists (select 1 from public.match_players where match_id = new_match and team is null) then
      update public.match_players mp set team = case when x.rk < n / 2 then x.rk + 1 else n - x.rk end
        from (select id, (row_number() over (order by coalesce(rating, 3) desc, seq) - 1)::int as rk
              from public.match_players where match_id = new_match) x
        where mp.id = x.id;
    elsif exists (select 1 from public.match_players where match_id = new_match group by team having count(*) <> 2) then
      raise exception 'invalid_teams' using errcode = '22023';
    end if;
  end if;
  if p_format = 'groups' then
    -- 蛇形分组：第 1、4、5、8… 强进第 1 组
    update public.match_players mp set pool = case when (e.i / p_pools) % 2 = 0 then e.i % p_pools + 1 else p_pools - e.i % p_pools end
      from (select members, (row_number() over (order by rating desc, seed) - 1)::int as i from public.match_entries(new_match)) e
      where mp.id = any(e.members);
  end if;

  if p_format = 'rotating' then perform public.match_schedule_rotating(new_match, 1);
  else perform public.match_schedule_rr(new_match);
  end if;

  if cardinality(coalesce(p_helpers, '{}')) > 0 then perform public.match_helpers(new_match, p_helpers); end if;
  if p_session is not null then
    insert into public.club_nights (session_id, match_id) values (p_session, new_match)
      on conflict (session_id) do update set match_id = excluded.match_id;
  end if;

  for player in
    select mp.user_id, min(g.round) as first_round from public.match_players mp
    left join public.match_games g on g.match_id = new_match and mp.id = any(g.side_a || g.side_b)
    where mp.match_id = new_match and mp.user_id is not null and mp.user_id <> me group by mp.user_id
  loop
    perform public.notify(player.user_id, 'match', 'Match started: {match}', 'Your first game is in round {round}.',
      '/app/matches/' || new_match || '/', jsonb_build_object('match', clean_name, 'round', coalesce(player.first_round, 1)));
  end loop;
  perform public.match_fill(new_match);
  return new_match;
end
$$;

-- 比赛页（组织者、帮手、参赛的注册用户）
create function public.match_state(p_match uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  role text := public.match_role(p_match);
begin
  if role is null then return null; end if;
  return public.match_view(p_match, role <> 'player') || (
    select jsonb_build_object(
      'role', role,
      'me', (select id from public.match_players where match_id = m.id and user_id = auth.uid()),
      'helpers', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname)), '[]')
                  from public.profiles p where p.id = any(m.helpers)),
      'undo_until', case when m.undo_until > now() and role <> 'player' then m.undo_until end)
    from public.matches m where m.id = p_match);
end
$$;

-- 输比分。组织者和帮手随时能输、能改（带上看到的版本，两个人同时改后到的报 score_changed），不合规则时可以坚持（p_force）；
-- 这一场的注册球员只能在打的时候输一次，先存的算，已经有比分了报 score_taken
create function public.match_score(p_game bigint, p_scores int[], p_version int, p_force boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.match_games;
  m public.matches;
  role text;
  win smallint;
  last_id bigint;
  playing bigint[];
begin
  select * into g from public.match_games where id = p_game;
  if g.id is null then raise exception 'game_not_found' using errcode = 'P0002'; end if;
  select * into m from public.matches where id = g.match_id for update;
  select * into g from public.match_games where id = p_game;
  role := public.match_role(m.id);
  if role in ('organizer', 'helper') then
    if g.version is distinct from p_version then raise exception 'score_changed' using errcode = '40001'; end if;
    if g.status = 'cancelled' then raise exception 'game_cancelled' using errcode = '22023'; end if;
  elsif exists (select 1 from public.match_players where match_id = m.id and user_id = auth.uid() and withdrawn_at is null
                and id = any(g.side_a || g.side_b)) then
    if g.status = 'done' then raise exception 'score_taken' using errcode = '40001'; end if;
    if g.status <> 'playing' then raise exception 'not_allowed' using errcode = '42501'; end if;
    p_force := false;
  else
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_scores is null or cardinality(p_scores) not between 2 and 6 or exists (select 1 from unnest(p_scores) x where x is null or x not between 0 and 99) then
    raise exception 'score_invalid' using errcode = '22023';
  end if;
  win := public.score_winner(p_scores, m.points, m.best_of, m.win_by_two);
  if win is null and p_force then win := public.loose_winner(p_scores); end if;
  if win is null then raise exception 'score_invalid' using errcode = '22023'; end if;

  select coalesce(max(id), 0) into last_id from public.match_games where match_id = m.id;
  select coalesce(array_agg(id), '{}') into playing from public.match_games where match_id = m.id and status = 'playing';
  update public.match_games
    set scores = p_scores::smallint[], winner = win, status = 'done', walkover = false, version = version + 1,
        scored_by = coalesce(scored_by, auth.uid()), edited_by = case when g.status = 'done' then auth.uid() end,
        flagged = flagged and role not in ('organizer', 'helper')
    where id = p_game;
  perform public.match_progress(m.id);
  update public.matches
    set undo = jsonb_build_object('game', to_jsonb(g), 'created', (select coalesce(jsonb_agg(id), '[]') from public.match_games where match_id = m.id and id > last_id),
                                  'started', (select coalesce(jsonb_agg(id), '[]') from public.match_games
                                              where match_id = m.id and status = 'playing' and id <> all(playing)),
                                  'closed', m.status = 'live' and status = 'done'),
        undo_until = now() + interval '10 seconds'
    where id = m.id;
end
$$;

-- 撤销最后一次输比分（10 秒内）：比分回到原来的样子，因为它排上的场次、淘汰赛、结束都撤掉
create function public.match_undo(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  prev public.match_games;
begin
  perform public.match_guard(p_match);
  select * into m from public.matches where id = p_match for update;
  if m.undo is null or m.undo_until < now() then raise exception 'nothing_to_undo' using errcode = 'P0002'; end if;
  prev := jsonb_populate_record(null::public.match_games, m.undo -> 'game');
  update public.match_games set status = 'queued', court = null, started_at = null
    where match_id = p_match and status = 'playing' and id in (select jsonb_array_elements_text(m.undo -> 'started')::bigint);
  delete from public.match_games
    where match_id = p_match and status = 'queued' and id in (select jsonb_array_elements_text(m.undo -> 'created')::bigint);
  update public.match_games
    set scores = prev.scores, winner = prev.winner, status = prev.status, walkover = prev.walkover, court = prev.court,
        started_at = prev.started_at, scored_by = prev.scored_by, edited_by = prev.edited_by, flagged = prev.flagged, version = version + 1
    where id = prev.id;
  update public.matches set undo = null, undo_until = null,
         status = case when (m.undo ->> 'closed')::boolean then 'live' else status end,
         ended_at = case when (m.undo ->> 'closed')::boolean then null else ended_at end
    where id = p_match;
  perform public.match_fill(p_match);
end
$$;

-- 球员点“不对”：只是在组织者那边标出来
create function public.match_flag(p_game bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.match_games g set flagged = true
    where g.id = p_game and g.status = 'done'
      and exists (select 1 from public.match_players p where p.match_id = g.match_id and p.user_id = auth.uid() and p.id = any(g.side_a || g.side_b));
  if not found then raise exception 'not_allowed' using errcode = '42501'; end if;
end
$$;

-- 退赛（受伤或走了）：p_game 给了就这一场算对方赢；没打的场次默认取消，p_forfeit 算对方赢。
-- 固定搭档整队退出；轮换搭档这一轮取消，后面的轮次重排
create function public.match_withdraw(p_player uuid, p_game bigint default null, p_forfeit boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  members uuid[];
  current_round int;
begin
  select m2.* into m from public.matches m2 join public.match_players p on p.match_id = m2.id where p.id = p_player;
  if m.id is null then raise exception 'player_not_found' using errcode = 'P0002'; end if;
  perform public.match_guard(m.id);
  perform 1 from public.matches where id = m.id for update;
  select array_agg(p.id) into members from public.match_players p join public.match_players me on me.id = p_player
    where p.match_id = m.id and (p.id = p_player or (m.doubles and p.team = me.team));
  update public.match_players set withdrawn_at = coalesce(withdrawn_at, now()) where id = any(members);
  if p_game is not null then
    update public.match_games set status = 'done', walkover = true, scores = null, winner = case when side_a && members then 2 else 1 end,
                                  version = version + 1
      where id = p_game and match_id = m.id and (side_a || side_b) && members and status in ('queued', 'playing');
  end if;
  if m.format = 'rotating' then
    select max(round) into current_round from public.match_games where match_id = m.id and status in ('playing', 'done');
    update public.match_games set status = 'cancelled', court = null
      where match_id = m.id and status in ('queued', 'playing') and (side_a || side_b) && members and round <= coalesce(current_round, 0);
    perform public.match_schedule_rotating(m.id, coalesce(current_round, 0) + 1);
  else
    update public.match_games
      set status = case when p_forfeit then 'done' else 'cancelled' end, walkover = coalesce(p_forfeit, false), court = null,
          winner = case when p_forfeit then case when side_a && members then 2 else 1 end end, version = version + 1
      where match_id = m.id and status in ('queued', 'playing') and (side_a || side_b) && members;
  end if;
  perform public.match_progress(m.id);
end
$$;

-- 中途加人：只有双打轮换搭档能加，从下一轮开始排
create function public.match_add_player(p_match uuid, p_user uuid default null, p_name text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  v_name text;
  v_rating numeric;
  added uuid;
  current_round int;
begin
  perform public.match_guard(p_match);
  select * into m from public.matches where id = p_match for update;
  if m.format <> 'rotating' or m.status <> 'live' then raise exception 'cannot_add_player' using errcode = '22023'; end if;
  if p_user is not null then
    select nickname, rating into v_name, v_rating from public.profiles where id = p_user;
    if v_name is null or public.blocked_between(auth.uid(), p_user) or not public.related(auth.uid(), p_user) then
      raise exception 'player_not_found' using errcode = 'P0002';
    end if;
    if exists (select 1 from public.match_players where match_id = p_match and user_id = p_user) then
      raise exception 'duplicate_player' using errcode = '22023';
    end if;
  else
    v_name := public.clean_player_name(p_name);
  end if;
  if exists (select 1 from public.match_players where match_id = p_match and lower(name) = lower(v_name)) then
    v_name := left(v_name, 20) || ' ' || (select count(*) + 1 from public.match_players where match_id = p_match and lower(name) like lower(v_name) || '%');
  end if;
  if (select count(*) from public.match_players where match_id = p_match) >= 64 then
    raise exception 'invalid_player_count' using errcode = '22023';
  end if;
  insert into public.match_players (match_id, user_id, name, rating, seq)
    values (p_match, p_user, left(v_name, 24), v_rating, (select max(seq) + 1 from public.match_players where match_id = p_match))
    returning id into added;
  select max(round) into current_round from public.match_games where match_id = p_match and status in ('playing', 'done');
  perform public.match_schedule_rotating(p_match, coalesce(current_round, 0) + 1);
  if p_user is not null then
    perform public.notify(p_user, 'match', 'Match started: {match}', 'Your first game is in round {round}.', '/app/matches/' || p_match || '/',
      jsonb_build_object('match', m.name, 'round', coalesce((select min(round) from public.match_games where match_id = p_match
                                                             and added = any(side_a || side_b)), current_round + 1)));
  end if;
  perform public.match_fill(p_match);
  return added;
end
$$;

-- 改场地数（随时；减少时正在打的打完再收）
create function public.match_courts(p_match uuid, p_courts int)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.match_guard(p_match);
  if p_courts not between 1 and 12 then raise exception 'invalid_courts' using errcode = '22023'; end if;
  update public.matches set courts = p_courts where id = p_match;
  perform public.match_fill(p_match);
end
$$;

-- 提前结束（组织者）：没打的写“没打”，按已经打的排名
create function public.match_end(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.match_guard(p_match, true);
  perform public.match_close(p_match);
end
$$;

-- 删掉（组织者）：还在打的，参赛的注册用户收到“比赛取消了”
create function public.match_delete(p_match uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  player uuid;
begin
  perform public.match_guard(p_match, true);
  select * into m from public.matches where id = p_match;
  if m.status = 'live' then
    for player in select user_id from public.match_players where match_id = p_match and user_id is not null and user_id <> auth.uid() loop
      perform public.notify(player, 'match', 'Match cancelled: {match}', '{name} deleted this match.', null,
        jsonb_build_object('match', m.name, 'name', (select nickname from public.profiles where id = auth.uid())));
    end loop;
  end if;
  delete from public.matches where id = p_match;
end
$$;

-- 帮手（记分员）：最多 3 个球友。新点的人收到通知
create function public.match_helpers(p_match uuid, p_users uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  helper uuid;
begin
  perform public.match_guard(p_match, true);
  p_users := array(select distinct x from unnest(coalesce(p_users, '{}')) x);
  if cardinality(p_users) > 3 then raise exception 'too_many_helpers' using errcode = '22023'; end if;
  select * into m from public.matches where id = p_match for update;
  foreach helper in array p_users loop
    if public.blocked_between(auth.uid(), helper) or not public.related(auth.uid(), helper) then
      raise exception 'player_not_found' using errcode = 'P0002';
    end if;
  end loop;
  update public.matches set helpers = p_users where id = p_match;
  foreach helper in array p_users loop
    continue when helper = any(m.helpers) or helper = auth.uid();
    perform public.notify(helper, 'match', '{name} asked you to keep score', '{match}. You can enter scores.', '/app/matches/' || p_match || '/',
      jsonb_build_object('match', m.name, 'name', (select nickname from public.profiles where id = auth.uid())));
  end loop;
end
$$;

-- 出线卡在并列上时，组织者点选谁出线（p_keys 按种子顺序，2 个或 4 个）；淘汰赛还没开始才能改
create function public.match_qualify(p_match uuid, p_keys text[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.match_guard(p_match, true);
  perform 1 from public.matches where id = p_match and format = 'groups' and status = 'live' for update;
  if not found or exists (select 1 from public.match_games where match_id = p_match and stage <> 'pool' and status <> 'queued') then
    raise exception 'knockout_started' using errcode = '22023';
  end if;
  delete from public.match_games where match_id = p_match and stage <> 'pool';
  perform public.match_knockout(p_match, p_keys);
  perform public.match_fill(p_match);
end
$$;

-- 我的 → 比赛：建的、帮忙的、参加过的，新的在前（最近 50 场）
create function public.my_matches()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', m.name, 'format', m.format, 'status', m.status, 'created_at', m.created_at, 'ended_at', m.ended_at,
      'players', (select count(*) from public.match_players p where p.match_id = m.id),
      'rank', case when m.status = 'done' then (
        select (e ->> 'rank')::int from jsonb_array_elements(public.match_ranking(m.id)) e
        where exists (select 1 from public.match_players p where p.match_id = m.id and p.user_id = auth.uid()
                      and (e -> 'members') ? p.id::text)) end)
    order by m.created_at desc), '[]')
  from (select * from public.matches m
        where m.owner_id = auth.uid() or auth.uid() = any(m.helpers)
           or exists (select 1 from public.match_players p where p.match_id = m.id and p.user_id = auth.uid())
        order by m.created_at desc limit 50) m
$$;

revoke execute on function public.match_view(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.create_match(text, text, int, text, int, int, boolean, jsonb, int, int, int, boolean, uuid, uuid[]),
  public.match_state(uuid), public.match_score(bigint, int[], int, boolean), public.match_undo(uuid), public.match_flag(bigint),
  public.match_withdraw(uuid, bigint, boolean), public.match_add_player(uuid, uuid, text), public.match_courts(uuid, int),
  public.match_end(uuid), public.match_delete(uuid), public.match_helpers(uuid, uuid[]), public.match_qualify(uuid, text[]),
  public.my_matches() from public, anon;
grant execute on function public.create_match(text, text, int, text, int, int, boolean, jsonb, int, int, int, boolean, uuid, uuid[]),
  public.match_state(uuid), public.match_score(bigint, int[], int, boolean), public.match_undo(uuid), public.match_flag(bigint),
  public.match_withdraw(uuid, bigint, boolean), public.match_add_player(uuid, uuid, text), public.match_courts(uuid, int),
  public.match_end(uuid), public.match_delete(uuid), public.match_helpers(uuid, uuid[]), public.match_qualify(uuid, text[]),
  public.my_matches() to authenticated;

-- ---------------------------------------------------------------------------
-- 公开看板和球员的“今晚”
-- ---------------------------------------------------------------------------

-- 看板（不登录，/live/<码>/）：只有名字，不给头像、等级、用户 id、付款信息。
-- 排场：场上、接下来两场、每个人到没到和今晚打了几场，当晚结束 24 小时后失效；从“当晚”开的比赛一起给。
-- 比赛：对阵、积分榜，结束 7 天后失效。me：这台设备报名的凭证或登录的人对上的那一个（只用来高亮）
create function public.live_board(p_code text, p_tokens text[] default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  mine text[] := (select coalesce(array_agg(public.guest_token_hash(t)), '{}') from unnest(p_tokens[1:50]) t);
  n public.club_nights;
  s record;
  m public.matches;
  first uuid[];
  second uuid[];
begin
  if p_code is null or char_length(p_code) <> 8 then return null; end if;
  select * into n from public.club_nights where board_code = p_code;
  if n.session_id is not null then
    select gs.starts_at, gs.ends_at, g.name, v.name as venue, v.time_zone_id as tz into s
      from public.group_sessions gs join public.play_groups g on g.id = gs.group_id
      join public.venues v on v.id = coalesce(gs.venue_id, g.venue_id)
      where gs.id = n.session_id and gs.cancelled_at is null and now() < gs.ends_at + interval '24 hours';
    if s.starts_at is null then return null; end if;
    if n.started_at is not null then
      first := public.night_pick(n.session_id);
      second := public.night_pick(n.session_id, first);
    end if;
    return jsonb_build_object(
      'kind', 'night', 'group', s.name, 'venue', s.venue, 'tz', s.tz, 'starts_at', s.starts_at, 'ends_at', s.ends_at,
      'started', n.started_at is not null, 'doubles', n.doubles,
      'courts', (select coalesce(jsonb_agg(jsonb_build_object('court', g.court, 'players', g.players, 'started_at', g.started_at)
                                           order by g.court), '[]')
                 from public.night_games g where g.session_id = n.session_id and g.ended_at is null),
      'next', case when first is null then '[]'::jsonb when second is null then jsonb_build_array(first)
                   else jsonb_build_array(first, second) end,
      'people', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'status', coalesce(p.attendance, 'absent'),
                                                              'games', p.games, 'on_court', p.on_court)
                                           order by p.next_up desc, p.eff, p.queued_at nulls first, p.signed_up_at), '[]')
                 from public.night_people(n.session_id) p where not p.waitlisted or p.attendance is not null),
      'me', (select su.id from public.session_signups su where su.session_id = n.session_id
             and ((auth.uid() is not null and su.user_id = auth.uid()) or su.guest_token_hash = any(mine)) limit 1),
      'match', (select public.match_view(m2.id, false) || jsonb_build_object('me', (select mp.id from public.match_players mp
                         join public.session_signups su on su.id = mp.signup_id
                         where mp.match_id = m2.id and ((auth.uid() is not null and su.user_id = auth.uid()) or su.guest_token_hash = any(mine)) limit 1))
                from public.matches m2 where m2.id = n.match_id and m2.status = 'live'),
      'now', now());
  end if;
  select * into m from public.matches where board_code = p_code and (status = 'live' or ended_at > now() - interval '7 days');
  if m.id is null then return null; end if;
  return public.match_view(m.id, false) || jsonb_build_object(
    'me', (select mp.id from public.match_players mp left join public.session_signups su on su.id = mp.signup_id
           where mp.match_id = m.id and ((auth.uid() is not null and mp.user_id = auth.uid()) or su.guest_token_hash = any(mine)) limit 1),
    'now', now());
end
$$;

-- 球局页最上面的“今晚”卡：我今晚在排场里（到了）或者在打的比赛。
-- status：court（在场地 court 上）、next（下一场是我）、waiting（等候中）、resting（休息）
create function public.my_tonight()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  items jsonb := '[]'::jsonb;
  r record;
  first uuid[];
  g record;
begin
  if me is null then return items; end if;
  for r in
    select su.id, su.attendance, gs.id as session_id, gs.group_id, g2.name, n.board_code, n.match_id, gs.ends_at
    from public.session_signups su
    join public.group_sessions gs on gs.id = su.session_id
    join public.play_groups g2 on g2.id = gs.group_id
    join public.club_nights n on n.session_id = gs.id
    where su.user_id = me and su.attendance in ('here', 'resting') and n.started_at is not null and gs.cancelled_at is null
      and now() between gs.starts_at - interval '1 hour' and gs.ends_at + interval '1 hour'
      and not exists (select 1 from public.matches m where m.id = n.match_id and m.status = 'live')
  loop
    first := public.night_pick(r.session_id);
    items := items || (select jsonb_build_object(
      'kind', 'night', 'session_id', r.session_id, 'group_id', r.group_id, 'name', r.name, 'board_code', r.board_code,
      'status', case when p.on_court is not null then 'court' when r.attendance = 'resting' then 'resting'
                     when r.id = any(coalesce(first, '{}')) then 'next' else 'waiting' end,
      'court', p.on_court, 'games', p.games)
      from public.night_people(r.session_id) p where p.id = r.id);
  end loop;
  for r in
    select m.id, m.name, m.board_code, mp.id as player from public.matches m join public.match_players mp on mp.match_id = m.id
    where mp.user_id = me and mp.withdrawn_at is null and m.status = 'live'
  loop
    select gm.court, gm.status, gm.round into g from public.match_games gm
      where gm.match_id = r.id and gm.status in ('playing', 'queued') and r.player = any(gm.side_a || gm.side_b)
      order by gm.status = 'playing' desc, gm.round, gm.seq limit 1;
    items := items || jsonb_build_object(
      'kind', 'match', 'match_id', r.id, 'name', r.name, 'board_code', r.board_code,
      'status', case when g.status = 'playing' then 'court'
                     when (select gm.id from public.match_games gm where gm.match_id = r.id and gm.status = 'queued' order by gm.round, gm.seq limit 1)
                          = (select gm.id from public.match_games gm where gm.match_id = r.id and gm.status = 'queued'
                             and r.player = any(gm.side_a || gm.side_b) order by gm.round, gm.seq limit 1) then 'next'
                     else 'waiting' end,
      'court', g.court, 'round', g.round,
      'games', (select count(*) from public.match_games gm where gm.match_id = r.id and gm.status = 'done' and r.player = any(gm.side_a || gm.side_b)));
  end loop;
  return items;
end
$$;

revoke execute on function public.live_board(text, text[]), public.my_tonight() from public;
grant execute on function public.live_board(text, text[]) to anon, authenticated;
revoke execute on function public.my_tonight() from anon;
grant execute on function public.my_tonight() to authenticated;

-- 排场的记录留 30 天
select cron.schedule('club-nights', '37 4 * * *', $$
  delete from public.club_nights n using public.group_sessions gs
  where gs.id = n.session_id and gs.ends_at < now() - interval '30 days'$$);

-- 推送、通知和邮件的译文
insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', 'Your turn: Court {court}', '轮到你了：场地 {court}'),
  ('zh-Hant', 'Your turn: Court {court}', '輪到你了：場地 {court}'),
  ('ja', 'Your turn: Court {court}', 'あなたの番です：コート {court}'),
  ('ko', 'Your turn: Court {court}', '차례예요: {court}번 코트'),
  ('id', 'Your turn: Court {court}', 'Giliranmu: Lapangan {court}'),
  ('ms', 'Your turn: Court {court}', 'Giliran anda: Gelanggang {court}'),
  ('th', 'Your turn: Court {court}', 'ถึงตาคุณแล้ว: คอร์ต {court}'),
  ('vi', 'Your turn: Court {court}', 'Đến lượt bạn: Sân {court}'),
  ('hi', 'Your turn: Court {court}', 'आपकी बारी: कोर्ट {court}'),
  ('zh-Hans', 'With {partner}, against {a} and {b}.', '和 {partner} 一组，对 {a}、{b}。'),
  ('zh-Hant', 'With {partner}, against {a} and {b}.', '和 {partner} 一組，對 {a}、{b}。'),
  ('ja', 'With {partner}, against {a} and {b}.', '{partner} さんとペアで、{a} さん・{b} さんと対戦します。'),
  ('ko', 'With {partner}, against {a} and {b}.', '{partner} 님과 한 팀, 상대는 {a}, {b} 님이에요.'),
  ('id', 'With {partner}, against {a} and {b}.', 'Bersama {partner}, melawan {a} dan {b}.'),
  ('ms', 'With {partner}, against {a} and {b}.', 'Bersama {partner}, menentang {a} dan {b}.'),
  ('th', 'With {partner}, against {a} and {b}.', 'คู่กับ {partner} เจอ {a} และ {b}'),
  ('vi', 'With {partner}, against {a} and {b}.', 'Cặp với {partner}, gặp {a} và {b}.'),
  ('hi', 'With {partner}, against {a} and {b}.', '{partner} के साथ, {a} और {b} के खिलाफ़।'),
  ('zh-Hans', 'Against {a}.', '对 {a}。'),
  ('zh-Hant', 'Against {a}.', '對 {a}。'),
  ('ja', 'Against {a}.', '{a} さんと対戦します。'),
  ('ko', 'Against {a}.', '상대는 {a} 님이에요.'),
  ('id', 'Against {a}.', 'Melawan {a}.'),
  ('ms', 'Against {a}.', 'Menentang {a}.'),
  ('th', 'Against {a}.', 'เจอ {a}'),
  ('vi', 'Against {a}.', 'Gặp {a}.'),
  ('hi', 'Against {a}.', '{a} के खिलाफ़।'),
  ('zh-Hans', 'Against {a} and {b}.', '对 {a}、{b}。'),
  ('zh-Hant', 'Against {a} and {b}.', '對 {a}、{b}。'),
  ('ja', 'Against {a} and {b}.', '{a} さん・{b} さんと対戦します。'),
  ('ko', 'Against {a} and {b}.', '상대는 {a}, {b} 님이에요.'),
  ('id', 'Against {a} and {b}.', 'Melawan {a} dan {b}.'),
  ('ms', 'Against {a} and {b}.', 'Menentang {a} dan {b}.'),
  ('th', 'Against {a} and {b}.', 'เจอ {a} และ {b}'),
  ('vi', 'Against {a} and {b}.', 'Gặp {a} và {b}.'),
  ('hi', 'Against {a} and {b}.', '{a} और {b} के खिलाफ़।'),
  ('zh-Hans', '{name} asked you to help tonight', '{name} 请你帮忙排场'),
  ('zh-Hant', '{name} asked you to help tonight', '{name} 請你幫忙排場'),
  ('ja', '{name} asked you to help tonight', '{name} さんから当日の手伝いを頼まれました'),
  ('ko', '{name} asked you to help tonight', '{name} 님이 오늘 진행을 도와 달라고 했어요'),
  ('id', '{name} asked you to help tonight', '{name} minta bantuanmu malam ini'),
  ('ms', '{name} asked you to help tonight', '{name} minta bantuan anda malam ini'),
  ('th', '{name} asked you to help tonight', '{name} ขอให้คุณช่วยจัดคอร์ตคืนนี้'),
  ('vi', '{name} asked you to help tonight', '{name} nhờ bạn phụ xếp sân tối nay'),
  ('hi', '{name} asked you to help tonight', '{name} ने आज आपसे मदद मांगी है'),
  ('zh-Hans', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when}。你可以排场、输比分。'),
  ('zh-Hant', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when}。你可以排場、輸入比分。'),
  ('ja', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when}。コートの割り振りとスコア入力ができます。'),
  ('ko', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when}. 코트 배정과 점수 입력을 할 수 있어요.'),
  ('id', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when}. Kamu bisa mengatur lapangan dan mengisi skor.'),
  ('ms', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when}. Anda boleh mengatur gelanggang dan mengisi skor.'),
  ('th', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when} คุณจัดคอร์ตและกรอกคะแนนได้'),
  ('vi', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when}. Bạn có thể xếp sân và nhập tỉ số.'),
  ('hi', '{group} · {when}. You can run the courts and enter scores.', '{group} · {when}। आप कोर्ट लगा सकते हैं और स्कोर डाल सकते हैं।'),
  ('zh-Hans', 'Your game: Court {court}', '该你了：场地 {court}'),
  ('zh-Hant', 'Your game: Court {court}', '該你了：場地 {court}'),
  ('ja', 'Your game: Court {court}', '試合の番です：コート {court}'),
  ('ko', 'Your game: Court {court}', '경기 차례예요: {court}번 코트'),
  ('id', 'Your game: Court {court}', 'Giliran mainmu: Lapangan {court}'),
  ('ms', 'Your game: Court {court}', 'Giliran perlawanan anda: Gelanggang {court}'),
  ('th', 'Your game: Court {court}', 'ถึงคิวแข่งของคุณ: คอร์ต {court}'),
  ('vi', 'Your game: Court {court}', 'Đến trận của bạn: Sân {court}'),
  ('hi', 'Your game: Court {court}', 'आपका मैच: कोर्ट {court}'),
  ('zh-Hans', 'Match started: {match}', '比赛开始了：{match}'),
  ('zh-Hant', 'Match started: {match}', '比賽開始了：{match}'),
  ('ja', 'Match started: {match}', '試合が始まりました：{match}'),
  ('ko', 'Match started: {match}', '대회가 시작됐어요: {match}'),
  ('id', 'Match started: {match}', 'Turnamen dimulai: {match}'),
  ('ms', 'Match started: {match}', 'Kejohanan bermula: {match}'),
  ('th', 'Match started: {match}', 'เริ่มแข่งแล้ว: {match}'),
  ('vi', 'Match started: {match}', 'Giải đã bắt đầu: {match}'),
  ('hi', 'Match started: {match}', 'मुकाबला शुरू: {match}'),
  ('zh-Hans', 'Your first game is in round {round}.', '你第一场在第 {round} 轮。'),
  ('zh-Hant', 'Your first game is in round {round}.', '你第一場在第 {round} 輪。'),
  ('ja', 'Your first game is in round {round}.', '最初の試合は第 {round} ラウンドです。'),
  ('ko', 'Your first game is in round {round}.', '첫 경기는 {round}라운드예요.'),
  ('id', 'Your first game is in round {round}.', 'Pertandingan pertamamu di babak {round}.'),
  ('ms', 'Your first game is in round {round}.', 'Perlawanan pertama anda dalam pusingan {round}.'),
  ('th', 'Your first game is in round {round}.', 'แมตช์แรกของคุณอยู่รอบที่ {round}'),
  ('vi', 'Your first game is in round {round}.', 'Trận đầu của bạn ở vòng {round}.'),
  ('hi', 'Your first game is in round {round}.', 'आपका पहला मैच राउंड {round} में है।'),
  ('zh-Hans', 'Match over: you placed #{rank}', '比赛结束：你第 {rank} 名'),
  ('zh-Hant', 'Match over: you placed #{rank}', '比賽結束：你第 {rank} 名'),
  ('ja', 'Match over: you placed #{rank}', '試合終了：あなたは {rank} 位'),
  ('ko', 'Match over: you placed #{rank}', '대회 종료: {rank}위예요'),
  ('id', 'Match over: you placed #{rank}', 'Turnamen selesai: kamu peringkat {rank}'),
  ('ms', 'Match over: you placed #{rank}', 'Kejohanan tamat: anda di tempat ke-{rank}'),
  ('th', 'Match over: you placed #{rank}', 'แข่งจบแล้ว: คุณได้อันดับ {rank}'),
  ('vi', 'Match over: you placed #{rank}', 'Giải kết thúc: bạn hạng {rank}'),
  ('hi', 'Match over: you placed #{rank}', 'मुकाबला खत्म: आप #{rank} पर रहे'),
  ('zh-Hans', 'Open it to see the final standings.', '点开看最终排名。'),
  ('zh-Hant', 'Open it to see the final standings.', '點開看最終排名。'),
  ('ja', 'Open it to see the final standings.', '開いて最終順位を確認できます。'),
  ('ko', 'Open it to see the final standings.', '눌러서 최종 순위를 확인하세요.'),
  ('id', 'Open it to see the final standings.', 'Buka untuk melihat peringkat akhir.'),
  ('ms', 'Open it to see the final standings.', 'Buka untuk melihat kedudukan akhir.'),
  ('th', 'Open it to see the final standings.', 'เปิดดูอันดับสุดท้าย'),
  ('vi', 'Open it to see the final standings.', 'Mở để xem bảng xếp hạng cuối.'),
  ('hi', 'Open it to see the final standings.', 'अंतिम रैंकिंग देखने के लिए खोलें।'),
  ('zh-Hans', 'Match cancelled: {match}', '比赛取消了：{match}'),
  ('zh-Hant', 'Match cancelled: {match}', '比賽取消了：{match}'),
  ('ja', 'Match cancelled: {match}', '試合が中止になりました：{match}'),
  ('ko', 'Match cancelled: {match}', '대회가 취소됐어요: {match}'),
  ('id', 'Match cancelled: {match}', 'Turnamen dibatalkan: {match}'),
  ('ms', 'Match cancelled: {match}', 'Kejohanan dibatalkan: {match}'),
  ('th', 'Match cancelled: {match}', 'ยกเลิกการแข่งแล้ว: {match}'),
  ('vi', 'Match cancelled: {match}', 'Giải đã bị hủy: {match}'),
  ('hi', 'Match cancelled: {match}', 'मुकाबला रद्द: {match}'),
  ('zh-Hans', '{name} deleted this match.', '{name} 删掉了这场比赛。'),
  ('zh-Hant', '{name} deleted this match.', '{name} 刪除了這場比賽。'),
  ('ja', '{name} deleted this match.', '{name} さんがこの試合を削除しました。'),
  ('ko', '{name} deleted this match.', '{name} 님이 이 대회를 삭제했어요.'),
  ('id', '{name} deleted this match.', '{name} menghapus turnamen ini.'),
  ('ms', '{name} deleted this match.', '{name} memadam kejohanan ini.'),
  ('th', '{name} deleted this match.', '{name} ลบการแข่งนี้แล้ว'),
  ('vi', '{name} deleted this match.', '{name} đã xóa giải này.'),
  ('hi', '{name} deleted this match.', '{name} ने यह मुकाबला हटा दिया।'),
  ('zh-Hans', '{name} asked you to keep score', '{name} 请你帮忙记分'),
  ('zh-Hant', '{name} asked you to keep score', '{name} 請你幫忙記分'),
  ('ja', '{name} asked you to keep score', '{name} さんからスコア係を頼まれました'),
  ('ko', '{name} asked you to keep score', '{name} 님이 점수 기록을 부탁했어요'),
  ('id', '{name} asked you to keep score', '{name} minta kamu mencatat skor'),
  ('ms', '{name} asked you to keep score', '{name} minta anda mencatat skor'),
  ('th', '{name} asked you to keep score', '{name} ขอให้คุณช่วยจดคะแนน'),
  ('vi', '{name} asked you to keep score', '{name} nhờ bạn ghi điểm'),
  ('hi', '{name} asked you to keep score', '{name} ने आपसे स्कोर रखने को कहा है'),
  ('zh-Hans', '{match}. You can enter scores.', '{match}。你可以输比分。'),
  ('zh-Hant', '{match}. You can enter scores.', '{match}。你可以輸入比分。'),
  ('ja', '{match}. You can enter scores.', '{match}。スコアを入力できます。'),
  ('ko', '{match}. You can enter scores.', '{match}. 점수를 입력할 수 있어요.'),
  ('id', '{match}. You can enter scores.', '{match}. Kamu bisa mengisi skor.'),
  ('ms', '{match}. You can enter scores.', '{match}. Anda boleh mengisi skor.'),
  ('th', '{match}. You can enter scores.', '{match} คุณกรอกคะแนนได้'),
  ('vi', '{match}. You can enter scores.', '{match}. Bạn có thể nhập tỉ số.'),
  ('hi', '{match}. You can enter scores.', '{match}। आप स्कोर डाल सकते हैं।'),
  ('zh-Hans', 'Court fee: {group}', '场地费：{group}'),
  ('zh-Hant', 'Court fee: {group}', '場地費：{group}'),
  ('ja', 'Court fee: {group}', 'コート代：{group}'),
  ('ko', 'Court fee: {group}', '코트비: {group}'),
  ('id', 'Court fee: {group}', 'Biaya lapangan: {group}'),
  ('ms', 'Court fee: {group}', 'Yuran gelanggang: {group}'),
  ('th', 'Court fee: {group}', 'ค่าคอร์ต: {group}'),
  ('vi', 'Court fee: {group}', 'Tiền sân: {group}'),
  ('hi', 'Court fee: {group}', 'कोर्ट फ़ीस: {group}'),
  ('zh-Hans', '{when} · {amount} each, paid to {name}.', '{when} · 每人 {amount}，付给 {name}。'),
  ('zh-Hant', '{when} · {amount} each, paid to {name}.', '{when} · 每人 {amount}，付給 {name}。'),
  ('ja', '{when} · {amount} each, paid to {name}.', '{when} · 1 人 {amount}、{name} さんへ。'),
  ('ko', '{when} · {amount} each, paid to {name}.', '{when} · 1인당 {amount}, {name} 님에게 보내 주세요.'),
  ('id', '{when} · {amount} each, paid to {name}.', '{when} · {amount} per orang, dibayar ke {name}.'),
  ('ms', '{when} · {amount} each, paid to {name}.', '{when} · {amount} seorang, dibayar kepada {name}.'),
  ('th', '{when} · {amount} each, paid to {name}.', '{when} · คนละ {amount} จ่ายให้ {name}'),
  ('vi', '{when} · {amount} each, paid to {name}.', '{when} · Mỗi người {amount}, trả cho {name}.'),
  ('hi', '{when} · {amount} each, paid to {name}.', '{when} · हर व्यक्ति {amount}, {name} को दें।'),
  ('zh-Hans', '{when} · Pay {name}.', '{when} · 付给 {name}。'),
  ('zh-Hant', '{when} · Pay {name}.', '{when} · 付給 {name}。'),
  ('ja', '{when} · Pay {name}.', '{when} · {name} さんへお支払いください。'),
  ('ko', '{when} · Pay {name}.', '{when} · {name} 님에게 보내 주세요.'),
  ('id', '{when} · Pay {name}.', '{when} · Bayar ke {name}.'),
  ('ms', '{when} · Pay {name}.', '{when} · Bayar kepada {name}.'),
  ('th', '{when} · Pay {name}.', '{when} · จ่ายให้ {name}'),
  ('vi', '{when} · Pay {name}.', '{when} · Trả cho {name}.'),
  ('hi', '{when} · Pay {name}.', '{when} · {name} को भुगतान करें।'),
  ('zh-Hans', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court}。每人 {amount}，付给 {name}。在这里付：'),
  ('zh-Hant', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court}。每人 {amount}，付給 {name}。在這裡付：'),
  ('ja', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court}。1 人 {amount}、{name} さんへ。こちらから支払えます：'),
  ('ko', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court}. 1인당 {amount}, {name} 님에게 보내 주세요. 여기서 보낼 수 있어요:'),
  ('id', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court}. {amount} per orang, dibayar ke {name}. Bayar di sini:'),
  ('ms', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court}. {amount} seorang, dibayar kepada {name}. Bayar di sini:'),
  ('th', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court} คนละ {amount} จ่ายให้ {name} จ่ายได้ที่นี่:'),
  ('vi', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court}. Mỗi người {amount}, trả cho {name}. Trả tại đây:'),
  ('hi', '{when} · {court}. {amount} each, paid to {name}. Pay here:', '{when} · {court}। हर व्यक्ति {amount}, {name} को दें। यहाँ भुगतान करें:'),
  ('zh-Hans', '{when} · {court}. Pay {name} here:', '{when} · {court}。在这里付给 {name}：'),
  ('zh-Hant', '{when} · {court}. Pay {name} here:', '{when} · {court}。在這裡付給 {name}：'),
  ('ja', '{when} · {court}. Pay {name} here:', '{when} · {court}。{name} さんへのお支払いはこちら：'),
  ('ko', '{when} · {court}. Pay {name} here:', '{when} · {court}. {name} 님에게 여기서 보낼 수 있어요:'),
  ('id', '{when} · {court}. Pay {name} here:', '{when} · {court}. Bayar ke {name} di sini:'),
  ('ms', '{when} · {court}. Pay {name} here:', '{when} · {court}. Bayar kepada {name} di sini:'),
  ('th', '{when} · {court}. Pay {name} here:', '{when} · {court} จ่ายให้ {name} ได้ที่นี่:'),
  ('vi', '{when} · {court}. Pay {name} here:', '{when} · {court}. Trả cho {name} tại đây:'),
  ('hi', '{when} · {court}. Pay {name} here:', '{when} · {court}। {name} को यहाँ भुगतान करें:')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
