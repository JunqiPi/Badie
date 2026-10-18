-- 有多少人在找搭子（只给人数，不给是谁；都不算自己和屏蔽关系）：
-- - pool_by_day：未来 14 天里每天有多少人在附近找（请求里有半径内的球馆），按我的时区分天
-- - ticket_pool：我的一个请求：同一天在附近找同类球局的人数，以及其中条件都合适的人数
--   （时间重叠 ≥ 30 分钟、有共同球馆、水平在双方的容忍范围内、没互相排除，和匹配时的条件一样）

create function public.pool_by_day(p_lat double precision, p_lon double precision, p_radius_km double precision, p_tz text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(d.day, d.players), '{}') from (
    select (t.starts_at at time zone p_tz)::date::text as day, count(distinct t.user_id) as players
    from public.match_tickets t
    where t.status = 'searching' and t.user_id <> auth.uid() and t.lock_at > now() and t.starts_at < now() + interval '15 days'
      and not public.blocked_between(auth.uid(), t.user_id)
      and exists (select 1 from public.venues v
                  where v.id = any (t.venue_ids)
                    and extensions.st_dwithin(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography,
                                              least(greatest(p_radius_km, 1), 100) * 1000))
    group by 1) d
  where auth.uid() is not null
$$;

create function public.ticket_pool(p_ticket uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with t as (
    select mt.*, p.rating, coalesce((select v.time_zone_id from public.venues v where v.id = mt.venue_ids[1]), 'UTC') as tz
    from public.match_tickets mt join public.profiles p on p.id = mt.user_id
    where mt.id = p_ticket and mt.user_id = auth.uid()),
  nearby as (
    select c.user_id, c.starts_at, c.ends_at, c.venue_ids, c.skill_tolerance, c.excluded_user_ids, p.rating
    from t, public.match_tickets c join public.profiles p on p.id = c.user_id
    where c.status = 'searching' and c.mode = t.mode and c.user_id <> t.user_id and c.lock_at > now()
      and (c.starts_at at time zone t.tz)::date = (t.starts_at at time zone t.tz)::date
      and not public.blocked_between(t.user_id, c.user_id)
      and exists (select 1 from public.venues a join public.venues b on extensions.st_dwithin(a.location, b.location, 30000)
                  where a.id = any (t.venue_ids) and b.id = any (c.venue_ids)))
  select jsonb_build_object(
    'available', (select count(distinct n.user_id) from nearby n),
    'compatible', (select count(distinct n.user_id) from nearby n
                   where n.starts_at <= t.ends_at - interval '30 minutes' and n.ends_at >= t.starts_at + interval '30 minutes'
                     and n.venue_ids && t.venue_ids
                     and not n.user_id = any (t.excluded_user_ids) and not t.user_id = any (n.excluded_user_ids)
                     and abs(round((n.rating - t.rating) * 3)) <= least(t.skill_tolerance, n.skill_tolerance) * 3))
  from t
$$;

revoke execute on function public.pool_by_day(double precision, double precision, double precision, text), public.ticket_pool(uuid)
  from public, anon;
grant execute on function public.pool_by_day(double precision, double precision, double precision, text), public.ticket_pool(uuid)
  to authenticated;
