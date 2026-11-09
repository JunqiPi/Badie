-- 首页按天看人的卡片：卡片上的人还没打过交道，原来看不到 TA 的资料和照片。
-- 对方正在找人、并且我能约 TA（没关掉被看到、水平和性别对得上、没拉黑）时也算有关系
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
    or exists (select 1 from public.profiles p join public.favorite_venues fb on fb.user_id = p.id
               join public.favorite_venues fa on fa.venue_id = fb.venue_id and fa.user_id = a
               where p.id = b and p.show_as_regular)
    or exists (select 1 from public.friend_link_opens where viewer = a and owner = b)
    -- 首页卡片：b 正在找人、a 能约 b，就能看 b 的资料（卡片上的照片和“看资料”）
    or exists (select 1 from public.match_tickets t
               where t.user_id = b and t.status = 'searching' and t.lock_at > now() and public.can_invite(a, t))
$$;
