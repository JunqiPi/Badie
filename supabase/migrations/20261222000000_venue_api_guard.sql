-- 不让人通过接口直接整表读球馆表：用公开的 key 每次 1000 条，翻十几页就能拿走全部球馆。
-- 只能走有上限的查询：venues_near（100 公里内最多 200 家）、search_venues（最多 50 家）、venue_brief（一家）。
-- 从别的表带出球馆（favorite_venues?select=venues(...)）不受影响：那种请求的路径是别的表。
-- iPhone、安卓从来不直接读这张表；网站唯一一处（邀请里按 id 查球馆）改用 venue_brief。

create function public.venue_brief(p_id text)
returns table (id text, name text, city text, time_zone_id text)
language sql stable set search_path = '' as $$
  select v.id, v.name, v.city, v.time_zone_id from public.venues v where v.id = venue_brief.p_id
$$;
grant execute on function public.venue_brief(text) to anon, authenticated;

-- 每个接口请求进来前先跑这个（PostgREST 的 db_pre_request）。要保持简单：这里出错，所有请求都会失败
create function public.check_request()
returns void language plpgsql stable set search_path = '' as $$
begin
  if ltrim(coalesce(current_setting('request.path', true), ''), '/') = 'venues'
     and coalesce(current_setting('request.method', true), '') in ('GET', 'HEAD')
     and current_user in ('anon', 'authenticated') then
    raise exception using errcode = '42501', message = 'venues can only be read near a place or by search',
      hint = 'Use rpc/venues_near, rpc/search_venues or rpc/venue_brief';
  end if;
end;
$$;
grant execute on function public.check_request() to anon, authenticated;

alter role authenticator set pgrst.db_pre_request = 'public.check_request';
notify pgrst, 'reload config';
