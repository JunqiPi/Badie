-- 社交：赛后评价、等级校准、球友、私信、拉黑和举报
-- 规则与 iOS 一致（Badie-iOS/docs/DESIGN.md §11、§12）：
-- - 评价只用于匹配和私下提醒，任何人都看不到分数和单条评价；对外只显示月度快照的正面标签和“靠谱”徽章
-- - 双方都选了“还想再约”才告诉双方（直接成为球友）
-- - 资料页只对有交集的人开放（同一场球局 / 同一个提议 / 球友 / 好友申请），防止被批量查看
-- - 私信：球友随便聊；同一场球局用球局群聊（赛后 48 小时关闭）；陌生人只能加球友
-- 这一版先不做：球群里的消息请求（等球群上线）、双盲延迟生效（评价本来就不单独展示）

-- ---------------------------------------------------------------------------
-- 等级校准：问卷分值单独存，rating 是匹配用的综合分值
-- ---------------------------------------------------------------------------

alter table public.profiles add column self_rating numeric(4, 2) not null default 3 check (self_rating between 0.66 and 6.34);
update public.profiles set self_rating = least(rating, 6.33);

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

create type public.attendance as enum ('on_time', 'late', 'no_show');
create type public.level_check as enum ('lower', 'accurate', 'higher');

-- 赛后评价：每场每人只能评一次，结束后 48 小时内
create table public.game_reviews (
  game_id uuid not null references public.games (id) on delete cascade,
  reviewer_id uuid not null references auth.users (id) on delete cascade,
  reviewee_id uuid not null references auth.users (id) on delete cascade,
  attendance public.attendance not null,
  level_check public.level_check not null,
  -- 评价者眼里对方的水平：对方这局的等级上下移一档
  peer_rating numeric(4, 2) not null,
  tags text[] not null default '{}' check (tags <@ array['friendly', 'punctual', 'skilled', 'patient', 'fair_play', 'great_partner']),
  -- 需要对方注意的地方：不公开、不计分，只用于私下提醒
  issues text[] not null default '{}' check (issues <@ array['unsafe_play', 'rude', 'hogging', 'unpaid']),
  play_again boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (game_id, reviewer_id, reviewee_id),
  check (reviewer_id <> reviewee_id)
);

create index game_reviews_reviewee_idx on public.game_reviews (reviewee_id, created_at);

-- 同一问题 60 天内只私下提醒一次
create table public.review_nudges (
  user_id uuid not null references auth.users (id) on delete cascade,
  issue text not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, issue)
);

create table public.friendships (
  user_a uuid not null references auth.users (id) on delete cascade,
  user_b uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create index friendships_user_b_idx on public.friendships (user_b);

-- 忽略的申请保留（发的人仍看到“已申请”，不知道被忽略，也不能反复发）
create table public.friend_requests (
  from_id uuid not null references auth.users (id) on delete cascade,
  to_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  ignored_at timestamptz,
  primary key (from_id, to_id),
  check (from_id <> to_id)
);

create index friend_requests_to_idx on public.friend_requests (to_id) where ignored_at is null;

create table public.blocks (
  blocker uuid not null references auth.users (id) on delete cascade,
  blocked uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);

create index blocks_blocked_idx on public.blocks (blocked);

create table public.user_reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references auth.users (id) on delete cascade,
  reported_id uuid not null references auth.users (id) on delete cascade,
  reason text not null check (reason in ('harassment', 'scam', 'unsafe', 'fake', 'other')),
  details text check (char_length(details) <= 1000),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- 会话：球局群聊 “game:<球局 id>”，球友私信 “dm:<较小的用户 id>:<较大的用户 id>”
create table public.messages (
  id bigint generated always as identity primary key,
  thread text not null check (thread ~ '^(game:[0-9a-f-]{36}|dm:[0-9a-f-]{36}:[0-9a-f-]{36})$'),
  sender_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index messages_thread_idx on public.messages (thread, id);
create index messages_sender_idx on public.messages (sender_id, created_at);

create table public.thread_reads (
  user_id uuid not null references auth.users (id) on delete cascade,
  thread text not null,
  last_read_id bigint not null,
  primary key (user_id, thread)
);

-- 结束后提醒评价（每场只提醒一次）
alter table public.games add column review_prompted boolean not null default false;

alter table public.game_reviews enable row level security;
alter table public.review_nudges enable row level security;
alter table public.friendships enable row level security;
alter table public.friend_requests enable row level security;
alter table public.blocks enable row level security;
alter table public.user_reports enable row level security;
alter table public.messages enable row level security;
alter table public.thread_reads enable row level security;

-- 客户端对这些表没有任何权限，全部走下面的函数
revoke all on public.game_reviews, public.review_nudges, public.friendships, public.friend_requests, public.blocks,
  public.user_reports, public.messages, public.thread_reads from anon, authenticated;
grant all on public.game_reviews, public.review_nudges, public.friendships, public.friend_requests, public.blocks,
  public.user_reports, public.messages, public.thread_reads to service_role;

-- ---------------------------------------------------------------------------
-- 内部工具
-- ---------------------------------------------------------------------------

create function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.friendships where user_a = least(a, b) and user_b = greatest(a, b))
$$;

create function public.blocked_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.blocks where (blocker = a and blocked = b) or (blocker = b and blocked = a))
$$;

