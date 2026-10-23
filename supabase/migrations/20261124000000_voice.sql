-- 文字风格（Badie-iOS/docs/VOICE.md）：通知不用感叹号，中文不用句尾的“吧”，越南文不用“nhé”，泰文不用“นะ”。
-- 约成的通知标题 “Game on!” 改成 “Game confirmed”：英文模板写在函数里，所以两个发这条通知的函数照最新的定义重建，只改这一处；
-- 译文表里的英文模板和译文一起换。其余只改译文，模板和占位符不变

create or replace function public.finalize_offer(p_offer uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  o public.match_offers;
  new_game uuid;
  seat record;
begin
  select * into o from public.match_offers where id = p_offer and status = 'open' for update;
  if o.id is null or exists (select 1 from public.match_seats where offer_id = p_offer and response <> 'accepted') then
    return null;
  end if;

  insert into public.games (mode, starts_at, ends_at, venue_id, offer_id)
    values (o.mode, o.starts_at, o.ends_at, o.venue_id, o.id) returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, s.user_id, s.team, p.rating
    from public.match_seats s join public.profiles p on p.id = s.user_id where s.offer_id = p_offer;
  update public.match_offers set status = 'confirmed', game_id = new_game where id = p_offer;
  update public.match_tickets set status = 'matched', game_id = new_game, offer_id = null
    where id in (select ticket_id from public.match_seats where offer_id = p_offer);

  for seat in select user_id from public.match_seats where offer_id = p_offer loop
    perform public.notify(seat.user_id, 'matched', 'Game confirmed', '{when} · {court}. Everyone confirmed.',
      '/app/games/' || new_game || '/', public.slot(o.starts_at, o.venue_id));
  end loop;
  return new_game;
end
$$;

create or replace function public.start_room(p_room uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  new_game uuid;
  player record;
begin
  select * into r from public.rooms where id = p_room for update;
  if r.id is null or r.owner_id is distinct from auth.uid() or r.status <> 'open' then raise exception 'not_room_owner' using errcode = '42501'; end if;
  if r.venue_id is null or r.starts_at is null then raise exception 'missing_details' using errcode = '22023'; end if;
  if r.starts_at <= now() then raise exception 'already_started' using errcode = '22023'; end if;
  if (select count(*) from public.room_members where room_id = p_room and not waitlisted) <> public.room_capacity(r.mode)
     or (r.mixed and (public.room_going(p_room, 'male') <> 2 or public.room_going(p_room, 'female') <> 2)) then
    raise exception 'not_enough_players' using errcode = '22023';
  end if;
  if exists (select 1 from public.room_members m where m.room_id = p_room and not m.waitlisted
             and public.has_game_between(m.user_id, r.starts_at, r.ends_at)) then
    raise exception 'overlapping' using errcode = '23P01';
  end if;

  -- 分队：按换算后的水平第 1、4 一队；混双强的男生配弱一点的女生
  insert into public.games (mode, starts_at, ends_at, venue_id) values (r.mode, r.starts_at, r.ends_at, r.venue_id) returning id into new_game;
  insert into public.game_players (game_id, user_id, team, rating)
    select new_game, ranked.user_id,
           case when r.mode = 'singles' then ranked.n
                when r.mixed then case when (ranked.gender = 'male') = (ranked.n_gender = 1) then 1 else 2 end
                when ranked.n in (1, 4) then 1 else 2 end,
           ranked.rating
    from (select m.user_id, p.rating, p.gender,
                 row_number() over (order by public.open_rating(p.rating, p.gender) desc, m.joined_at)::smallint as n,
                 row_number() over (partition by p.gender order by p.rating desc, m.joined_at) as n_gender
          from public.room_members m join public.profiles p on p.id = m.user_id
          where m.room_id = p_room and not m.waitlisted) ranked;
  update public.rooms set status = 'started', game_id = new_game where id = p_room;

  for player in select user_id, waitlisted from public.room_members where room_id = p_room and user_id <> r.owner_id loop
    if player.waitlisted then
      perform public.notify(player.user_id, 'room_closed', 'The game is full',
        '{when} · {court} started without the waitlist. Find another game nearby.', '/app/play/', public.slot(r.starts_at, r.venue_id));
    else
      perform public.notify(player.user_id, 'matched', 'Game confirmed', '{when} · {court}. Everyone confirmed.',
        '/app/games/' || new_game || '/', public.slot(r.starts_at, r.venue_id));
    end if;
  end loop;
  return new_game;
end
$$;

update public.notification_texts t set english = 'Game confirmed', translated = v.translated
from (values
  ('zh-Hans', '约成了'),
  ('zh-Hant', '約成了'),
  ('ja', 'ゲームが確定しました'),
  ('ko', '게임이 확정됐어요'),
  ('id', 'Game dikonfirmasi'),
  ('ms', 'Permainan disahkan'),
  ('th', 'ยืนยันเกมแล้ว'),
  ('vi', 'Đã chốt trận'),
  ('hi', 'गेम पक्का हो गया')
) as v(locale, translated)
where t.english = 'Game on!' and t.locale = v.locale;

update public.notification_texts t set translated = v.translated
from (values
  ('zh-Hans', 'You and {name} are now friends. Message them to set up the next game.',
   '你和 {name} 成了球友。可以发消息约下一场。'),
  ('zh-Hant', 'You and {name} are now friends. Message them to set up the next game.',
   '你和 {name} 已經是球友了。可以傳訊息約下一場。'),
  ('vi', 'You and {name} are now friends. Message them to set up the next game.',
   'Bạn và {name} đã là bạn bè. Nhắn tin để hẹn trận tiếp theo.'),
  ('vi', 'Keep an eye on the people around you and keep your swings safe.',
   'Hãy để ý những người xung quanh và vung vợt an toàn.'),
  ('vi', 'Settle up court fees soon after the game.',
   'Hãy trả phần tiền sân sớm sau trận.'),
  ('ko', 'The owner left Badie, so the group is yours now.',
   '그룹장이 Badie를 떠나 이제 이 그룹을 운영하게 됐어요.'),
  ('zh-Hans', 'The host changed the lineup. Find another game nearby.',
   '房主调整了人员。可以看看附近的其他球局。'),
  ('zh-Hant', 'The host changed the lineup. Find another game nearby.',
   '房主調整了人員。可以看看附近的其他球局。'),
  ('th', 'The host changed the lineup. Find another game nearby.',
   'เจ้าของห้องปรับรายชื่อผู้เล่นแล้ว ลองหาเกมอื่นใกล้ ๆ'),
  ('zh-Hans', '{when} · {court} started without the waitlist. Find another game nearby.',
   '{when} · {court} 已开局，候补这次没排上。可以看看附近的其他球局。'),
  ('zh-Hant', '{when} · {court} started without the waitlist. Find another game nearby.',
   '{when} · {court} 已開局，候補這次沒排上。可以看看附近的其他球局。'),
  ('th', '{when} · {court} started without the waitlist. Find another game nearby.',
   '{when} · {court} เริ่มแล้วโดยไม่มีผู้เล่นสำรอง ลองหาเกมอื่นใกล้ ๆ'),
  ('ja', 'We couldn’t find players for {when} · {court}. Nothing counts against you. Still want to play? Try a last-minute search.',
   '{when} · {court} は相手が見つかりませんでした。記録には影響しません。まだプレーしたい場合は「今すぐゲーム」で探せます。'),
  ('ja', '{name} wants to chat',
   '{name}さんがチャットを希望しています'),
  ('ko', '{name} picked you to play {target}: {when} · {court}. We’ll tell you if they accept.',
   '{name}님이 {target}님과 겨룰 파트너로 선택했어요: {when} · {court}. 상대가 수락하면 알려 드릴게요.')
) as v(locale, english, translated)
where t.locale = v.locale and t.english = v.english;
