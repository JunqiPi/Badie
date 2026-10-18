-- 按昵称搜球友：只搜得到愿意被搜到的人（资料里的开关，默认开启，和上榜一样可以随时关）。
-- - 昵称开头匹配（不分大小写），至少 2 个字，最多 10 个结果；完全一样的、共同球友多的排前面
-- - 屏蔽关系双方互相搜不到；每人每 10 分钟最多搜 30 次，防止被整体爬取
-- - 搜到的人可以看资料、加球友、屏蔽和举报（好友申请仍是每天最多 20 个）

alter table public.profiles add column discoverable boolean not null default true;
grant update (discoverable) on public.profiles to authenticated;

-- 有交集，或者对方允许被搜到：可以看资料、加球友、拉黑、举报、发挑战（挑战另看对方的设置）
create or replace function public.related(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select a = b or public.are_friends(a, b)
    or exists (select 1 from public.game_players x join public.game_players y on y.game_id = x.game_id
               where x.user_id = a and y.user_id = b)
    or exists (select 1 from public.match_seats x join public.match_seats y on y.offer_id = x.offer_id
               where x.user_id = a and y.user_id = b)
    or exists (select 1 from public.friend_requests where (from_id = a and to_id = b) or (from_id = b and to_id = a))
    or exists (select 1 from public.group_members x join public.group_members y on y.group_id = x.group_id
               where x.user_id = a and y.user_id = b and not x.pending and not y.pending)
    or exists (select 1 from public.profiles where id = b and discoverable)
$$;

create table public.player_searches (
  user_id uuid not null references auth.users (id) on delete cascade,
  searched_at timestamptz not null default now()
);
create index player_searches_user_idx on public.player_searches (user_id, searched_at);
alter table public.player_searches enable row level security;
revoke all on public.player_searches from anon, authenticated;
grant all on public.player_searches to service_role;

create function public.find_players(p_query text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  q text := lower(btrim(coalesce(p_query, '')));
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if char_length(q) not between 2 and 12 then return '[]'::jsonb; end if;
  delete from public.player_searches where user_id = me and searched_at < now() - interval '10 minutes';
  if (select count(*) from public.player_searches where user_id = me) >= 30 then
    raise exception 'too_many_searches' using errcode = '54000';
  end if;
  insert into public.player_searches (user_id) values (me);

  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x.id, 'nickname', x.nickname, 'rating', x.rating, 'mutual_friends', x.mutual,
                                        'relationship', x.relationship) order by x.exact desc, x.mutual desc, lower(x.nickname))
    from (select p.id, p.nickname, p.rating, lower(p.nickname) = q as exact,
                 (select count(*) from (
                    select case when user_a = me then user_b else user_a end as f from public.friendships where me in (user_a, user_b)
                    intersect
                    select case when user_a = p.id then user_b else user_a end from public.friendships where p.id in (user_a, user_b)) m) as mutual,
                 case when public.are_friends(me, p.id) then 'friend'
                      when exists (select 1 from public.friend_requests where from_id = me and to_id = p.id) then 'requested'
                      when exists (select 1 from public.friend_requests where from_id = p.id and to_id = me and ignored_at is null) then 'incoming'
                      else 'none' end as relationship
          from public.profiles p
          where p.discoverable and p.id <> me and not public.blocked_between(me, p.id)
            and lower(p.nickname) like replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%'
          order by lower(p.nickname) = q desc, lower(p.nickname)
          limit 10) x), '[]');
end
$$;

revoke execute on function public.find_players(text) from public, anon;
grant execute on function public.find_players(text) to authenticated;