-- 两人有交集：同一场球局、同一个提议、球友，或者有好友申请。只有这样才能看资料、加球友、拉黑、举报
create function public.related(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select a = b or public.are_friends(a, b)
    or exists (select 1 from public.game_players x join public.game_players y on y.game_id = x.game_id
               where x.user_id = a and y.user_id = b)
    or exists (select 1 from public.match_seats x join public.match_seats y on y.offer_id = x.offer_id
               where x.user_id = a and y.user_id = b)
    or exists (select 1 from public.friend_requests where (from_id = a and to_id = b) or (from_id = b and to_id = a))
$$;

-- 履约记录：打完的场次、爽约（没签到，并且有球友说没来）、临时取消
create function public.attendance_record(p_user uuid)
returns table (games_played bigint, no_shows bigint, late_cancels bigint)
language sql stable security definer set search_path = '' as $$
  with ended as (
    select gp.checked_in_at is null and exists (
             select 1 from public.game_reviews r where r.game_id = g.id and r.reviewee_id = p_user and r.attendance = 'no_show') as no_show
    from public.game_players gp join public.games g on g.id = gp.game_id
    where gp.user_id = p_user and g.status = 'scheduled' and g.ends_at < now())
  select count(*) filter (where not no_show), count(*) filter (where no_show),
         (select count(*) from public.game_players where user_id = p_user and late_cancel)
  from ended
$$;

-- 综合分值：评价满 5 次后 = 30% 问卷 + 70% 球友评价（没做问卷或问卷顶到 6+ 时 15% + 85%，更快校准）；
-- 没认证最高 7−。爽约那场的评价不算水平
create function public.refresh_rating(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  update public.profiles p
    set rating = case when r.n >= 5
      then least(greatest(round(((1 - r.w) * p.self_rating + r.w * r.peer) * 3) / 3, 0.67), 6.67)
      else p.self_rating end
  from (select count(gr.reviewer_id) as n, avg(gr.peer_rating) as peer,
               case when pr.assessed_at is null or pr.self_rating >= 6.33 then 0.85 else 0.7 end as w
        from public.profiles pr left join public.game_reviews gr on gr.reviewee_id = pr.id and gr.attendance <> 'no_show'
        where pr.id = p_user group by pr.assessed_at, pr.self_rating) r
  where p.id = p_user
$$;

-- 对外的正面标签：上个月底为止的评价，≥5 位不同球友、≥3 场后才有；每个标签至少 2 位不同球友给过；最多 3 个
create function public.public_tags(p_user uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  with r as (select * from public.game_reviews where reviewee_id = p_user and created_at < date_trunc('month', now()))
  select case when (select count(distinct reviewer_id) from r) >= 5 and (select count(distinct game_id) from r) >= 3
    then array(select tag from r, unnest(r.tags) tag group by tag having count(distinct r.reviewer_id) >= 2
               order by count(distinct r.reviewer_id) desc,
                        array_position(array['friendly', 'punctual', 'skilled', 'patient', 'fair_play', 'great_partner'], tag)
               limit 3)
    else '{}' end
$$;

create function public.make_friends(a uuid, b uuid, p_title text, p_body text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.friendships (user_a, user_b) values (least(a, b), greatest(a, b)) on conflict do nothing;
  if not found then return; end if;
  delete from public.friend_requests where (from_id = a and to_id = b) or (from_id = b and to_id = a);
  perform public.notify(a, 'friend', p_title, replace(p_body, '{name}', (select nickname from public.profiles where id = b)), '/app/players/' || b || '/');
  perform public.notify(b, 'friend', p_title, replace(p_body, '{name}', (select nickname from public.profiles where id = a)), '/app/players/' || a || '/');
end
$$;

-- 拉黑的人不会再被匹配到一起（匹配时双方任一方排除对方就不配）
create function public.exclude_blocked()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.excluded_user_ids := array(select distinct x from unnest(new.excluded_user_ids || array(
    select blocked from public.blocks where blocker = new.user_id)) x);
  return new;
end
$$;

create trigger match_tickets_exclude_blocked before insert on public.match_tickets
  for each row execute function public.exclude_blocked();

-- 球局结束后提醒大家评价
create function public.prompt_reviews()
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
        public.slot_text(g.starts_at, g.venue_id) || '. Rate your partners within 48 hours. It stays private.', '/app/games/' || g.id || '/');
    end loop;
  end loop;
end
$$;

-- 会话 id；私信只能和球友
create function public.thread_key(p_kind text, p_id uuid)
returns text language sql stable set search_path = '' as $$
  select case p_kind when 'game' then 'game:' || p_id
                     when 'dm' then 'dm:' || least(auth.uid(), p_id) || ':' || greatest(auth.uid(), p_id) end
$$;

-- 我在这个会话里：'open' 能发，'closed' 只能看，null 看不了
create function public.thread_access(p_kind text, p_id uuid, p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'game' then (
      select case when g.status = 'scheduled' and now() <= g.ends_at + interval '48 hours' then 'open' else 'closed' end
      from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = p_user where g.id = p_id)
    when 'dm' then case
      when p_user = p_id then null
      when public.are_friends(p_user, p_id) and not public.blocked_between(p_user, p_id) then 'open'
      when exists (select 1 from public.messages where thread = 'dm:' || least(p_user, p_id) || ':' || greatest(p_user, p_id)) then 'closed'
      end
    end
$$;

-- ---------------------------------------------------------------------------
-- 等级与评价
-- ---------------------------------------------------------------------------

create or replace function public.save_assessment(p_rating numeric, p_answers jsonb)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare
  result public.profiles;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_rating is null or p_rating not between 0.66 and 6.34 then raise exception 'invalid_rating' using errcode = '22023'; end if;
  if exists (select 1 from public.profiles where id = auth.uid() and assessed_at > now() - interval '90 days') then
    raise exception 'retake_too_soon' using errcode = '22023';
  end if;
  update public.profiles set self_rating = round(p_rating * 3) / 3, assessed_at = now(), assessment = p_answers
    where id = auth.uid();
  if not found then raise exception 'no_profile' using errcode = 'P0002'; end if;
  perform public.refresh_rating(auth.uid());
  select * into result from public.profiles where id = auth.uid();
  return result;
end
$$;

-- 评价同局的一位球友（结束后 48 小时内，每人一次）
create function public.review_player(p_game uuid, p_user uuid, p_attendance public.attendance, p_level public.level_check,
                                     p_tags text[], p_issues text[], p_play_again boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  their_rating numeric;
  flagged text;
begin
  if not exists (select 1 from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = me
                 where g.id = p_game and g.status = 'scheduled' and now() between g.ends_at and g.ends_at + interval '48 hours')
     or p_user = me then
    raise exception 'cannot_review' using errcode = 'P0002';
  end if;
  select rating into their_rating from public.game_players where game_id = p_game and user_id = p_user;
  if their_rating is null then raise exception 'cannot_review' using errcode = 'P0002'; end if;

  insert into public.game_reviews (game_id, reviewer_id, reviewee_id, attendance, level_check, peer_rating, tags, issues, play_again)
    values (p_game, me, p_user, p_attendance, p_level,
            least(greatest(their_rating + case p_level when 'lower' then -1 when 'higher' then 1 else 0 end / 3.0, 0.67), 9.33),
            coalesce(p_tags, '{}'), coalesce(p_issues, '{}'), coalesce(p_play_again, false))
    on conflict do nothing;
  if not found then raise exception 'already_reviewed' using errcode = '23505'; end if;
  perform public.refresh_rating(p_user);

  -- 双方都想再约：成为球友
  if p_play_again and exists (select 1 from public.game_reviews
                              where game_id = p_game and reviewer_id = p_user and reviewee_id = me and play_again) then
    perform public.make_friends(me, p_user, 'You both want to play again', 'You and {name} are now friends. Message them to set up the next game.');
  end if;

  -- 60 天内 ≥3 位不同球友提到同一点：私下提醒本人（不说是谁），同一点 60 天内只提醒一次
  for flagged in select i from public.game_reviews r, unnest(r.issues) i
               where r.reviewee_id = p_user and r.created_at > now() - interval '60 days'
               group by i having count(distinct r.reviewer_id) >= 3 loop
    insert into public.review_nudges (user_id, issue) values (p_user, flagged)
      on conflict on constraint review_nudges_pkey do update set sent_at = now() where review_nudges.sent_at < now() - interval '60 days';
    if found then
      perform public.notify(p_user, 'nudge', 'A tip from recent games', case flagged
        when 'unsafe_play' then 'Keep an eye on the people around you and keep your swings safe.'
        when 'rude' then 'Keep it friendly on court. Everyone is here to enjoy the game.'
        when 'hogging' then 'In doubles, share the court and let your partner play their shots.'
        else 'Settle up court fees soon after the game.' end);
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 球友、拉黑、举报
-- ---------------------------------------------------------------------------

-- 返回 'requested' 或 'friends'（对方也申请过我就直接成为球友）
create function public.send_friend_request(p_user uuid)
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
    perform public.notify(p_user, 'friend_request', 'Friend request',
      (select nickname from public.profiles where id = me) || ' wants to be friends.', '/app/players/' || me || '/');
  end if;
  return 'requested';
end
$$;

-- 接受或忽略（忽略对方不会知道）
create function public.respond_friend_request(p_user uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.friend_requests where from_id = p_user and to_id = auth.uid() and ignored_at is null) then
    raise exception 'no_request' using errcode = 'P0002';
  end if;
  if p_accept then
    perform public.make_friends(auth.uid(), p_user, 'New friend', 'You and {name} are now friends.');
  else
    update public.friend_requests set ignored_at = now() where from_id = p_user and to_id = auth.uid();
  end if;
end
$$;

create function public.remove_friend(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.friendships where user_a = least(auth.uid(), p_user) and user_b = greatest(auth.uid(), p_user)
$$;

-- 拉黑：解除球友、撤掉申请、以后不再匹配到一起、私信关闭。对方不会收到通知
create function public.block_user(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null or p_user = me or not public.related(me, p_user) then raise exception 'not_allowed' using errcode = '42501'; end if;
  insert into public.blocks (blocker, blocked) values (me, p_user) on conflict do nothing;
  delete from public.friendships where user_a = least(me, p_user) and user_b = greatest(me, p_user);
  delete from public.friend_requests where (from_id = me and to_id = p_user) or (from_id = p_user and to_id = me);
  update public.match_tickets set excluded_user_ids = array_append(excluded_user_ids, p_user)
    where user_id = me and status in ('searching', 'offered', 'paused') and not p_user = any (excluded_user_ids);
end
$$;

create function public.unblock_user(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.blocks where blocker = auth.uid() and blocked = p_user
$$;

-- 举报：管理员会收到通知；每人每天最多 10 次
create function public.report_user(p_user uuid, p_reason text, p_details text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  admin record;
begin
  if me is null or p_user = me or not public.related(me, p_user) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if (select count(*) from public.user_reports where reporter_id = me and created_at > now() - interval '1 day') >= 10 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;
  insert into public.user_reports (reporter_id, reported_id, reason, details) values (me, p_user, p_reason, nullif(btrim(p_details), ''));
  for admin in select user_id from public.admin_users loop
    perform public.notify(admin.user_id, 'report', 'New player report', 'Reason: ' || p_reason || '. Review it in the database.');
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 资料页
-- ---------------------------------------------------------------------------

-- 只有正面信息和客观记录，没有分数、胜率、精确场次、好友列表；没有交集的人返回 null
create function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'assessed', p.assessed_at is not null,
    'games_band', case when a.games_played = 0 then 'No games yet' when a.games_played < 5 then '1–4 games'
                       when a.games_played < 20 then '5+ games' when a.games_played < 50 then '20+ games' else '50+ games' end,
    'new_player', (select count(*) from public.game_reviews where reviewee_id = p.id) < 5,
    'reliable', a.games_played >= 3 and a.no_shows = 0 and a.late_cancels <= 1,
    'tags', to_jsonb(public.public_tags(p.id)),
    'relationship', case
      when p.id = auth.uid() then 'self'
      when exists (select 1 from public.blocks where blocker = auth.uid() and blocked = p.id) then 'blocked'
      when public.are_friends(auth.uid(), p.id) then 'friend'
      when exists (select 1 from public.friend_requests where from_id = auth.uid() and to_id = p.id) then 'requested'
      when exists (select 1 from public.friend_requests where from_id = p.id and to_id = auth.uid() and ignored_at is null) then 'incoming'
      else 'none' end,
    'games_together', (select count(*) from public.game_players x join public.game_players y on y.game_id = x.game_id
                       join public.games g on g.id = x.game_id
                       where x.user_id = auth.uid() and y.user_id = p.id and g.status = 'scheduled' and g.ends_at < now()),
    'last_game', (select jsonb_build_object('starts_at', g.starts_at, 'venue', v.name, 'tz', v.time_zone_id)
                  from public.game_players x join public.game_players y on y.game_id = x.game_id
                  join public.games g on g.id = x.game_id join public.venues v on v.id = g.venue_id
                  where x.user_id = auth.uid() and y.user_id = p.id and g.status = 'scheduled' and g.ends_at < now()
                  order by g.starts_at desc limit 1),
    'mutual_friends', (select count(*) from (
        select case when user_a = auth.uid() then user_b else user_a end as f from public.friendships where auth.uid() in (user_a, user_b)
        intersect
        select case when user_a = p.id then user_b else user_a end from public.friendships where p.id in (user_a, user_b)) m))
  from public.profiles p cross join lateral public.attendance_record(p.id) a
  where p.id = p_user and public.related(auth.uid(), p_user)
$$;

-- 球友和收到的申请
create function public.my_friends()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'friends', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating) order by lower(p.nickname))
                         from public.friendships f
                         join public.profiles p on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
                         where auth.uid() in (f.user_a, f.user_b)), '[]'),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating, 'created_at', r.created_at)
                                           order by r.created_at desc)
                          from public.friend_requests r join public.profiles p on p.id = r.from_id
                          where r.to_id = auth.uid() and r.ignored_at is null), '[]'))
