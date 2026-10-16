-- 管理员与球馆审核
--
-- - 管理员名单在 admin_users 表里，只能用 service_role（Supabase 后台 / SQL 编辑器）添加，App 里没有入口
-- - 所有审核操作走 admin_* 函数：函数里检查 is_admin()，并写一条 moderation_log（谁、什么时候、对什么、做了什么、为什么）
-- - 普通用户读不到审核队列和日志

create type public.admin_role as enum ('owner', 'moderator');

create table public.admin_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role public.admin_role not null default 'moderator',
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;
-- 不建任何策略：客户端无法读写，只能通过下面的函数判断身份

create function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid())
$$;

grant execute on function public.is_admin() to authenticated;

create table public.moderation_log (
  id bigint generated always as identity primary key,
  admin_id uuid not null references auth.users (id),
  target_type text not null,
  target_id text not null,
  action text not null,
  note text not null default '',
  created_at timestamptz not null default now()
);

create index moderation_log_target_idx on public.moderation_log (target_type, target_id);

alter table public.moderation_log enable row level security;

create policy "admins read the moderation log"
  on public.moderation_log for select to authenticated using ((select public.is_admin()));

create function public.require_admin()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
end
$$;

revoke execute on function public.require_admin() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 球馆审核队列：被举报的、被隐藏的、同一栋楼待复核的
-- ---------------------------------------------------------------------------

create function public.admin_venue_queue()
returns table (
  venue_id text, name text, city text, country_code text, status public.venue_status, source public.venue_source,
  review_flag text, hidden_pending_review boolean, report_count int, reporters int,
  latest_issues public.venue_issue[], added_by uuid, created_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_admin();
  return query
    select v.id, v.name, v.city, v.country_code::text, v.status, v.source, v.review_flag, v.hidden_pending_review,
           count(r.id)::int, count(distinct r.reporter_id)::int,
           (array_agg(distinct r.issue) filter (where r.id is not null)), v.added_by, v.created_at
    from public.venues v
    left join public.venue_reports r on r.venue_id = v.id and r.resolved_at is null
    where v.merged_into is null
    group by v.id
    having v.hidden_pending_review or v.review_flag is not null or count(r.id) > 0
    order by v.hidden_pending_review desc, count(distinct r.reporter_id) desc, v.created_at;
end
$$;

alter table public.venue_reports add column resolved_at timestamptz;

-- 处理一条球馆：
--   keep    信息无误：取消隐藏、清掉复核标记、举报记为已处理
--   verify  人工核实过：同上，并标为“已核实”
--   remove  不存在 / 不是羽毛球场地：隐藏（保留记录以便追溯）
create function public.admin_resolve_venue(target text, decision text, note text default '')
returns public.venues language plpgsql security definer set search_path = '' as $$
declare
  result public.venues;
begin
  perform public.require_admin();
  if decision not in ('keep', 'verify', 'remove') then
    raise exception 'unknown_decision' using errcode = '22023';
  end if;
  if not exists (select 1 from public.venues where id = target) then
    raise exception 'venue_not_found' using errcode = 'P0002';
  end if;

  update public.venues v set
    hidden_pending_review = (decision = 'remove'),
    review_flag = null,
    status = case when decision = 'verify' then 'verified' else v.status end
  where v.id = target
  returning * into result;

  update public.venue_reports set resolved_at = now() where venue_id = target and resolved_at is null;
  insert into public.moderation_log (admin_id, target_type, target_id, action, note)
    values (auth.uid(), 'venue', target, decision, left(coalesce(note, ''), 500));
  return result;
end
$$;

-- 合并重复条目：旧条目指向保留的球馆，名称记为别名，确认人与收藏转过去（与 MockBackend.mergeVenue 一致）
create function public.admin_merge_venue(duplicate text, keep text, note text default '')
returns public.venues language plpgsql security definer set search_path = '' as $$
declare
  dup public.venues;
  result public.venues;
begin
  perform public.require_admin();
  select * into dup from public.venues where id = duplicate;
  if dup.id is null or duplicate = keep or not exists (select 1 from public.venues where id = keep and merged_into is null) then
    raise exception 'venue_not_found' using errcode = 'P0002';
  end if;

  update public.venues v set aliases = (
    select coalesce(array_agg(distinct a order by a), '{}')
    from unnest(v.aliases || dup.aliases || array[dup.name]) a
    where a <> v.name
  ) where v.id = keep;

  insert into public.venue_confirmations (venue_id, user_id, confirmed_at)
    select keep, c.user_id, c.confirmed_at from public.venue_confirmations c where c.venue_id = duplicate
    on conflict do nothing;
  insert into public.favorite_venues (user_id, venue_id, created_at)
    select f.user_id, keep, f.created_at from public.favorite_venues f where f.venue_id = duplicate
    on conflict do nothing;
  delete from public.favorite_venues where venue_id = duplicate;

  update public.venues set merged_into = keep, apple_place_id = null where id = duplicate;
  update public.venues v set
    status = case when v.status = 'unconfirmed'
      and (select count(*) from public.venue_confirmations c where c.venue_id = keep) >= 3 then 'confirmed' else v.status end
  where v.id = keep;
  update public.venue_reports set resolved_at = now() where venue_id = duplicate and resolved_at is null;

  insert into public.moderation_log (admin_id, target_type, target_id, action, note)
    values (auth.uid(), 'venue', duplicate, 'merge:' || keep, left(coalesce(note, ''), 500));
  select * into result from public.venues where id = keep;
  return result;
end
$$;

revoke execute on function public.admin_venue_queue() from public, anon;
revoke execute on function public.admin_resolve_venue(text, text, text) from public, anon;
revoke execute on function public.admin_merge_venue(text, text, text) from public, anon;
grant execute on function public.admin_venue_queue() to authenticated;
grant execute on function public.admin_resolve_venue(text, text, text) to authenticated;
grant execute on function public.admin_merge_venue(text, text, text) to authenticated;

-- 管理员可以看到被隐藏的球馆（审核时要看详情）
drop policy "venues are public unless hidden for review" on public.venues;
create policy "venues are public unless hidden for review"
  on public.venues for select to anon, authenticated
  using (not hidden_pending_review or added_by = (select auth.uid()) or (select public.is_admin()));

-- 审核时要看谁确认过、谁举报过
create policy "admins read venue confirmations"
  on public.venue_confirmations for select to authenticated using ((select public.is_admin()));

create policy "admins read venue reports"
  on public.venue_reports for select to authenticated using ((select public.is_admin()));
