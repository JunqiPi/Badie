-- 双打挑战（和 iOS 一致）：发起人带一位球友当搭档，对方接受时也选一位自己的球友。
-- 搭档必须是本人的球友、和本人没有屏蔽关系、不是对面的人、那段时间没有别的球局；
-- 发起时通知发起人的搭档，接受后两队各两人开一场双打，搭档都会收到通知

alter table public.challenges
  add column challenger_partner_id uuid references auth.users (id) on delete cascade,
  add column target_partner_id uuid references auth.users (id) on delete cascade;

create function public.valid_partner(p_user uuid, p_partner uuid, p_taken uuid[], p_starts_at timestamptz, p_ends_at timestamptz)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_partner <> p_user and not p_partner = any (p_taken)
    and public.are_friends(p_user, p_partner) and not public.blocked_between(p_user, p_partner)
    and not public.has_game_between(p_partner, p_starts_at, p_ends_at)
$$;

drop function public.send_challenge(uuid, text, timestamptz, timestamptz, text);
drop function public.respond_challenge(uuid, boolean);

create function public.send_challenge(p_target uuid, p_venue text, p_starts_at timestamptz, p_ends_at timestamptz, p_message text,
                                      p_partner uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  availability text := public.challenge_availability(p_target);
  venue text;
  new_id uuid;
  params jsonb;
begin
  if availability = 'hidden' or not public.related(me, p_target) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if availability <> 'available' then raise exception '%', availability using errcode = '22023'; end if;
  if p_starts_at < now() + interval '2 hours' or p_starts_at > now() + interval '14 days' then raise exception 'too_soon' using errcode = '22023'; end if;
  if coalesce(p_message, '') ~* '(https?:|www\.|@|\d{7,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
  select coalesce(merged_into, id) into venue from public.venues where id = p_venue and not hidden_pending_review;
  if venue is null then raise exception 'invalid_venues' using errcode = '22023'; end if;
  if public.has_game_between(me, p_starts_at, p_ends_at) then raise exception 'overlapping' using errcode = '23P01'; end if;
  if p_partner is not null and not public.valid_partner(me, p_partner, array[p_target], p_starts_at, p_ends_at) then
    raise exception 'invalid_partner' using errcode = '22023';
  end if;

  insert into public.challenges (challenger_id, target_id, challenger_partner_id, venue_id, starts_at, ends_at, message, expires_at)
    values (me, p_target, p_partner, venue, p_starts_at, p_ends_at, btrim(coalesce(p_message, '')),
            least(now() + interval '48 hours', p_starts_at - interval '1 hour'))
    returning id into new_id;
  params := public.slot(p_starts_at, venue) || jsonb_build_object(
    'name', (select nickname from public.profiles where id = me),
    'partner', (select nickname from public.profiles where id = p_partner),
    'target', (select nickname from public.profiles where id = p_target));
  if p_partner is null then
    perform public.notify(p_target, 'challenge', 'Singles challenge', '{name} challenged you: {when} · {court}.', '/app/games/', params);
  else
    perform public.notify(p_target, 'challenge', 'Doubles challenge',
      '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '/app/games/', params);
    perform public.notify(p_partner, 'challenge', 'You’re someone’s doubles partner',
      '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '/app/games/', params);
  end if;
  return new_id;
end
$$;

-- 接受：双打要带上自己的搭档（p_partner）
create function public.respond_challenge(p_challenge uuid, p_accept boolean, p_partner uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  c public.challenges;
  doubles boolean;
  new_game uuid;
  player uuid;
  params jsonb;
begin
  select * into c from public.challenges where id = p_challenge and target_id = auth.uid() and status = 'pending' and expires_at > now() for update;
  if c.id is null then raise exception 'challenge_closed' using errcode = 'P0002'; end if;
  if not p_accept then
    update public.challenges set status = 'declined', responded_at = now() where id = p_challenge;
    return null;
  end if;
  doubles := c.challenger_partner_id is not null;
  if doubles and (p_partner is null
                  or not public.valid_partner(c.target_id, p_partner, array[c.challenger_id, c.challenger_partner_id], c.starts_at, c.ends_at)) then
    raise exception 'invalid_partner' using errcode = '22023';
  end if;
  if public.has_game_between(c.challenger_id, c.starts_at, c.ends_at) or public.has_game_between(c.target_id, c.starts_at, c.ends_at)
     or (doubles and public.has_game_between(c.challenger_partner_id, c.starts_at, c.ends_at)) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  insert into public.games (mode, starts_at, ends_at, venue_id)
    values (case when doubles then 'doubles' else 'singles' end::public.game_mode, c.starts_at, c.ends_at, c.venue_id)
    returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, p.id, case when p.id in (c.challenger_id, c.challenger_partner_id) then 1 else 2 end, p.rating
    from public.profiles p
    where p.id in (c.challenger_id, c.target_id) or (doubles and p.id in (c.challenger_partner_id, p_partner));
  update public.challenges set status = 'accepted', responded_at = now(), game_id = new_game,
                               target_partner_id = case when doubles then p_partner end
    where id = p_challenge;
  params := public.slot(c.starts_at, c.venue_id) || jsonb_build_object('name', (select nickname from public.profiles where id = c.target_id));
  foreach player in array array_remove(array[c.challenger_id, c.challenger_partner_id, case when doubles then p_partner end], null) loop
    perform public.notify(player, 'matched', 'Challenge accepted', '{name} is in: {when} · {court}.', '/app/games/' || new_game || '/', params);
  end loop;
  return new_game;
end
$$;

-- 挑战列表加上单打 / 双打和搭档
create or replace function public.my_challenges()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'incoming', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'starts_at', c.starts_at, 'ends_at', c.ends_at, 'message', c.message, 'expires_at', c.expires_at,
        'mode', case when c.challenger_partner_id is null then 'singles' else 'doubles' end,
        'venue', jsonb_build_object('name', v.name, 'tz', v.time_zone_id),
        'player', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating),
        'partner', (select jsonb_build_object('id', x.id, 'nickname', x.nickname, 'rating', x.rating)
                    from public.profiles x where x.id = c.challenger_partner_id)) order by c.starts_at)
      from public.challenges c join public.venues v on v.id = c.venue_id join public.profiles p on p.id = c.challenger_id
      where c.target_id = auth.uid() and c.status = 'pending' and c.expires_at > now()), '[]'),
    'outgoing', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'starts_at', c.starts_at, 'ends_at', c.ends_at, 'game_id', c.game_id,
        'mode', case when c.challenger_partner_id is null then 'singles' else 'doubles' end,
        'status', case when c.status = 'pending' and c.expires_at <= now() then 'not_happening'
                       when c.status in ('declined', 'expired') then 'not_happening' else c.status::text end,
        'venue', jsonb_build_object('name', v.name, 'tz', v.time_zone_id),
        'player', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', p.rating),
        'partner', (select jsonb_build_object('id', x.id, 'nickname', x.nickname, 'rating', x.rating)
                    from public.profiles x where x.id = c.challenger_partner_id)) order by c.created_at desc)
      from public.challenges c join public.venues v on v.id = c.venue_id join public.profiles p on p.id = c.target_id
      where c.challenger_id = auth.uid() and c.status <> 'withdrawn' and c.created_at > now() - interval '14 days'), '[]'))
