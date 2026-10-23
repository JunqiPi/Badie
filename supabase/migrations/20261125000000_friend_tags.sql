-- 昵称#编号（像 Discord）：昵称可以重名，昵称 + 4 位编号不会重；搜“昵称#编号”精确找到这个人（仍只搜得到允许被搜到的人）。
-- 加球友链接：每人一个随机码，badie.rsvp/add/<码>/。打开链接的人可以看资料、加球友，对方关了被搜到也可以；
-- 重置链接后旧链接失效，只打开过、还没加球友的人也看不到了。

alter table public.profiles
  add column tag smallint check (tag between 1 and 9999),
  add column friend_code text unique check (friend_code ~ '^[a-hjkmnp-z2-9]{8}$');

-- 这个昵称下还空着的编号：先随机试，用得多了再从剩下的里挑
create function public.free_tag(p_nickname text, p_user uuid)
returns smallint language plpgsql volatile set search_path = '' as $$
declare
  candidate smallint;
  tries int := 0;
begin
  while tries < 20 loop
    candidate := 1 + floor(random() * 9999)::int;
    if not exists (select 1 from public.profiles
                   where lower(nickname) = lower(p_nickname) and tag = candidate and id is distinct from p_user) then
      return candidate;
    end if;
    tries := tries + 1;
  end loop;
  select s into candidate from generate_series(1, 9999) s
    where not exists (select 1 from public.profiles where lower(nickname) = lower(p_nickname) and tag = s and id is distinct from p_user)
    order by random() limit 1;
  if candidate is null then raise exception 'nickname_taken' using errcode = '23505'; end if;
  return candidate;
end
$$;

create function public.new_friend_code()
returns text language sql volatile set search_path = '' as $$
  select string_agg(substr('abcdefghjkmnpqrstuvwxyz23456789', 1 + floor(random() * 31)::int, 1), '') from generate_series(1, 8)
$$;

-- 注册和改昵称时：新昵称下编号被占了才换，没被占就沿用
create function public.assign_tag()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tag is null or exists (select 1 from public.profiles
                                where lower(nickname) = lower(new.nickname) and tag = new.tag and id <> new.id) then
    new.tag := public.free_tag(new.nickname, new.id);
  end if;
  if new.friend_code is null then new.friend_code := public.new_friend_code(); end if;
  return new;
end
$$;

-- 排在 profiles_name_filter 之后（按名字顺序），用的是过滤后的昵称
create trigger profiles_tag before insert or update of nickname on public.profiles
  for each row execute function public.assign_tag();

do $$
declare
  r record;
begin
  for r in select id, nickname from public.profiles where tag is null order by created_at loop
    update public.profiles set tag = public.free_tag(r.nickname, r.id), friend_code = public.new_friend_code() where id = r.id;
  end loop;
end
$$;

alter table public.profiles alter column tag set not null, alter column friend_code set not null;
create unique index profiles_handle_idx on public.profiles (lower(nickname), tag);

-- 打开过谁的加球友链接
create table public.friend_link_opens (
  viewer uuid not null references auth.users (id) on delete cascade,
  owner uuid not null references auth.users (id) on delete cascade,
  opened_at timestamptz not null default now(),
  primary key (viewer, owner)
);
create index friend_link_opens_owner_idx on public.friend_link_opens (owner);
alter table public.friend_link_opens enable row level security;
revoke all on public.friend_link_opens from anon, authenticated;
grant all on public.friend_link_opens to service_role;

-- 打开别人的加球友链接：返回对方的 ID（之后照常看资料、加球友）。和搜索共用限速，防止猜码
create function public.open_friend_link(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  target uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  delete from public.player_searches where user_id = me and searched_at < now() - interval '10 minutes';
  if (select count(*) from public.player_searches where user_id = me) >= 30 then
    raise exception 'too_many_searches' using errcode = '54000';
  end if;
  insert into public.player_searches (user_id) values (me);
  select id into target from public.profiles where friend_code = lower(btrim(coalesce(p_code, '')));
  if target is null or public.blocked_between(me, target) then return null; end if;
  if target <> me then
    insert into public.friend_link_opens (viewer, owner) values (me, target) on conflict do nothing;
  end if;
  return target;
end
$$;

-- 换一个新链接：旧链接失效，只打开过、还没加球友的人不再能看资料
create function public.reset_friend_code()
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  code text;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  update public.profiles set friend_code = public.new_friend_code() where id = me returning friend_code into code;
  delete from public.friend_link_opens where owner = me;
  return code;
end
$$;

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
$$;

-- 搜索：“昵称#编号”精确查找；只写昵称照旧按开头匹配。结果带上编号
create or replace function public.find_players(p_query text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  q text := lower(btrim(coalesce(p_query, '')));
  wanted smallint;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if q ~ '#\d{1,4}$' then
    wanted := substring(q from '#(\d{1,4})$')::int;
    q := btrim(regexp_replace(q, '#\d{1,4}$', ''));
  end if;
  if char_length(q) not between 2 and 12 then return '[]'::jsonb; end if;
  delete from public.player_searches where user_id = me and searched_at < now() - interval '10 minutes';
  if (select count(*) from public.player_searches where user_id = me) >= 30 then
    raise exception 'too_many_searches' using errcode = '54000';
  end if;
  insert into public.player_searches (user_id) values (me);

  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x.id, 'nickname', x.nickname, 'tag', x.tag, 'rating', x.rating,
                                        'mutual_friends', x.mutual, 'relationship', x.relationship)
                     order by x.exact desc, x.mutual desc, lower(x.nickname), x.tag)
    from (select p.id, p.nickname, p.tag, p.rating, lower(p.nickname) = q as exact,
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
            and case when wanted is null
                     then lower(p.nickname) like replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%'
                     else lower(p.nickname) = q and p.tag = wanted end
          order by lower(p.nickname) = q desc, lower(p.nickname), p.tag
          limit 10) x), '[]');
end
$$;

create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', pr.verified_kind,
    'avatar', pr.avatar_path,
    'gender', pr.gender,
    'tag', pr.tag)
  from public.player_card_base(p_user) base, public.win_rate(p_user) w, public.profiles pr
  where base is not null and pr.id = p_user
$$;

revoke execute on function public.free_tag(text, uuid), public.new_friend_code(), public.assign_tag()
  from public, anon, authenticated;
revoke execute on function public.open_friend_link(text), public.reset_friend_code() from public, anon;
grant execute on function public.open_friend_link(text), public.reset_friend_code() to authenticated;