$$;

-- ---------------------------------------------------------------------------
-- 私信
-- ---------------------------------------------------------------------------

-- 发消息：每分钟最多 20 条，每天 500 条
create function public.send_message(p_kind text, p_id uuid, p_body text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  key text := public.thread_key(p_kind, p_id);
  content text := btrim(p_body);
  new_id bigint;
begin
  if me is null or public.thread_access(p_kind, p_id, me) is distinct from 'open' then
    raise exception 'chat_closed' using errcode = '42501';
  end if;
  if content is null or char_length(content) not between 1 and 1000 then raise exception 'invalid_message' using errcode = '22023'; end if;
  if (select count(*) from public.messages where sender_id = me and created_at > now() - interval '1 minute') >= 20
     or (select count(*) from public.messages where sender_id = me and created_at > now() - interval '1 day') >= 500 then
    raise exception 'too_many_messages' using errcode = '54000';
  end if;
  insert into public.messages (thread, sender_id, body) values (key, me, content) returning id into new_id;
  insert into public.thread_reads as r (user_id, thread, last_read_id) values (me, key, new_id)
    on conflict on constraint thread_reads_pkey do update set last_read_id = excluded.last_read_id;
  return new_id;
end
$$;

-- 打开会话：最近 200 条消息、标题信息，并标记已读
create function public.open_thread(p_kind text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  key text := public.thread_key(p_kind, p_id);
  access text := public.thread_access(p_kind, p_id, me);
  result jsonb;
begin
  if me is null or access is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  select jsonb_build_object(
    'access', access,
    'friend', p_kind = 'dm' and public.are_friends(me, p_id),
    'game', (select jsonb_build_object('starts_at', g.starts_at, 'ends_at', g.ends_at, 'venue', v.name, 'tz', v.time_zone_id)
             from public.games g join public.venues v on v.id = g.venue_id where p_kind = 'game' and g.id = p_id),
    'members', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'me', p.id = me) order by p.id = me, lower(p.nickname))
                from public.profiles p
                where (p_kind = 'game' and p.id in (select user_id from public.game_players where game_id = p_id))
                   or (p_kind = 'dm' and p.id in (me, p_id))),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'created_at', m.created_at,
                                                             'sender', m.sender_id, 'mine', m.sender_id = me) order by m.id)
                          from (select * from public.messages where thread = key order by id desc limit 200) m), '[]'))
    into result;
  insert into public.thread_reads (user_id, thread, last_read_id)
    select me, key, max(id) from public.messages where thread = key having max(id) is not null
    on conflict on constraint thread_reads_pkey do update set last_read_id = excluded.last_read_id;
  return result;
