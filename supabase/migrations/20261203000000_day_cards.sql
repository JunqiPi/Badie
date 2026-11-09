-- 首页按天看能约的人：卡片左右滑，右滑发约球邀请（单打），对方确认就成局。
-- 只有发了约球请求、并且没关掉“让找球友的人看到我”的人才会出现；看不到联系方式

alter table public.profiles add column show_searching boolean not null default true;
grant update (show_searching) on public.profiles to authenticated;

-- 左滑跳过：这个请求不再出现
create table public.candidate_skips (
  viewer uuid not null references auth.users (id) on delete cascade,
  ticket_id uuid not null references public.match_tickets (id) on delete cascade,
  primary key (viewer, ticket_id)
);
alter table public.candidate_skips enable row level security;
revoke all on public.candidate_skips from anon, authenticated;

-- 我能约 TA 吗：TA 的水平范围、只约同性、混双要异性、拉黑和排除名单
create function public.can_invite(p_me uuid, t public.match_tickets)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles me, public.profiles them
    where me.id = p_me and them.id = t.user_id and them.show_searching and p_me <> t.user_id
      and not public.blocked_between(p_me, t.user_id) and not p_me = any (t.excluded_user_ids)
      and abs(round((public.open_rating(me.rating, me.gender) - public.open_rating(them.rating, them.gender)) * 3)) <= t.skill_tolerance * 3
      and (t.play_with is null or t.play_with = me.gender)
      and (not t.mixed or me.gender is distinct from them.gender))
$$;

-- 这一天附近在找人、我能约的（按开始时间排，最多 50 个）
create function public.day_candidates(p_from timestamptz, p_to timestamptz, p_lat double precision, p_lon double precision,
                                      p_radius_km double precision)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(c order by c ->> 'starts_at'), '[]') from (
    select jsonb_build_object(
             'ticket', t.id, 'mode', t.mode, 'mixed', t.mixed, 'play_with', t.play_with,
             'starts_at', t.starts_at, 'ends_at', t.ends_at,
             'user', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'tag', p.tag, 'rating', p.rating, 'gender', p.gender,
                                        'recent_no_shows', public.recent_no_shows(p.id)),
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

create function public.skip_candidate(p_ticket uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.candidate_skips (viewer, ticket_id) select auth.uid(), p_ticket where auth.uid() is not null
  on conflict do nothing
$$;

-- 右滑约 TA（单打）：替我建一个同时段的请求，直接给我们俩发提议，我这边算已确认；TA 确认就成局。
-- TA 拒绝或没回复，我的请求照常留着继续找
create function public.invite_ticket(p_ticket uuid, p_venue text, p_starts_at timestamptz)
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
  select * into t from public.match_tickets where id = p_ticket for update;
  if t.id is null or t.status <> 'searching' or t.mode <> 'singles' or not public.can_invite(me, t) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  if not p_venue = any (t.venue_ids) or extract(epoch from p_starts_at)::bigint % 1800 <> 0 then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  slot_end := least(t.ends_at, p_starts_at + interval '2 hours');
  if p_starts_at < greatest(t.starts_at, now() + interval '30 minutes') or slot_end - p_starts_at < interval '1 hour' then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  if exists (select 1 from public.match_tickets where user_id = me and status in ('searching', 'offered', 'paused')
             and starts_at < slot_end and p_starts_at < ends_at)
     or public.has_game_between(me, p_starts_at, slot_end) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;
  if (select count(*) from public.match_tickets where user_id = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;

  hurried := p_starts_at < now() + interval '150 minutes';
  lock_time := p_starts_at - case when hurried then interval '20 minutes' else interval '2 hours' end;
  select coalesce(time_zone_id, 'UTC') into tz from public.venues where id = p_venue;
  respond_by := least(public.offer_respond_by(p_starts_at, now(), tz), lock_time);
  if respond_by < now() + interval '3 minutes' then raise exception 'too_soon' using errcode = '22023'; end if;

  insert into public.match_tickets (user_id, mode, starts_at, ends_at, venue_ids, skill_tolerance, auto_accept, lock_at, last_minute, status)
    values (me, 'singles', p_starts_at, slot_end, array[p_venue], 8, false, lock_time, hurried, 'offered')
    returning id into mine;
  insert into public.match_offers (mode, starts_at, ends_at, venue_id, lock_at)
    values ('singles', p_starts_at, slot_end, p_venue, lock_time) returning id into offer;
  insert into public.match_seats (offer_id, user_id, ticket_id, team, response, respond_by, responded_at)
    values (offer, me, mine, 1, 'accepted', respond_by, now()), (offer, t.user_id, t.id, 2, 'pending', respond_by, null);
  update public.match_tickets set offer_id = offer where id = mine;
  update public.match_tickets set status = 'offered', offer_id = offer, priority = false where id = t.id;

  perform public.notify(t.user_id, 'offer', '{name} wants to play', '{when} · {court}. Confirm by {by}.', '/app/play/',
    public.slot(p_starts_at, p_venue) || jsonb_build_object('name', (select nickname from public.profiles where id = me),
                                                              'by', jsonb_build_object('at', respond_by, 'tz', tz)));
  return offer;
end
$$;

-- 按天的人数一起放到 30 天
create or replace function public.pool_by_day(p_lat double precision, p_lon double precision, p_radius_km double precision, p_tz text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(d.day, d.players), '{}') from (
    select (t.starts_at at time zone p_tz)::date::text as day, count(distinct t.user_id) as players
    from public.match_tickets t
    where t.status = 'searching' and t.user_id <> auth.uid() and t.lock_at > now() and t.starts_at < now() + interval '31 days'
      and not public.blocked_between(auth.uid(), t.user_id)
      and exists (select 1 from public.venues v
                  where v.id = any (t.venue_ids)
                    and extensions.st_dwithin(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography,
                                              least(greatest(p_radius_km, 1), 100) * 1000))
    group by 1) d
  where auth.uid() is not null
$$;

revoke execute on function public.can_invite(uuid, public.match_tickets) from public, anon, authenticated;
revoke execute on function public.day_candidates(timestamptz, timestamptz, double precision, double precision, double precision),
  public.skip_candidate(uuid), public.invite_ticket(uuid, text, timestamptz) from public, anon;
grant execute on function public.day_candidates(timestamptz, timestamptz, double precision, double precision, double precision),
  public.skip_candidate(uuid), public.invite_ticket(uuid, text, timestamptz) to authenticated;

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', '{name} wants to play', '{name} 想约你打球'), ('zh-Hant', '{name} wants to play', '{name} 想約你打球'),
  ('ja', '{name} wants to play', '{name} さんから試合のお誘い'), ('ko', '{name} wants to play', '{name}님이 같이 치자고 해요'),
  ('hi', '{name} wants to play', '{name} आपके साथ खेलना चाहते हैं'), ('id', '{name} wants to play', '{name} mengajakmu main'),
  ('ms', '{name} wants to play', '{name} ajak anda bermain'), ('th', '{name} wants to play', '{name} ชวนคุณตีแบด'),
  ('vi', '{name} wants to play', '{name} muốn rủ bạn chơi')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
