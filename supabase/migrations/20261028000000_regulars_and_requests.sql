-- 同馆常客和球群消息请求（和 iOS 一致，Badie-iOS/docs/DESIGN.md §12）：
-- - 同馆常客：本人开启才出现，只给收藏了同一家球馆的人看；只有昵称、等级和球馆，没有时间和位置
-- - 同一个球群的人可以发一条纯文字的消息请求（不能带链接或联系方式），对方接受或回复后才能继续聊；
--   忽略的话对方不会知道。打满 3 场才能发，每天最多 10 条；收到的一方可以关掉
-- 球馆的“人常去”用已有的 venue_regular_counts 视图

alter table public.profiles
  add column show_as_regular boolean not null default false,
  add column allow_message_requests boolean not null default true;
grant update (show_as_regular, allow_message_requests) on public.profiles to authenticated;

create table public.message_requests (
  from_id uuid not null references auth.users (id) on delete cascade,
  to_id uuid not null references auth.users (id) on delete cascade,
  group_id uuid references public.play_groups (id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  ignored_at timestamptz,
  primary key (from_id, to_id),
  check (from_id <> to_id)
);

create index message_requests_to_idx on public.message_requests (to_id);

alter table public.message_requests enable row level security;
revoke all on public.message_requests from anon, authenticated;
grant all on public.message_requests to service_role;

-- 常客可以被收藏了同一家球馆的人点开资料
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
$$;

-- 同馆常客：收藏了同一家球馆、开启了常客显示的人，共同球馆多的在前，最多 20 位
create function public.venue_regulars()
returns jsonb language sql stable security definer set search_path = '' as $$
  with shared as (
    select f.user_id, count(*) as shared, (array_agg(f.venue_id order by f.venue_id))[1] as venue_id
    from public.favorite_venues f
    where f.user_id <> auth.uid() and f.venue_id in (select venue_id from public.favorite_venues where user_id = auth.uid())
    group by f.user_id),
  listed as (
    select s.*, p.nickname, p.rating from shared s join public.profiles p on p.id = s.user_id
    where p.show_as_regular and not public.hidden_from(auth.uid(), s.user_id)
    order by s.shared desc, lower(p.nickname) limit 20)
  select coalesce(jsonb_agg(jsonb_build_object('id', l.user_id, 'nickname', l.nickname, 'rating', l.rating,
                                               'venue', jsonb_build_object('id', v.id, 'name', v.name))
                            order by l.shared desc, lower(l.nickname)), '[]')
  from listed l join public.venues v on v.id = l.venue_id
$$;

-- 我能不能给 TA 发私信：friends / open（请求已接受，或 TA 发来请求等我回）/ requested（我发了，等 TA 接受）/
-- request（同球群，可以发一条请求）/ new_account（同球群，但我还没打满 3 场）/ none（先加好友）
create function public.message_option(p_viewer uuid, p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case
    when p_viewer = p_user or public.blocked_between(p_viewer, p_user) then jsonb_build_object('status', 'none')
    when public.are_friends(p_viewer, p_user) then jsonb_build_object('status', 'friends')
    when exists (select 1 from public.message_requests r
                 where (r.from_id = p_user and r.to_id = p_viewer) or (r.from_id = p_viewer and r.to_id = p_user and r.accepted_at is not null))
      then jsonb_build_object('status', 'open')
    when exists (select 1 from public.message_requests r where r.from_id = p_viewer and r.to_id = p_user)
      then jsonb_build_object('status', 'requested')
    when g.id is null or not p.allow_message_requests then jsonb_build_object('status', 'none')
    when (select a.games_played from public.attendance_record(p_viewer) a) < 3 then jsonb_build_object('status', 'new_account', 'group', g.name)
    else jsonb_build_object('status', 'request', 'group', g.name, 'group_id', g.id)
  end
  from public.profiles p
  left join lateral (
    select pg.id, pg.name from public.play_groups pg
    join public.group_members x on x.group_id = pg.id and x.user_id = p_viewer and not x.pending
    join public.group_members y on y.group_id = pg.id and y.user_id = p_user and not y.pending
    order by lower(pg.name) limit 1) g on true
  where p.id = p_user
$$;

-- 私信：open 能发，request 能发一条请求，requested 等对方接受，closed 只能看，null 看不了
create or replace function public.thread_access(p_kind text, p_id uuid, p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'game' then (
      select case when g.status = 'scheduled' and now() <= g.ends_at + interval '48 hours' then 'open' else 'closed' end
      from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = p_user where g.id = p_id)
    when 'group' then case when public.group_role_of(p_id, p_user) in ('owner', 'organizer', 'member') then 'open' end
    when 'dm' then (
      select case o ->> 'status'
        when 'friends' then 'open' when 'open' then 'open' when 'requested' then 'requested' when 'request' then 'request'
        else case when exists (select 1 from public.messages where thread = 'dm:' || least(p_user, p_id) || ':' || greatest(p_user, p_id))
                  then 'closed' end
        end
      from public.message_option(p_user, p_id) o)
    end
$$;

create or replace function public.send_message(p_kind text, p_id uuid, p_body text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  key text := public.thread_key(p_kind, p_id);
  access text := public.thread_access(p_kind, p_id, me);
  content text := btrim(p_body);
  new_id bigint;
begin
  if me is null or access is null or access = 'closed' then raise exception 'chat_closed' using errcode = '42501'; end if;
  if access = 'requested' then raise exception 'request_pending' using errcode = '22023'; end if;
  if content is null or char_length(content) not between 1 and 1000 then raise exception 'invalid_message' using errcode = '22023'; end if;
  if (select count(*) from public.messages where sender_id = me and created_at > now() - interval '1 minute') >= 20
     or (select count(*) from public.messages where sender_id = me and created_at > now() - interval '1 day') >= 500 then
    raise exception 'too_many_messages' using errcode = '54000';
  end if;
  if access = 'request' then
    if content ~* '(https?:|www\.|@|\d{7,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
    if (select count(*) from public.message_requests where from_id = me and created_at > now() - interval '1 day') >= 10 then
      raise exception 'too_many_message_requests' using errcode = '54000';
    end if;
    insert into public.message_requests (from_id, to_id, group_id)
      values (me, p_id, (public.message_option(me, p_id) ->> 'group_id')::uuid);
    perform public.notify(p_id, 'message_request', '{name} wants to chat',
                          'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.',
                          '/app/messages/dm/' || me || '/',
                          jsonb_build_object('name', (select nickname from public.profiles where id = me),
                                             'group', (select pg.name from public.play_groups pg join public.message_requests r on r.group_id = pg.id
                                                       where r.from_id = me and r.to_id = p_id)));
  elsif p_kind = 'dm' then
    -- 回复对方的请求就算接受
    update public.message_requests set accepted_at = now(), ignored_at = null where from_id = p_id and to_id = me and accepted_at is null;
  end if;
  insert into public.messages (thread, sender_id, body) values (key, me, content) returning id into new_id;
  insert into public.thread_reads as r (user_id, thread, last_read_id) values (me, key, new_id)
    on conflict on constraint thread_reads_pkey do update set last_read_id = excluded.last_read_id;
  return new_id;
end
$$;

-- 收到的消息请求：接受，或者忽略（只是不再显示，对方仍看到“等待接受”）
create function public.respond_message_request(p_user uuid, p_accept boolean)
returns void language sql security definer set search_path = '' as $$
  update public.message_requests
    set accepted_at = case when p_accept then now() end, ignored_at = case when p_accept then null else now() end
    where from_id = p_user and to_id = auth.uid() and accepted_at is null
$$;

-- 打开会话：加上消息请求的状态（incoming = TA 发给我的，outgoing = 我发的，都还没接受）
create or replace function public.open_thread(p_kind text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  key text := public.thread_key(p_kind, p_id);
  access text := public.thread_access(p_kind, p_id, me);
  result jsonb;
begin
  if me is null or access is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  select jsonb_build_object(
    'access', access,
    'friend', p_kind = 'dm' and public.are_friends(me, p_id),
    'request', case when p_kind = 'dm' then public.request_direction(me, p_id) end,
    'group_name', case when access = 'request' then public.message_option(me, p_id) ->> 'group' end,
    'game', (select jsonb_build_object('starts_at', g.starts_at, 'ends_at', g.ends_at, 'venue', v.name, 'tz', v.time_zone_id)
             from public.games g join public.venues v on v.id = g.venue_id where p_kind = 'game' and g.id = p_id),
    'group', (select jsonb_build_object('name', g.name, 'venue', v.name)
              from public.play_groups g join public.venues v on v.id = g.venue_id where p_kind = 'group' and g.id = p_id),
    'members', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'me', p.id = me) order by p.id = me, lower(p.nickname))
                from public.profiles p
                where (p_kind = 'game' and p.id in (select user_id from public.game_players where game_id = p_id))
                   or (p_kind = 'group' and p.id in (select user_id from public.group_members where group_id = p_id and not pending))
                   or (p_kind = 'dm' and p.id in (me, p_id))),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'created_at', m.created_at,
                                                             'sender', m.sender_id, 'mine', m.sender_id = me) order by m.id)
                          from (select * from public.messages where thread = key order by id desc limit 200) m), '[]'))
    into result;
  insert into public.thread_reads (user_id, thread, last_read_id)
    select me, key, max(id) from public.messages where thread = key having max(id) is not null
    on conflict on constraint thread_reads_pkey do update set last_read_id = excluded.last_read_id;
  return result;