end
$$;

-- 会话列表：有消息的私信 + 最近 30 天的球局群聊（开着的或有消息的）
create function public.my_threads()
returns jsonb language sql stable security definer set search_path = '' as $$
  with threads as (
    select 'game' as kind, g.id, 'game:' || g.id as thread, g.starts_at, v.name as venue, v.time_zone_id as tz, null::text as nickname,
           case when g.status = 'scheduled' and now() <= g.ends_at + interval '48 hours' then 'open' else 'closed' end as access
    from public.game_players gp join public.games g on g.id = gp.game_id join public.venues v on v.id = g.venue_id
    where gp.user_id = auth.uid() and g.ends_at > now() - interval '30 days'
    union all
    select 'dm', p.id, 'dm:' || least(auth.uid(), p.id) || ':' || greatest(auth.uid(), p.id), null, null, null, p.nickname,
           case when public.blocked_between(auth.uid(), p.id) then 'closed' else 'open' end
    from public.friendships f join public.profiles p on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
    where auth.uid() in (f.user_a, f.user_b))
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'id', t.id, 'starts_at', t.starts_at, 'venue', t.venue, 'tz', t.tz, 'nickname', t.nickname, 'access', t.access,
      'last', (select jsonb_build_object('body', m.body, 'created_at', m.created_at, 'mine', m.sender_id = auth.uid()) from public.messages m
               where m.thread = t.thread order by m.id desc limit 1),
      'unread', (select count(*) from public.messages m where m.thread = t.thread and m.sender_id <> auth.uid()
                 and m.id > coalesce((select last_read_id from public.thread_reads r where r.user_id = auth.uid() and r.thread = t.thread), 0)))
    order by coalesce((select max(m.created_at) from public.messages m where m.thread = t.thread), t.starts_at) desc), '[]')
  from threads t
  where t.kind = 'game' and t.access = 'open' or exists (select 1 from public.messages m where m.thread = t.thread)
