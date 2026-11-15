-- 示例球友：附近的真人太少时，nearby_players 在真人后面补几张示例卡，让刚来的人看懂发现页。
-- 示例不是账号：数据库里没有对应的行，是这个函数临时拼出来的；附近的真人到 6 个就不再返回，不用清理。
-- 认得出来：id 都以 00000000-0000-4000-8000- 开头；卡片照片是存储桶里 avatars/samples/NN.jpg（图的角上印着“Sample · 示例”）。
-- 约不了：invite_player 找不到这个人，照旧报 not_available（“TA 现在约不了”）。跳过示例不记录，也不报错。

-- 原来的 nearby_players 改名：只管真人
alter function public.nearby_players(double precision, double precision, double precision) rename to nearby_real_players;

create function public.is_sample_player(p_user uuid)
returns boolean language sql immutable set search_path = '' as $$
  select p_user::text like '00000000-0000-4000-8000-%'
$$;

create function public.nearby_players(p_lat double precision, p_lon double precision, p_radius_km double precision)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  found jsonb := public.nearby_real_players(p_lat, p_lon, p_radius_km);
  have int := jsonb_array_length(found);
  mine numeric;
  places jsonb;
  samples jsonb;
  names text[] := array['Kevin', 'Mei', 'Sam', 'Bella', 'Danny', 'Ivy', 'Jason', 'Emily', 'Leo', 'Zoe',
                        'Ryan', 'Tina', 'Eric', 'Chloe', 'Alan', 'Nina', 'Marcus', 'Grace', 'Tony', 'Amy'];
  gaps numeric[] := array[-0.67, 0, 0.33, -0.33, 0.67, 1, -1];
  starts int[] := array[18, 19, 9, 14, 20];
begin
  if have >= 6 then return found; end if;
  -- 没定级的人看不到附近的人，也不补示例
  if auth.uid() is null or not public.has_level(auth.uid()) then return found; end if;
  select p.rating into mine from public.profiles p where p.id = auth.uid();

  -- 示例“常去”的球馆：我附近真实的球馆，近的在前，最多 4 家
  select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'km', round((v.dist / 1000)::numeric, 1)) order by v.dist, v.id), '[]'::jsonb)
    into places
  from (
    select x.id, x.name,
           extensions.st_distance(x.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography) as dist
    from public.venues x
    where x.merged_into is null
      and extensions.st_dwithin(x.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography,
                                (least(greatest(p_radius_km, 1), 100) * 1000)::double precision)
    order by dist, x.id
    limit 4) v;

  select jsonb_agg(jsonb_build_object(
           'user', jsonb_build_object(
             'id', ('00000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
             'nickname', names[i],
             'tag', null,
             'rating', round(least(6.33, greatest(1, mine + gaps[1 + (i - 1) % 7])), 2),
             'gender', null,
             'recent_no_shows', 0,
             'avatar', null,
             'card_color', null,
             'card_photo', 'samples/' || lpad(i::text, 2, '0') || '.jpg',
             'preferred_mode', case when i % 3 = 1 then 'singles' else 'doubles' end,
             'usual_times', jsonb_build_array(
               jsonb_build_object('weekday', 1 + (i * 3) % 7,
                                  'start', lpad(starts[1 + (i - 1) % 5]::text, 2, '0') || ':00',
                                  'end', lpad((starts[1 + (i - 1) % 5] + 2)::text, 2, '0') || ':00'),
               jsonb_build_object('weekday', 1 + (i * 3 + 2) % 7,
                                  'start', lpad(starts[1 + (i + 1) % 5]::text, 2, '0') || ':00',
                                  'end', lpad((starts[1 + (i + 1) % 5] + 2)::text, 2, '0') || ':00'))),
           'venues', case when jsonb_array_length(places) = 0 then null
                          else jsonb_build_array(places -> ((i - 1) % jsonb_array_length(places))) end,
           'shared_venues', 0,
           'is_friend', false,
           'friend_request', null)
         order by i)
    into samples
  from generate_series(1, 20 - have) i;

  return found || coalesce(samples, '[]'::jsonb);
end
$$;

-- 跳过示例：不记录，也不报错（示例没有账号，记不了）
create or replace function public.skip_nearby(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if public.is_sample_player(p_user) then return; end if;
  if p_user is null or p_user = me or not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  insert into public.nearby_skips (user_id, skipped_id) values (me, p_user)
    on conflict (user_id, skipped_id) do update set created_at = now();
end
$$;

revoke execute on function public.nearby_players(double precision, double precision, double precision),
  public.nearby_real_players(double precision, double precision, double precision), public.is_sample_player(uuid)
  from public, anon;
grant execute on function public.nearby_players(double precision, double precision, double precision),
  public.nearby_real_players(double precision, double precision, double precision), public.is_sample_player(uuid)
  to authenticated;
