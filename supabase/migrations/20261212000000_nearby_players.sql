-- 常在附近打的人：按天的卡片刷完以后，接着看常去附近球馆的人（不分日期）
-- - 只出现打开了“在同馆常客里显示我”（show_as_regular）的人；不出现自己、拉黑（任一方）、举报过的、已经是球友的、
--   我已经想约还在等回复的、30 天内我跳过的、30 天内拒绝过（任一方）的
-- - 右滑 = 想一起打：24 小时最多 10 个；对方也想和我打就直接成为球友，否则等对方回复（拒绝不告诉对方）
-- - 推荐时间：常用时间目前只存在手机上，服务器只推荐两人都常去的球馆，时间留空
-- 只能通过下面的函数读写

-- 喜欢单打还是双打（以前只存在手机上；null = 都行）
alter table public.profiles add column preferred_mode public.game_mode;
grant update (preferred_mode) on public.profiles to authenticated;

create table public.play_wishes (
  from_id uuid not null references auth.users (id) on delete cascade,
  to_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (from_id, to_id),
  check (from_id <> to_id)
);
create index play_wishes_to_idx on public.play_wishes (to_id, status);
create index play_wishes_from_created_idx on public.play_wishes (from_id, created_at);

create table public.nearby_skips (
  user_id uuid not null references auth.users (id) on delete cascade,
  skipped_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, skipped_id),
  check (user_id <> skipped_id)
);
create index nearby_skips_skipped_idx on public.nearby_skips (skipped_id);

alter table public.play_wishes enable row level security;
alter table public.nearby_skips enable row level security;
revoke all on public.play_wishes, public.nearby_skips from anon, authenticated;
grant all on public.play_wishes, public.nearby_skips to service_role;

-- 想一起打的人能互相看资料（卡片上的照片、“看资料”）
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
    -- 想一起打：还在等回复
    or exists (select 1 from public.play_wishes w
               where w.status = 'pending' and ((w.from_id = a and w.to_id = b) or (w.from_id = b and w.to_id = a)))
$$;

-- 卡片上的人：和 day_candidates 的 user 一样，多一个 preferred_mode
create function public.nearby_user(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'tag', p.tag, 'rating', p.rating, 'gender', p.gender,
                            'recent_no_shows', public.recent_no_shows(p.id), 'avatar', p.avatar_path,
                            'card_color', p.card_color, 'card_photo', p.card_photo_path, 'preferred_mode', p.preferred_mode)
  from public.profiles p where p.id = p_user
$$;

-- 30 天内有一方拒绝过（谁拒绝谁都算）
create function public.play_wish_cooldown(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.play_wishes w
                 where w.status = 'declined' and w.responded_at > now() - interval '30 days'
                   and ((w.from_id = a and w.to_id = b) or (w.from_id = b and w.to_id = a)))
$$;