$$;

-- 导航上的未读数
create function public.inbox_counts()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'messages', (select coalesce(sum((t ->> 'unread')::int), 0) from jsonb_array_elements(public.my_threads()) t),
    'updates', (select count(*) from public.notifications where user_id = auth.uid() and read_at is null),
    'requests', (select count(*) from public.friend_requests where to_id = auth.uid() and ignored_at is null))
$$;

-- ---------------------------------------------------------------------------
-- 页面数据：加上球友 id（点头像看资料）、评价状态、爽约次数
-- ---------------------------------------------------------------------------

create or replace function public.my_matchmaking()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at), '[]') from (
    select t.starts_at, jsonb_build_object(
      'id', t.id, 'mode', t.mode, 'starts_at', t.starts_at, 'ends_at', t.ends_at, 'status', t.status,
      'skill_tolerance', t.skill_tolerance, 'auto_accept', t.auto_accept, 'lock_at', t.lock_at, 'game_id', t.game_id,
      'venues', (select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'tz', v.time_zone_id))
                 from public.venues v where v.id = any (t.venue_ids)),
      'offer', (select jsonb_build_object(
          'id', o.id, 'starts_at', o.starts_at, 'ends_at', o.ends_at, 'respond_by', me.respond_by, 'my_response', me.response,
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

create or replace function public.my_games()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at desc), '[]') from (
    select g.starts_at, jsonb_build_object(
      'id', g.id, 'mode', g.mode, 'starts_at', g.starts_at, 'ends_at', g.ends_at, 'status', g.status,
      'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                  'lat', v.lat, 'lon', v.lon, 'pricing', v.pricing, 'country', v.country_code),
      'my_team', me.team, 'checked_in', me.checked_in_at is not null,
      'my_report', (select jsonb_build_object('outcome', r.outcome) from public.result_reports r
                    where r.game_id = g.id and r.reporter_id = auth.uid()),
      'result', (select to_jsonb(gr) from public.game_result(g.id) gr),
      'review_until', g.ends_at + interval '48 hours',
      'players', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', gp.rating, 'team', gp.team,
                                                      'me', gp.user_id = auth.uid(), 'checked_in', gp.checked_in_at is not null,
                                                      'reviewed', exists (select 1 from public.game_reviews r where r.game_id = g.id
                                                                          and r.reviewer_id = auth.uid() and r.reviewee_id = gp.user_id))
                                   order by gp.team, gp.rating desc)
                  from public.game_players gp join public.profiles p on p.id = gp.user_id where gp.game_id = g.id)
    ) as item
    from public.games g
    join public.game_players me on me.game_id = g.id and me.user_id = auth.uid()
    join public.venues v on v.id = g.venue_id
    where g.ends_at > now() - interval '60 days'
  ) items