$$;

revoke execute on function public.valid_partner(uuid, uuid, uuid[], timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.send_challenge(uuid, text, timestamptz, timestamptz, text, uuid), public.respond_challenge(uuid, boolean, uuid)
  from public, anon;
grant execute on function public.send_challenge(uuid, text, timestamptz, timestamptz, text, uuid), public.respond_challenge(uuid, boolean, uuid)
  to authenticated;

insert into public.notification_texts (locale, english, translated) values
  ('zh-Hans', 'Doubles challenge', '双打挑战'),
  ('zh-Hans', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name} 和 {partner} 向你发起双打挑战：{when} · {court}。选一位搭档就能接受。'),
  ('zh-Hans', 'You’re someone’s doubles partner', '你被选为双打搭档'),
  ('zh-Hans', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name} 选你一起挑战 {target}：{when} · {court}。对方接受后会通知你。'),
  ('zh-Hant', 'Doubles challenge', '雙打挑戰'),
  ('zh-Hant', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name} 和 {partner} 向你發起雙打挑戰：{when} · {court}。選一位搭檔就能接受。'),
  ('zh-Hant', 'You’re someone’s doubles partner', '你被選為雙打搭檔'),
  ('zh-Hant', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name} 選你一起挑戰 {target}：{when} · {court}。對方接受後會通知你。'),
  ('ja', 'Doubles challenge', 'ダブルスの挑戦'),
  ('ja', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name} さんと {partner} さんからダブルスの挑戦：{when} · {court}。パートナーを選ぶと承諾できます。'),
  ('ja', 'You’re someone’s doubles partner', 'ダブルスのパートナーに選ばれました'),
  ('ja', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name} さんがあなたを選んで {target} さんに挑戦しました：{when} · {court}。相手が承諾したらお知らせします。'),
  ('ko', 'Doubles challenge', '복식 도전'),
  ('ko', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name}님과 {partner}님이 복식 도전을 보냈어요: {when} · {court}. 파트너를 고르면 수락할 수 있어요.'),
  ('ko', 'You’re someone’s doubles partner', '복식 파트너로 선택됐어요'),
  ('ko', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name}님이 {target}님과의 경기에 당신을 골랐어요: {when} · {court}. 상대가 수락하면 알려 드릴게요.'),
  ('id', 'Doubles challenge', 'Tantangan ganda'),
  ('id', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name} dan {partner} menantangmu: {when} · {court}. Pilih pasangan untuk menerima.'),
  ('id', 'You’re someone’s doubles partner', 'Kamu dipilih jadi pasangan ganda'),
  ('id', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name} memilihmu untuk melawan {target}: {when} · {court}. Kami akan memberi tahu jika mereka menerima.'),
  ('ms', 'Doubles challenge', 'Cabaran beregu'),
  ('ms', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name} dan {partner} mencabar anda: {when} · {court}. Pilih pasangan untuk menerima.'),
  ('ms', 'You’re someone’s doubles partner', 'Anda dipilih sebagai pasangan beregu'),
  ('ms', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name} memilih anda untuk bermain menentang {target}: {when} · {court}. Kami akan maklumkan jika mereka terima.'),
  ('th', 'Doubles challenge', 'คำท้าประเภทคู่'),
  ('th', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name} และ {partner} ท้าคุณ: {when} · {court} เลือกคู่ของคุณเพื่อตอบรับ'),
  ('th', 'You’re someone’s doubles partner', 'คุณถูกเลือกเป็นคู่ประเภทคู่'),
  ('th', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name} เลือกคุณไปเล่นกับ {target}: {when} · {court} เราจะแจ้งเมื่ออีกฝ่ายตอบรับ'),
  ('vi', 'Doubles challenge', 'Thách đấu đôi'),
  ('vi', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name} và {partner} thách đấu bạn: {when} · {court}. Chọn một bạn đánh cặp để nhận lời.'),
  ('vi', 'You’re someone’s doubles partner', 'Bạn được chọn làm bạn đánh đôi'),
  ('vi', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name} chọn bạn để đấu với {target}: {when} · {court}. Chúng tôi sẽ báo khi họ nhận lời.'),
  ('hi', 'Doubles challenge', 'डबल्स चैलेंज'),
  ('hi', '{name} and {partner} challenged you: {when} · {court}. Pick a partner to accept.', '{name} और {partner} ने आपको चैलेंज किया: {when} · {court}। स्वीकार करने के लिए एक पार्टनर चुनें।'),
  ('hi', 'You’re someone’s doubles partner', 'आपको डबल्स पार्टनर चुना गया है'),
  ('hi', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.', '{name} ने {target} के ख़िलाफ़ खेलने के लिए आपको चुना: {when} · {court}। उनके स्वीकार करने पर हम बताएँगे।');
