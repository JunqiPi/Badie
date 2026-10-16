-- 第一块：用户资料 + 共享球馆库
--
-- 规则与 iOS 版 MockBackend+Venues.swift 一致：
-- - 球馆只能通过 add_venue() 加入：先查重（Apple Place ID / 200 米内名称相近），每人每天最多 3 家
-- - 新球馆“待确认”，3 位不同球友确认（或签到打过球）后变“球友确认”
-- - 待确认的球馆被 2 位以上不同球友报告问题时暂时隐藏（添加者本人仍可见），等人工审核
-- - 客户端不能直接写 venues 表，所有写入走下面的函数

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

-- ---------------------------------------------------------------------------
-- 用户资料（auth.users 之外的公开信息）
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null check (char_length(nickname) between 2 and 12),
  country_code char(2),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are readable by signed-in users"
  on public.profiles for select to authenticated using (true);

create policy "users insert their own profile"
  on public.profiles for insert to authenticated with check (id = (select auth.uid()));

create policy "users update their own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 球馆
-- ---------------------------------------------------------------------------

create type public.venue_source as enum ('curated', 'apple_maps', 'player', 'open_street_map', 'open_data');
create type public.venue_status as enum ('verified', 'confirmed', 'unconfirmed');
create type public.coordinate_datum as enum ('wgs84', 'gcj02');

create table public.venues (
  id text primary key default 'v-' || substr(md5(gen_random_uuid()::text), 1, 8),
  name text not null check (char_length(name) between 2 and 60),
  aliases text[] not null default '{}',
  location extensions.geography (point, 4326) not null,
  datum public.coordinate_datum not null default 'wgs84',
  -- 结构化地址，与 iOS PostalAddress 同字段
  street text not null,
  unit text,
  city text not null,
  region text not null default '',
  postal_code text not null default '',
  country_code char(2) not null,
  time_zone_id text,
  apple_place_id text,
  alternate_place_ids text[] not null default '{}',
  court_count int check (court_count is null or court_count >= 1),
  -- {"kind":"perCourtHour","amount":80} / {"kind":"dropIn","amount":15} / null
  pricing jsonb,
  pricing_note text,
  currency_code char(3),
  phone text,
  website text,
  entrance_note text check (entrance_note is null or char_length(entrance_note) <= 80),
  amenities text[] not null default '{}',
  -- {"open":"08:00","close":"22:00","days":[1,2,3,4,5,6,7]}
  operating_hours jsonb,
  source public.venue_source not null,
  -- 开放数据的许可证与署名；公开网页只展示 source 允许再发布的信息（见 docs/BACKEND.md §3.5）
  license text,
  attribution text,
  status public.venue_status not null default 'unconfirmed',
  added_by uuid references auth.users (id) on delete set null,
  last_confirmed_at timestamptz,
  merged_into text references public.venues (id),
  review_flag text,
  hidden_pending_review boolean not null default false,
  created_at timestamptz not null default now()
);

create index venues_location_idx on public.venues using gist (location);
create unique index venues_apple_place_id_idx on public.venues (apple_place_id)
  where apple_place_id is not null and merged_into is null;
create index venues_added_by_idx on public.venues (added_by, created_at);