$$;

create or replace function public.my_record()
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
    'games_played', a.games_played, 'no_shows', a.no_shows, 'late_cancels', a.late_cancels)
  from public.attendance_record(auth.uid()) a
$$;

-- ---------------------------------------------------------------------------
-- 权限与定时任务
-- ---------------------------------------------------------------------------

revoke execute on function public.are_friends(uuid, uuid), public.blocked_between(uuid, uuid), public.related(uuid, uuid),
  public.attendance_record(uuid), public.refresh_rating(uuid), public.public_tags(uuid), public.make_friends(uuid, uuid, text, text),
  public.exclude_blocked(), public.prompt_reviews(), public.thread_key(text, uuid), public.thread_access(text, uuid, uuid)
  from public, anon, authenticated;

revoke execute on function public.review_player(uuid, uuid, public.attendance, public.level_check, text[], text[], boolean),
  public.send_friend_request(uuid), public.respond_friend_request(uuid, boolean), public.remove_friend(uuid),
  public.block_user(uuid), public.unblock_user(uuid), public.report_user(uuid, text, text), public.player_card(uuid),
  public.my_friends(), public.send_message(text, uuid, text), public.open_thread(text, uuid), public.my_threads(), public.inbox_counts()
  from public, anon;
grant execute on function public.review_player(uuid, uuid, public.attendance, public.level_check, text[], text[], boolean),
  public.send_friend_request(uuid), public.respond_friend_request(uuid, boolean), public.remove_friend(uuid),
  public.block_user(uuid), public.unblock_user(uuid), public.report_user(uuid, text, text), public.player_card(uuid),
  public.my_friends(), public.send_message(text, uuid, text), public.open_thread(text, uuid), public.my_threads(), public.inbox_counts()
  to authenticated;

select cron.schedule('prompt-reviews', '*/5 * * * *', 'select public.prompt_reviews()');
