-- 不让人通过接口直接整表读球馆表：用公开的 key 每次 1000 条，翻十几页就能拿走全部球馆。
-- 只该走有上限的查询：venues_near（100 公里内最多 200 家）、search_venues（最多 50 家）、按 id 查（venue_brief、venues_by_ids）。
-- 从别的表带出球馆（favorite_venues?select=venues(...)）不受影响：那种请求的路径是别的表。
--
-- **检查函数先写好，还没启用**：安卓（android-v1.0.5-1 已发布）有 5 处直接 GET /venues?id=in.(…)，
-- 接口这一层分不出“按 id 查”和“整表翻页”。等安卓改用 venues_by_ids、装了旧包的人都更新了，
-- 再加一个迁移：alter role authenticator set pgrst.db_pre_request = 'public.check_request'; notify pgrst, 'reload config';
-- iPhone 从来不直接读这张表；网站唯一一处（邀请里按 id 查球馆）已改用 venue_brief。

create function public.venue_brief(p_id text)
returns table (id text, name text, city text, time_zone_id text)
language sql stable set search_path = '' as $$
  select v.id, v.name, v.city, v.time_zone_id from public.venues v where v.id = venue_brief.p_id
$$;
grant execute on function public.venue_brief(text) to anon, authenticated;

-- 按一组 id 查球馆（一次最多 100 家），给安卓替换直接读表用；行级权限照常
create function public.venues_by_ids(p_ids text[])
returns setof public.venues
language sql stable set search_path = '' as $$
  select v.* from public.venues v where v.id = any (venues_by_ids.p_ids[1:100])
$$;
grant execute on function public.venues_by_ids(text[]) to anon, authenticated;

-- 启用后每个接口请求进来前先跑这个（PostgREST 的 db_pre_request）。要保持简单：这里出错，所有请求都会失败
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