end
$$;

create function public.request_direction(p_viewer uuid, p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case when exists (select 1 from public.message_requests where from_id = p_user and to_id = p_viewer and accepted_at is null) then 'incoming'
              when exists (select 1 from public.message_requests where from_id = p_viewer and to_id = p_user and accepted_at is null) then 'outgoing' end
$$;

-- 会话列表：私信除了球友，还有消息请求（我发出的，和别人发给我、我没忽略的）
create or replace function public.my_threads()
returns jsonb language sql stable security definer set search_path = '' as $$
  with others as (
    select case when f.user_a = auth.uid() then f.user_b else f.user_a end as id
    from public.friendships f where auth.uid() in (f.user_a, f.user_b)
    union
    select case when r.from_id = auth.uid() then r.to_id else r.from_id end
    from public.message_requests r where r.from_id = auth.uid() or (r.to_id = auth.uid() and r.ignored_at is null)),
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
    select 'dm', p.id, 'dm:' || least(auth.uid(), p.id) || ':' || greatest(auth.uid(), p.id), null, null, null, p.nickname,
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
  where (t.kind in ('game', 'group') and t.access = 'open') or exists (select 1 from public.messages m where m.thread = t.thread)
$$;

-- 资料页：加上能不能私信（不带球群 id）
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id')
  from public.player_card_base(p_user) base, public.win_rate(p_user) w
  where base is not null
$$;

revoke execute on function public.message_option(uuid, uuid), public.request_direction(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.venue_regulars(), public.respond_message_request(uuid, boolean) from public, anon;
grant execute on function public.venue_regulars(), public.respond_message_request(uuid, boolean) to authenticated;

insert into public.notification_texts (locale, english, translated) values
  ('zh-Hans', '{name} wants to chat', '{name} 想和你聊天'),
  ('zh-Hans', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', '你们都在「{group}」。回复或接受后就能继续聊；忽略的话对方不会知道。'),
  ('zh-Hant', '{name} wants to chat', '{name} 想和你聊天'),
  ('zh-Hant', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', '你們都在「{group}」。回覆或接受後就能繼續聊；忽略的話對方不會知道。'),
  ('ja', '{name} wants to chat', '{name}さんがメッセージを送りたがっています'),
  ('ja', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', 'どちらも「{group}」のメンバーです。返信するか承認するとやり取りを続けられます。無視しても相手には伝わりません。'),
  ('ko', '{name} wants to chat', '{name}님이 대화를 원해요'),
  ('ko', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', '둘 다 {group}에 있어요. 답장하거나 수락하면 계속 대화할 수 있어요. 무시해도 상대방은 알 수 없어요.'),
  ('id', '{name} wants to chat', '{name} ingin mengobrol'),
  ('id', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', 'Kalian sama-sama di {group}. Balas atau terima untuk lanjut mengobrol. Kalau kamu abaikan, mereka tidak akan tahu.'),
  ('ms', '{name} wants to chat', '{name} mahu berbual'),
  ('ms', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', 'Anda berdua dalam {group}. Balas atau terima untuk terus berbual. Jika anda abaikan, mereka tidak akan tahu.'),
  ('th', '{name} wants to chat', '{name} อยากคุยกับคุณ'),
  ('th', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', 'คุณทั้งคู่อยู่ใน {group} ตอบกลับหรือยอมรับเพื่อคุยต่อ ถ้าคุณเพิกเฉย อีกฝ่ายจะไม่รู้'),
  ('vi', '{name} wants to chat', '{name} muốn trò chuyện'),
  ('vi', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', 'Hai bạn cùng ở {group}. Trả lời hoặc chấp nhận để tiếp tục trò chuyện. Nếu bạn bỏ qua, họ sẽ không biết.'),
  ('hi', '{name} wants to chat', '{name} आपसे बात करना चाहते हैं'),
  ('hi', 'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.', 'आप दोनों {group} में हैं। बात जारी रखने के लिए जवाब दें या स्वीकार करें। अनदेखा करने पर उन्हें पता नहीं चलेगा।');
