-- 新球友 7 天内没聊过也出现在会话列表；starts_at 给私信用作“成为球友的时间”，客户端按它排序
create or replace function public.my_threads()
returns jsonb language sql stable security definer set search_path = '' as $$
  with others as (
    select id, max(since) as since from (
      select case when f.user_a = auth.uid() then f.user_b else f.user_a end as id, f.created_at as since
      from public.friendships f where auth.uid() in (f.user_a, f.user_b)
      union all
      select case when r.from_id = auth.uid() then r.to_id else r.from_id end, null
      from public.message_requests r where r.from_id = auth.uid() or (r.to_id = auth.uid() and r.ignored_at is null)) x
    group by id),
  threads as (
    select 'game' as kind, g.id, 'game:' || g.id as thread, g.starts_at, v.name as venue, v.time_zone_id as tz, null::text as name,
           case when g.status = 'scheduled' and now() <= g.ends_at + interval '48 hours' then 'open' else 'closed' end as access
    from public.game_players gp join public.games g on g.id = gp.game_id join public.venues v on v.id = g.venue_id
    where gp.user_id = auth.uid() and g.ends_at > now() - interval '30 days'
    union all
    select 'group', g.id, 'group:' || g.id, null, v.name, v.time_zone_id, g.name, 'open'
    from public.group_members m join public.play_groups g on g.id = m.group_id join public.venues v on v.id = g.venue_id
    where m.user_id = auth.uid() and not m.pending
    union all
    select 'dm', p.id, 'dm:' || least(auth.uid(), p.id) || ':' || greatest(auth.uid(), p.id), o.since, null, null, p.nickname,
           coalesce(public.thread_access('dm', p.id, auth.uid()), 'closed')
    from others o join public.profiles p on p.id = o.id)
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'id', t.id, 'starts_at', t.starts_at, 'venue', t.venue, 'tz', t.tz, 'name', t.name, 'access', t.access,
      'request', case when t.kind = 'dm' then public.request_direction(auth.uid(), t.id) end,
      'last', (select jsonb_build_object('body', m.body, 'created_at', m.created_at, 'mine', m.sender_id = auth.uid()) from public.messages m
               where m.thread = t.thread order by m.id desc limit 1),
      'unread', (select count(*) from public.messages m where m.thread = t.thread and m.sender_id <> auth.uid()
                 and m.id > coalesce((select last_read_id from public.thread_reads r where r.user_id = auth.uid() and r.thread = t.thread), 0)))
    order by coalesce((select max(m.created_at) from public.messages m where m.thread = t.thread), t.starts_at, '-infinity') desc), '[]')
  from threads t
  where (t.kind in ('game', 'group') and t.access = 'open')
     or (t.kind = 'dm' and t.starts_at > now() - interval '7 days')
     or exists (select 1 from public.messages m where m.thread = t.thread)
$$;
