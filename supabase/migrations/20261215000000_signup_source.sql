-- 等级卡片（Badie-iOS/docs/LEVEL_CARD.md §8）：注册时记下从哪个链接来的（?ref=card，不含个人信息），
-- 和“你从哪里知道 Badie 的”（可以不选）。建资料时写一次，之后不能改；和资料的其他字段一样只有本人读得到。
-- 看效果：SQL 编辑器里跑 select * from public.signup_sources();

alter table public.profiles
  add column ref text check (ref ~ '^[a-z0-9_-]{1,32}$'),
  add column heard_from text check (heard_from in ('friend', 'level_card', 'social', 'search', 'app_store', 'club', 'other'));

grant insert (ref, heard_from) on public.profiles to authenticated;

-- 按周数各来源的注册人数，以及其中做过定级问卷的人数
create function public.signup_sources()
returns table (week date, ref text, heard_from text, signups bigint, assessed bigint)
language sql stable security definer set search_path = '' as $$
  select date_trunc('week', p.created_at)::date, p.ref, p.heard_from, count(*), count(*) filter (where p.assessed_at is not null)
  from public.profiles p
  group by 1, 2, 3
  order by 1 desc, 4 desc
$$;
revoke execute on function public.signup_sources() from public, anon, authenticated;