create table public.venue_confirmations (
  venue_id text not null references public.venues (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  confirmed_at timestamptz not null default now(),
  primary key (venue_id, user_id)
);

create type public.venue_issue as enum ('wrong_location', 'closed', 'duplicate', 'not_badminton', 'other');

create table public.venue_reports (
  id bigint generated always as identity primary key,
  venue_id text not null references public.venues (id) on delete cascade,
  reporter_id uuid not null references auth.users (id) on delete cascade,
  issue public.venue_issue not null,
  detail text not null default '' check (char_length(detail) <= 200),
  created_at timestamptz not null default now()
);

create index venue_reports_venue_idx on public.venue_reports (venue_id);

create table public.favorite_venues (
  user_id uuid not null references auth.users (id) on delete cascade,
  venue_id text not null references public.venues (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, venue_id)
);

alter table public.venues enable row level security;
alter table public.venue_confirmations enable row level security;
alter table public.venue_reports enable row level security;
alter table public.favorite_venues enable row level security;

-- 球馆对所有人可见（含未登录：公开网页要用），被举报待审的只有添加者能看到
create policy "venues are public unless hidden for review"
  on public.venues for select to anon, authenticated
  using (not hidden_pending_review or added_by = (select auth.uid()));

create policy "users see their own confirmations"
  on public.venue_confirmations for select to authenticated using (user_id = (select auth.uid()));

-- 举报只写不读（通过 report_venue），审核在后台进行

create policy "users manage their own favorites"
  on public.favorite_venues for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- 公开的“常去人数”，不暴露是谁收藏的
create view public.venue_regular_counts with (security_invoker = false) as
  select venue_id, count(*)::int as regulars from public.favorite_venues group by venue_id;

grant select on public.venue_regular_counts to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 名称相似度（服务端兜底；客户端另有更细的规则，含拼音与英文缩写）
-- ---------------------------------------------------------------------------

create function public.normalize_venue_name(value text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select trim(regexp_replace(lower(extensions.unaccent(coalesce(value, ''))), '[^[:alnum:]]+', ' ', 'g'))
$$;

-- 去掉“羽毛球馆 / badminton / center”等通用词后的核心名称
create function public.venue_name_core(value text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select regexp_replace(
    replace(public.normalize_venue_name(value), ' ', ''),
    '(badminton|club|center|centre|court|courts|sports|sport|hall|gym|academy|the|羽毛球馆|羽毛球|羽球館|羽球馆|体育馆|體育館|体育中心|運動中心|运动中心|中心|俱乐部|球馆|球館|场馆|バドミントン|배드민턴)',
    '', 'g')
$$;

create function public.venue_names_similar(a text, b text)
returns boolean language sql immutable parallel safe set search_path = '' as $$
  select case
    when public.normalize_venue_name(a) = public.normalize_venue_name(b) then true
    when char_length(public.venue_name_core(a)) >= 2 and char_length(public.venue_name_core(b)) >= 2
      and (strpos(public.venue_name_core(a), public.venue_name_core(b)) > 0
        or strpos(public.venue_name_core(b), public.venue_name_core(a)) > 0) then true
    else extensions.similarity(public.normalize_venue_name(a), public.normalize_venue_name(b)) >= 0.5
  end
$$;

-- ---------------------------------------------------------------------------
-- 查询
-- ---------------------------------------------------------------------------

-- 半径内的球馆，按距离排序（RLS 照常生效）
create function public.venues_near(lat double precision, lng double precision, radius_km double precision,
                                   max_results int default 100)
returns table (venue public.venues, distance_m double precision)
language sql stable set search_path = '' as $$
  select v, extensions.st_distance(v.location, extensions.st_makepoint(lng, lat)::extensions.geography)
  from public.venues v
  where v.merged_into is null
    and extensions.st_dwithin(v.location, extensions.st_makepoint(lng, lat)::extensions.geography,
                              least(radius_km, 100) * 1000)
  order by 2
  limit least(max_results, 200)
$$;

-- 可能重复的已有球馆：same_place（Place ID 相同）/ likely（200 米内名称相近）/ same_building（40 米内）
create function public.venue_duplicates(name text, lat double precision, lng double precision,
                                        apple_place_id text default null, alternate_place_ids text[] default '{}')
returns table (venue_id text, venue_name text, kind text, distance_m double precision)
language sql stable set search_path = '' as $$
  with candidates as (
    select v.id, v.name, v.aliases, v.apple_place_id,
           extensions.st_distance(v.location, extensions.st_makepoint(lng, lat)::extensions.geography) as meters
    from public.venues v
    where v.merged_into is null
      and (extensions.st_dwithin(v.location, extensions.st_makepoint(lng, lat)::extensions.geography, 200)
           or (v.apple_place_id is not null
               and v.apple_place_id = any (array_append(coalesce(alternate_place_ids, '{}'), apple_place_id))))
  ), classified as (
    select id, name, meters,
      case
        when apple_place_id is not null
          and apple_place_id = any (array_append(coalesce(venue_duplicates.alternate_place_ids, '{}'),
                                                 venue_duplicates.apple_place_id)) then 'same_place'
        when meters <= 200 and (public.venue_names_similar(venue_duplicates.name, candidates.name)
          or exists (select 1 from unnest(aliases) alias where public.venue_names_similar(venue_duplicates.name, alias)))
          then 'likely'
        when meters <= 40 then 'same_building'
      end as kind
    from candidates
  )
  select id, name, kind, meters from classified where kind is not null
  order by case kind when 'same_place' then 0 when 'likely' then 1 else 2 end, meters
$$;

-- ---------------------------------------------------------------------------
-- 写入（客户端只能调这些函数）
-- ---------------------------------------------------------------------------

create function public.add_venue(
  name text, lat double precision, lng double precision,
  street text, city text, region text, postal_code text, country_code text,
  unit text default null, time_zone_id text default null,
  apple_place_id text default null, alternate_place_ids text[] default '{}',
  source public.venue_source default 'player', datum public.coordinate_datum default 'wgs84',
  aliases text[] default '{}', court_count int default null, entrance_note text default null,
  phone text default null, website text default null
)
returns public.venues
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  clean_name text := trim(name);
  dup record;
  neighbor text;
  result public.venues;
begin
  if me is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if char_length(clean_name) not between 2 and 60 then
    raise exception 'venue_name_invalid' using errcode = '22023';
  end if;
  if coalesce(trim(street), '') = '' or coalesce(trim(city), '') = '' then
    raise exception 'venue_address_incomplete' using errcode = '22023';
  end if;
  if source not in ('player', 'apple_maps') then
    raise exception 'source_not_allowed' using errcode = '42501';
  end if;

  for dup in select * from public.venue_duplicates(clean_name, lat, lng, apple_place_id, alternate_place_ids) loop
    if dup.kind = 'same_place' then
      select * into result from public.venues where id = dup.venue_id;
      return result;
    elsif dup.kind = 'likely' then
      raise exception 'venue_duplicate' using errcode = '23505', detail = dup.venue_name;
    elsif neighbor is null then
      neighbor := dup.venue_name;
    end if;
  end loop;

  if (select count(*) from public.venues v where v.added_by = me and v.created_at > now() - interval '24 hours') >= 3 then
    raise exception 'venue_rate_limited' using errcode = '54000';
  end if;

  insert into public.venues (
    id, name, aliases, location, datum, street, unit, city, region, postal_code, country_code, time_zone_id,
    apple_place_id, alternate_place_ids, court_count, entrance_note, phone, website, source, status,
    added_by, last_confirmed_at, review_flag
  ) values (
    case when apple_place_id is not null and apple_place_id <> ''
              and not exists (select 1 from public.venues v where v.id = 'v-ap-' || apple_place_id)
         then 'v-ap-' || apple_place_id
         else 'v-' || substr(md5(gen_random_uuid()::text), 1, 8) end,
    clean_name,
    coalesce((select array_agg(distinct trim(a) order by trim(a)) from unnest(aliases) a
              where trim(a) <> '' and trim(a) <> clean_name), '{}'),
    extensions.st_makepoint(lng, lat)::extensions.geography,
    datum, trim(street), nullif(trim(unit), ''), trim(city), coalesce(trim(region), ''),
    coalesce(trim(postal_code), ''), upper(country_code), time_zone_id,
    nullif(apple_place_id, ''), coalesce(alternate_place_ids, '{}'),
    case when court_count is null then null else greatest(1, court_count) end,
    nullif(left(trim(entrance_note), 80), ''), phone, website, source, 'unconfirmed',
    me, now(), case when neighbor is not null then '同一栋楼已有：' || neighbor end
  ) returning * into result;

  insert into public.venue_confirmations (venue_id, user_id) values (result.id, me);
  return result;
end
$$;

-- 记录确认，够 3 人后“待确认”升级为“球友确认”（签到打过球也会调用它）
create function public.record_venue_confirmation(target text, user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.venue_confirmations (venue_id, user_id) values (target, user_id)
    on conflict do nothing;
  update public.venues v set
    last_confirmed_at = now(),
    status = case
      when v.status = 'unconfirmed'
        and (select count(*) from public.venue_confirmations c where c.venue_id = target) >= 3 then 'confirmed'
      else v.status end
  where v.id = target;
end
$$;

revoke execute on function public.record_venue_confirmation(text, uuid) from public, anon, authenticated;

create function public.confirm_venue(target text)
returns public.venues language plpgsql security definer set search_path = '' as $$
declare
  result public.venues;
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if not exists (select 1 from public.venues where id = target) then
    raise exception 'venue_not_found' using errcode = 'P0002';
  end if;
  perform public.record_venue_confirmation(target, auth.uid());
  select * into result from public.venues where id = target;
  return result;
end
$$;

create function public.report_venue(target text, issue public.venue_issue, detail text default '')
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if not exists (select 1 from public.venues where id = target) then
    raise exception 'venue_not_found' using errcode = 'P0002';
  end if;
  insert into public.venue_reports (venue_id, reporter_id, issue, detail)
    values (target, auth.uid(), issue, left(coalesce(detail, ''), 200));
  update public.venues v set hidden_pending_review = true
  where v.id = target and v.status = 'unconfirmed'
    and (select count(distinct r.reporter_id) from public.venue_reports r where r.venue_id = target) >= 2;
end
$$;

revoke execute on function public.add_venue from public, anon;
revoke execute on function public.confirm_venue from public, anon;
revoke execute on function public.report_venue from public, anon;
grant execute on function public.add_venue to authenticated;
grant execute on function public.confirm_venue to authenticated;
grant execute on function public.report_venue to authenticated;