-- a 能不能对 b 说想一起打
create function public.play_wish_allowed(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select a <> b
    and exists (select 1 from public.profiles p where p.id = b and p.show_as_regular)
    and not public.hidden_from(a, b) and not public.hidden_from(b, a)
    and not public.are_friends(a, b)
    and not public.play_wish_cooldown(a, b)
$$;

-- 推荐：两人都常去的球馆（a 最早收藏的那家）。常用时间不在服务器上，时间留空；没有共同球馆就是 null
create function public.play_suggestion(a uuid, b uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('venue_id', v.id, 'venue_name', v.name, 'starts_at', null::timestamptz, 'ends_at', null::timestamptz)
  from public.favorite_venues fa
  join public.favorite_venues fb on fb.venue_id = fa.venue_id and fb.user_id = b
  join public.venues v on v.id = fa.venue_id
  where fa.user_id = a
  order by fa.created_at, v.id
  limit 1
$$;

-- 成为球友：和接受好友请求一样建 friendships、清掉两人之间的好友请求；通知由调用的地方发
create function public.befriend(a uuid, b uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.friendships (user_a, user_b) values (least(a, b), greatest(a, b)) on conflict do nothing;
  delete from public.friend_requests where (from_id = a and to_id = b) or (from_id = b and to_id = a);
$$;

-- 常在附近：收藏的球馆在我附近的人；共同球馆多的在前，再按水平接近、离我近，最多 30 位
create function public.nearby_players(p_lat double precision, p_lon double precision, p_radius_km double precision)
returns jsonb language sql stable security definer set search_path = '' as $$
  with here as (
    select extensions.st_makepoint(p_lon, p_lat)::extensions.geography as g,
           (least(greatest(p_radius_km, 1), 100) * 1000)::double precision as m),
  me as (
    select p.id, public.open_rating(p.rating, p.gender) as level from public.profiles p where p.id = auth.uid()),
  near as (
    select f.user_id, v.id, v.name, extensions.st_distance(v.location, h.g) as dist
    from here h
    join public.venues v on extensions.st_dwithin(v.location, h.g, h.m)
    join public.favorite_venues f on f.venue_id = v.id
    where f.user_id <> auth.uid()),
  picked as (
    select p.id,
           (select count(*) from public.favorite_venues a join public.favorite_venues b on b.venue_id = a.venue_id and b.user_id = p.id
            where a.user_id = me.id)::int as shared,
           abs(public.open_rating(p.rating, p.gender) - me.level) as gap,
           (select min(n.dist) from near n where n.user_id = p.id) as nearest
    from me
    join public.profiles p on p.id in (select n.user_id from near n)
    where p.show_as_regular
      and not public.hidden_from(me.id, p.id) and not public.hidden_from(p.id, me.id)
      and not public.are_friends(me.id, p.id)
      and not public.play_wish_cooldown(me.id, p.id)
      and not exists (select 1 from public.play_wishes w where w.from_id = me.id and w.to_id = p.id and w.status = 'pending')
      and not exists (select 1 from public.nearby_skips s
                      where s.user_id = me.id and s.skipped_id = p.id and s.created_at > now() - interval '30 days')
    order by shared desc, gap, nearest, p.id
    limit 30)
  select coalesce(jsonb_agg(jsonb_build_object(
           'user', public.nearby_user(x.id),
           -- TA 收藏的、在我附近的球馆，近的在前
           'venues', (select jsonb_agg(jsonb_build_object('id', n.id, 'name', n.name, 'km', round((n.dist / 1000)::numeric, 1))
                                       order by n.dist, n.id)
                      from near n where n.user_id = x.id),
           'shared_venues', x.shared)
         order by x.shared desc, x.gap, x.nearest, x.id), '[]'::jsonb)
  from picked x
$$;

-- 左滑跳过：30 天内不再出现（再跳过一次重新计时）
create function public.skip_nearby(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_user is null or p_user = me or not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;
  insert into public.nearby_skips (user_id, skipped_id) values (me, p_user)
    on conflict (user_id, skipped_id) do update set created_at = now();
end
$$;

-- 右滑想一起打
create function public.wish_to_play(p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  sent int;
  mutual boolean;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_user is null then raise exception 'not_available' using errcode = 'P0002'; end if;
  -- 同一个人的右滑排队算个数；两个人同时互相右滑也只会走一次“互相想打”
  perform pg_advisory_xact_lock(hashtextextended('play_wish:' || me::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('play_wish:' || least(me, p_user)::text || ':' || greatest(me, p_user)::text, 0));
  if not (select p.show_as_regular from public.profiles p where p.id = me) then
    raise exception 'not_visible' using errcode = '22023';
  end if;
  if not public.play_wish_allowed(me, p_user) then raise exception 'not_available' using errcode = 'P0002'; end if;

  sent := (select count(*) from public.play_wishes where from_id = me and created_at > now() - interval '1 day')::int;
  -- 已经在等 TA 回复：什么都不做
  if exists (select 1 from public.play_wishes where from_id = me and to_id = p_user and status = 'pending') then
    return jsonb_build_object('mutual', false, 'remaining', greatest(10 - sent, 0), 'suggestion', null::jsonb);
  end if;

  mutual := exists (select 1 from public.play_wishes where from_id = p_user and to_id = me and status = 'pending');
  -- 对方已经想和我打：直接成为球友，不占用次数上限
  if not mutual and sent >= 10 then raise exception 'wish_limit' using errcode = '54000'; end if;

  insert into public.play_wishes (from_id, to_id, status, created_at, responded_at)
    values (me, p_user, case when mutual then 'accepted' else 'pending' end, now(), case when mutual then now() end)
    on conflict (from_id, to_id) do update
      set status = excluded.status, created_at = excluded.created_at, responded_at = excluded.responded_at;

  if mutual then
    update public.play_wishes set status = 'accepted', responded_at = now() where from_id = p_user and to_id = me;
    perform public.befriend(me, p_user);
    perform public.notify(p_user, 'play_wish_accepted', 'You both want to play',
      'You and {name} are now friends. Send a message to pick a time.', '/app/players/' || me || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me)));
    perform public.notify(me, 'play_wish_accepted', 'You both want to play',
      'You and {name} are now friends. Send a message to pick a time.', '/app/players/' || p_user || '/',
      jsonb_build_object('name', (select nickname from public.profiles where id = p_user)));
    return jsonb_build_object('mutual', true, 'remaining', greatest(9 - sent, 0), 'suggestion', public.play_suggestion(me, p_user));
  end if;

  perform public.notify(p_user, 'play_wish', '{name} wants to play with you', 'Say yes and you’ll be friends and can chat.',
    '/app/players/' || me || '/', jsonb_build_object('name', (select nickname from public.profiles where id = me)));
  return jsonb_build_object('mutual', false, 'remaining', greatest(9 - sent, 0), 'suggestion', null::jsonb);
end
$$;

-- 想和我打、还在等我回复的，新的在前
create function public.pending_play_wishes()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'from', public.nearby_user(w.from_id),
           'shared_venue', public.play_suggestion(auth.uid(), w.from_id) ->> 'venue_name',
           'created_at', w.created_at)
         order by w.created_at desc, w.from_id), '[]'::jsonb)
  from public.play_wishes w
  where w.to_id = auth.uid() and w.status = 'pending'
    and not public.hidden_from(auth.uid(), w.from_id) and not public.hidden_from(w.from_id, auth.uid())
    and not public.are_friends(auth.uid(), w.from_id)
$$;

-- 回复：同意就成为球友并告诉对方；不了就不告诉对方，30 天内两边都不再出现
create function public.respond_play_wish(p_from uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_from is null or p_accept is null then raise exception 'not_available' using errcode = 'P0002'; end if;
  perform pg_advisory_xact_lock(hashtextextended('play_wish:' || least(me, p_from)::text || ':' || greatest(me, p_from)::text, 0));
  perform 1 from public.play_wishes where from_id = p_from and to_id = me and status = 'pending' for update;
  if not found or public.hidden_from(me, p_from) or public.hidden_from(p_from, me) then
    raise exception 'not_available' using errcode = 'P0002';
  end if;

  if not p_accept then
    update public.play_wishes set status = 'declined', responded_at = now() where from_id = p_from and to_id = me;
    return jsonb_build_object('suggestion', null::jsonb);
  end if;

  update public.play_wishes set status = 'accepted', responded_at = now() where from_id = p_from and to_id = me;
  perform public.befriend(me, p_from);
  perform public.notify(p_from, 'play_wish_accepted', '{name} said yes to playing', 'You’re now friends. Send a message to pick a time.',
    '/app/players/' || me || '/', jsonb_build_object('name', (select nickname from public.profiles where id = me)));
  return jsonb_build_object('suggestion', public.play_suggestion(me, p_from));
end
$$;

revoke execute on function public.nearby_user(uuid), public.play_wish_cooldown(uuid, uuid), public.play_wish_allowed(uuid, uuid),
  public.play_suggestion(uuid, uuid), public.befriend(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.nearby_players(double precision, double precision, double precision), public.skip_nearby(uuid),
  public.wish_to_play(uuid), public.pending_play_wishes(), public.respond_play_wish(uuid, boolean) from public, anon;
grant execute on function public.nearby_players(double precision, double precision, double precision), public.skip_nearby(uuid),
  public.wish_to_play(uuid), public.pending_play_wishes(), public.respond_play_wish(uuid, boolean) to authenticated;

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', '{name} wants to play with you', '{name} 想和你打球'),
  ('zh-Hans', 'Say yes and you’ll be friends and can chat.', '同意后你们就是球友，可以聊天。'),
  ('zh-Hans', '{name} said yes to playing', '{name} 同意一起打球'),
  ('zh-Hans', 'You’re now friends. Send a message to pick a time.', '你们已经是球友了，发消息约个时间。'),
  ('zh-Hans', 'You both want to play', '你们都想一起打'),
  ('zh-Hans', 'You and {name} are now friends. Send a message to pick a time.', '你和 {name} 已经是球友了，发消息约个时间。'),
  ('zh-Hant', '{name} wants to play with you', '{name} 想和你打球'),
  ('zh-Hant', 'Say yes and you’ll be friends and can chat.', '同意後你們就是球友，可以聊天。'),
  ('zh-Hant', '{name} said yes to playing', '{name} 同意一起打球'),
  ('zh-Hant', 'You’re now friends. Send a message to pick a time.', '你們已經是球友了，傳訊息約個時間。'),
  ('zh-Hant', 'You both want to play', '你們都想一起打'),
  ('zh-Hant', 'You and {name} are now friends. Send a message to pick a time.', '你和 {name} 已經是球友了，傳訊息約個時間。'),
  ('ja', '{name} wants to play with you', '{name} さんが一緒に打ちたいそうです'),
  ('ja', 'Say yes and you’ll be friends and can chat.', 'OK すると友だちになって、メッセージできます。'),
  ('ja', '{name} said yes to playing', '{name} さんが一緒に打つことに OK しました'),
  ('ja', 'You’re now friends. Send a message to pick a time.', '友だちになりました。メッセージで時間を決めましょう。'),
  ('ja', 'You both want to play', 'お互いに一緒に打ちたいと思っています'),
  ('ja', 'You and {name} are now friends. Send a message to pick a time.', '{name} さんと友だちになりました。メッセージで時間を決めましょう。'),
  ('ko', '{name} wants to play with you', '{name}님이 같이 치고 싶어 해요'),
  ('ko', 'Say yes and you’ll be friends and can chat.', '수락하면 친구가 되고 대화할 수 있어요.'),
  ('ko', '{name} said yes to playing', '{name}님이 같이 치기로 했어요'),
  ('ko', 'You’re now friends. Send a message to pick a time.', '이제 친구예요. 메시지로 시간을 정해 보세요.'),
  ('ko', 'You both want to play', '서로 같이 치고 싶어 해요'),
  ('ko', 'You and {name} are now friends. Send a message to pick a time.', '{name}님과 친구가 됐어요. 메시지로 시간을 정해 보세요.'),
  ('hi', '{name} wants to play with you', '{name} आपके साथ खेलना चाहते हैं'),
  ('hi', 'Say yes and you’ll be friends and can chat.', 'हाँ कहने पर आप दोस्त बन जाएँगे और बात कर सकेंगे।'),
  ('hi', '{name} said yes to playing', '{name} साथ खेलने के लिए तैयार हैं'),
  ('hi', 'You’re now friends. Send a message to pick a time.', 'अब आप दोस्त हैं। समय तय करने के लिए मैसेज करें।'),
  ('hi', 'You both want to play', 'आप दोनों साथ खेलना चाहते हैं'),
  ('hi', 'You and {name} are now friends. Send a message to pick a time.', 'आप और {name} अब दोस्त हैं। समय तय करने के लिए मैसेज करें।'),
  ('id', '{name} wants to play with you', '{name} ingin main bareng kamu'),
  ('id', 'Say yes and you’ll be friends and can chat.', 'Kalau kamu setuju, kalian jadi teman dan bisa mengobrol.'),
  ('id', '{name} said yes to playing', '{name} setuju main bareng'),
  ('id', 'You’re now friends. Send a message to pick a time.', 'Kalian sekarang berteman. Kirim pesan untuk atur waktunya.'),
  ('id', 'You both want to play', 'Kalian sama-sama ingin main bareng'),
  ('id', 'You and {name} are now friends. Send a message to pick a time.', 'Kamu dan {name} sekarang berteman. Kirim pesan untuk atur waktunya.'),
  ('ms', '{name} wants to play with you', '{name} mahu bermain dengan anda'),
  ('ms', 'Say yes and you’ll be friends and can chat.', 'Jika anda setuju, anda akan berkawan dan boleh berbual.'),
  ('ms', '{name} said yes to playing', '{name} setuju untuk bermain bersama'),
  ('ms', 'You’re now friends. Send a message to pick a time.', 'Anda kini berkawan. Hantar mesej untuk tetapkan masa.'),
  ('ms', 'You both want to play', 'Anda berdua mahu bermain bersama'),
  ('ms', 'You and {name} are now friends. Send a message to pick a time.', 'Anda dan {name} kini berkawan. Hantar mesej untuk tetapkan masa.'),
  ('th', '{name} wants to play with you', '{name} อยากตีแบดกับคุณ'),
  ('th', 'Say yes and you’ll be friends and can chat.', 'ถ้าตกลง จะได้เป็นเพื่อนกันและคุยกันได้'),
  ('th', '{name} said yes to playing', '{name} ตกลงตีแบดด้วยกัน'),
  ('th', 'You’re now friends. Send a message to pick a time.', 'ตอนนี้เป็นเพื่อนกันแล้ว ส่งข้อความนัดเวลากันได้เลย'),
  ('th', 'You both want to play', 'คุณทั้งคู่อยากตีแบดด้วยกัน'),
  ('th', 'You and {name} are now friends. Send a message to pick a time.', 'คุณกับ {name} เป็นเพื่อนกันแล้ว ส่งข้อความนัดเวลากันได้เลย'),
  ('vi', '{name} wants to play with you', '{name} muốn chơi cùng bạn'),
  ('vi', 'Say yes and you’ll be friends and can chat.', 'Đồng ý thì hai bạn thành bạn bè và có thể nhắn tin.'),
  ('vi', '{name} said yes to playing', '{name} đã đồng ý chơi cùng'),
  ('vi', 'You’re now friends. Send a message to pick a time.', 'Hai bạn đã là bạn bè. Nhắn tin để hẹn giờ nhé.'),
  ('vi', 'You both want to play', 'Hai bạn đều muốn chơi cùng nhau'),
  ('vi', 'You and {name} are now friends. Send a message to pick a time.', 'Bạn và {name} đã là bạn bè. Nhắn tin để hẹn giờ nhé.')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
