-- 爽约处罚（三档，只数近 180 天内的次数）：第 1 次警告，第 2 次 7 天不能约球，第 3 次永久不能约球。
-- - 爽约：没签到、没取消，并且同场没取消的人里多数说他没来（单打是对手，双打是另外 3 人里至少 2 人）
-- - 48 小时内可以申诉；申诉期间不执行，管理员核实后维持或撤销（撤销的不再计入，之后的次数重新排档）
-- - 不能约球：不能匹配、发起或加入球局、报名球群、发起或接受挑战；可以登录、看消息
-- - 资料页显示近 180 天爽约次数和暂停到什么时候

create table public.strikes (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  game_id uuid not null references public.games (id) on delete cascade,
  level smallint not null check (level between 1 and 3),
  status text not null default 'active' check (status in ('active', 'appealed', 'upheld', 'overturned')),
  -- 不能约球从什么时候开始（只有第 2、3 次有；申诉中为空）
  starts_at timestamptz,
  appeal text check (char_length(appeal) <= 500),
  appealed_at timestamptz,
  resolved_at timestamptz,
  -- 本人看过提醒
  seen_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, game_id)
);
create index strikes_user_idx on public.strikes (user_id, created_at);
alter table public.strikes enable row level security;
revoke all on public.strikes from anon, authenticated;
grant all on public.strikes to service_role;

-- 这局他算不算爽约：没签到、没取消，同场多数人说他没来
create function public.judged_no_show(p_game uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select gp.checked_in_at is null and gp.cancelled_at is null
       and (select count(*) from public.game_reviews r
            join public.game_players rp on rp.game_id = r.game_id and rp.user_id = r.reviewer_id and rp.cancelled_at is null
            where r.game_id = p_game and r.reviewee_id = p_user and r.attendance = 'no_show') * 2
         > (select count(*) from public.game_players o where o.game_id = p_game and o.user_id <> p_user and o.cancelled_at is null)
    from public.game_players gp where gp.game_id = p_game and gp.user_id = p_user), false)
$$;

-- 履约记录按同样的标准算；申诉撤销的不算
create or replace function public.attendance_record(p_user uuid)
returns table (games_played bigint, no_shows bigint, late_cancels bigint)
language sql stable security definer set search_path = '' as $$
  with ended as (
    select public.judged_no_show(g.id, p_user)
           and not exists (select 1 from public.strikes s where s.game_id = g.id and s.user_id = p_user and s.status = 'overturned') as no_show
    from public.game_players gp join public.games g on g.id = gp.game_id
    where gp.user_id = p_user and gp.cancelled_at is null and g.status = 'scheduled' and g.ends_at < now())
  select count(*) filter (where not no_show), count(*) filter (where no_show),
         (select count(*) from public.game_players where user_id = p_user and late_cancel)
           + (select count(*) from public.session_late_cancels where user_id = p_user)
  from ended
$$;

-- 现在不能约球到什么时候（永久 = infinity；能约球 = null）
create function public.suspended_until(p_user uuid)
returns timestamptz language sql stable security definer set search_path = '' as $$
  select max(case when level = 3 then 'infinity'::timestamptz else starts_at + interval '7 days' end)
  from public.strikes
  where user_id = p_user and level >= 2 and status in ('active', 'upheld') and starts_at is not null
    and (level = 3 or starts_at + interval '7 days' > now())
$$;

-- 近 180 天爽约次数（申诉中和撤销的不算）
create function public.recent_no_shows(p_user uuid)
returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.strikes
  where user_id = p_user and status in ('active', 'upheld') and created_at > now() - interval '180 days'
$$;

create function public.strike_text(p_level int)
returns text language sql immutable set search_path = '' as $$
  select case p_level
    when 1 then 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.'
    when 2 then 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.'
    else 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.' end
$$;

-- 开始不能约球：还在找的约球请求一并取消（不然之后照样会被排进球局）
create function public.start_suspension(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  update public.match_tickets set status = 'cancelled' where user_id = p_user and status in ('searching', 'paused')
$$;

-- 有人说他没来时检查一次：够了多数就记一次
create function public.record_strike()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  previous int;
  next_level smallint;
begin
  -- 同一局几个人同时评：排队判断，后提交的能看到先提交的评价（不会都只数到 1 票而漏记）
  perform 1 from public.game_players where game_id = new.game_id and user_id = new.reviewee_id for update;
  if exists (select 1 from public.strikes where user_id = new.reviewee_id and game_id = new.game_id)
     or not public.judged_no_show(new.game_id, new.reviewee_id) then
    return new;
  end if;
  select count(*) into previous from public.strikes
    where user_id = new.reviewee_id and status <> 'overturned' and created_at > now() - interval '180 days';
  next_level := least(previous + 1, 3);
  insert into public.strikes (user_id, game_id, level, starts_at)
    values (new.reviewee_id, new.game_id, next_level, case when next_level >= 2 then now() end);
  if next_level >= 2 then perform public.start_suspension(new.reviewee_id); end if;
  perform public.notify(new.reviewee_id, 'strike', 'Missed game recorded', public.strike_text(next_level), '/me/');
  return new;
end
$$;

create trigger game_reviews_strike after insert on public.game_reviews
  for each row when (new.attendance = 'no_show') execute function public.record_strike();

-- 不能约球的人：报名、加入、发起都拦下（只拦本人的操作，系统替人做的不拦）
create function public.block_suspended()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is not null and (to_jsonb(new) ->> tg_argv[0])::uuid = me and public.suspended_until(me) is not null then
    raise exception 'suspended' using errcode = '42501';
  end if;
  return new;
end
$$;

create trigger match_tickets_suspended before insert on public.match_tickets
  for each row execute function public.block_suspended('user_id');
create trigger match_seats_suspended before update of response on public.match_seats
  for each row when (new.response = 'accepted' and old.response is distinct from new.response)
  execute function public.block_suspended('user_id');
create trigger room_members_suspended before insert on public.room_members
  for each row execute function public.block_suspended('user_id');
create trigger session_signups_suspended before insert on public.session_signups
  for each row execute function public.block_suspended('user_id');
create trigger challenges_suspended before insert on public.challenges
  for each row execute function public.block_suspended('challenger_id');
-- 接受挑战：双方和搭档都要能约球（发起后才被暂停的也拦下）
create function public.block_suspended_challenge()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from unnest(array[new.challenger_id, new.target_id, new.challenger_partner_id, new.target_partner_id]) u
             where u is not null and public.suspended_until(u) is not null) then
    raise exception 'suspended' using errcode = '42501';
  end if;
  return new;
end
$$;
create trigger challenges_accept_suspended before update of status on public.challenges
  for each row when (new.status = 'accepted' and old.status is distinct from new.status)
  execute function public.block_suspended_challenge();

-- 双打挑战选搭档：不能约球的人选不了
create or replace function public.valid_partner(p_user uuid, p_partner uuid, p_taken uuid[], p_starts_at timestamptz, p_ends_at timestamptz)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_partner <> p_user and not p_partner = any (p_taken)
    and public.are_friends(p_user, p_partner) and not public.blocked_between(p_user, p_partner)
    and not public.has_game_between(p_partner, p_starts_at, p_ends_at)
    and public.suspended_until(p_partner) is null
$$;

-- 我的爽约记录：暂停到什么时候、近 180 天次数、每一次（能不能申诉、看过没有）；永久的那次一直列出来
create function public.my_strikes()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'suspended_until', public.suspended_until(auth.uid()),
    'recent', public.recent_no_shows(auth.uid()),
    'strikes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'level', s.level, 'status', s.status, 'created_at', s.created_at, 'seen', s.seen_at is not null,
               'can_appeal', s.status = 'active' and s.created_at > now() - interval '48 hours',
               'game_starts_at', g.starts_at, 'tz', v.time_zone_id, 'venue', v.name) order by s.created_at desc)
      from public.strikes s join public.games g on g.id = s.game_id left join public.venues v on v.id = g.venue_id
      where s.user_id = auth.uid()
        and (s.created_at > now() - interval '180 days' or (s.level = 3 and s.status in ('active', 'upheld')))), '[]'))
$$;

create function public.mark_strikes_seen()
returns void language sql security definer set search_path = '' as $$
  update public.strikes set seen_at = now() where user_id = auth.uid() and seen_at is null
$$;

-- 申诉：48 小时内，写明情况；申诉期间不执行
create function public.appeal_strike(p_strike bigint, p_text text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  body text := btrim(coalesce(p_text, ''));
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if char_length(body) not between 5 and 500 then raise exception 'invalid_appeal' using errcode = '22023'; end if;
  update public.strikes set status = 'appealed', appeal = body, appealed_at = now(), starts_at = null, seen_at = coalesce(seen_at, now())
    where id = p_strike and user_id = auth.uid() and status = 'active' and created_at > now() - interval '48 hours';
  if not found then raise exception 'appeal_closed' using errcode = '22023'; end if;
end
$$;

-- 管理员：待处理的申诉（附上这局谁说他没来）
create function public.admin_strike_appeals()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'level', s.level, 'appeal', s.appeal, 'appealed_at', s.appealed_at,
             'user', jsonb_build_object('id', p.id, 'nickname', p.nickname),
             'game', jsonb_build_object('id', g.id, 'starts_at', g.starts_at, 'venue', v.name),
             'reporters', (select coalesce(jsonb_agg(rp.nickname), '[]') from public.game_reviews r join public.profiles rp on rp.id = r.reviewer_id
                           where r.game_id = s.game_id and r.reviewee_id = s.user_id and r.attendance = 'no_show'))
           order by s.appealed_at)
    from public.strikes s join public.profiles p on p.id = s.user_id join public.games g on g.id = s.game_id
    left join public.venues v on v.id = g.venue_id
    where s.status = 'appealed'), '[]');
end
$$;

-- 撤销一次后，之后的每次按新的次数重新排档（降档的沿用原来的开始时间）
create function public.relevel_strikes(p_user uuid, p_after timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r record;
  next_level smallint;
begin
  for r in select id, created_at from public.strikes
           where user_id = p_user and created_at > p_after and status <> 'overturned' order by created_at loop
    select least(count(*) + 1, 3) into next_level from public.strikes
      where user_id = p_user and status <> 'overturned' and created_at < r.created_at and created_at > r.created_at - interval '180 days';
    update public.strikes set level = next_level, starts_at = case when next_level >= 2 then starts_at end where id = r.id;
  end loop;
end
$$;

-- 管理员处理申诉：撤销（不再计入记录）或维持（第 2、3 次从现在开始执行）
create function public.admin_resolve_strike(p_strike bigint, p_overturn boolean, p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.strikes;
begin
  perform public.require_admin();
  update public.strikes
    set status = case when p_overturn then 'overturned' else 'upheld' end, resolved_at = now(),
        starts_at = case when not p_overturn and level >= 2 then now() end
    where id = p_strike and status = 'appealed' returning * into s;
  if s.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if p_overturn then
    perform public.relevel_strikes(s.user_id, s.created_at);
    perform public.notify(s.user_id, 'strike', 'Appeal accepted', 'The missed game was removed from your record.', '/me/');
  else
    if s.level >= 2 then perform public.start_suspension(s.user_id); end if;
    perform public.notify(s.user_id, 'strike', 'Appeal declined', 'We checked, and the missed game stays on your record.', '/me/');
  end if;
  insert into public.moderation_log (admin_id, target_type, target_id, action, note)
    values (auth.uid(), 'strike', s.id::text, case when p_overturn then 'overturn' else 'uphold' end, left(coalesce(p_note, ''), 500));
end
$$;

-- 资料卡：近 180 天爽约次数、暂停到什么时候
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', pr.verified_kind,
    'avatar', pr.avatar_path,
    'gender', pr.gender,
    'tag', pr.tag,
    'recent_no_shows', public.recent_no_shows(p_user),
    'suspended_until', public.suspended_until(p_user))
  from public.player_card_base(p_user) base, public.win_rate(p_user) w, public.profiles pr
  where base is not null and pr.id = p_user
$$;

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', 'Missed game recorded', '记了一次爽约'),
  ('zh-Hans', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '球友说你没来。180 天内再有一次，7 天内不能约球。觉得不对，可以在 48 小时内申诉。'),
  ('zh-Hans', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '180 天内第二次爽约，7 天内不能约球。觉得不对，可以在 48 小时内申诉。'),
  ('zh-Hans', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', '180 天内第三次爽约，以后不能再约球。觉得不对，可以在 48 小时内申诉。'),
  ('zh-Hans', 'Appeal accepted', '申诉通过'),
  ('zh-Hans', 'The missed game was removed from your record.', '这次爽约已从你的记录里撤销。'),
  ('zh-Hans', 'Appeal declined', '申诉未通过'),
  ('zh-Hans', 'We checked, and the missed game stays on your record.', '我们核实过，这次爽约仍保留在记录里。'),
  ('zh-Hant', 'Missed game recorded', '記了一次爽約'),
  ('zh-Hant', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '球友說你沒來。180 天內再有一次，7 天內不能約球。覺得不對，可以在 48 小時內申訴。'),
  ('zh-Hant', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '180 天內第二次爽約，7 天內不能約球。覺得不對，可以在 48 小時內申訴。'),
  ('zh-Hant', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', '180 天內第三次爽約，以後不能再約球。覺得不對，可以在 48 小時內申訴。'),
  ('zh-Hant', 'Appeal accepted', '申訴通過'),
  ('zh-Hant', 'The missed game was removed from your record.', '這次爽約已從你的紀錄裡撤銷。'),
  ('zh-Hant', 'Appeal declined', '申訴未通過'),
  ('zh-Hant', 'We checked, and the missed game stays on your record.', '我們核實過，這次爽約仍保留在紀錄裡。'),
  ('ja', 'Missed game recorded', 'ドタキャンが記録されました'),
  ('ja', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '参加しなかったと報告されました。180 日以内にもう一度あると、7 日間試合に参加できません。間違いだと思う場合は 48 時間以内に申し立てできます。'),
  ('ja', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '180 日以内で 2 回目のドタキャンです。7 日間試合に参加できません。間違いだと思う場合は 48 時間以内に申し立てできます。'),
  ('ja', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', '180 日以内で 3 回目のドタキャンです。今後は試合に参加できません。間違いだと思う場合は 48 時間以内に申し立てできます。'),
  ('ja', 'Appeal accepted', '申し立てが認められました'),
  ('ja', 'The missed game was removed from your record.', 'このドタキャンは記録から取り消されました。'),
  ('ja', 'Appeal declined', '申し立ては認められませんでした'),
  ('ja', 'We checked, and the missed game stays on your record.', '確認の結果、このドタキャンは記録に残ります。'),
  ('ko', 'Missed game recorded', '노쇼가 기록됐어요'),
  ('ko', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '오지 않았다는 신고가 있었어요. 180일 안에 한 번 더 있으면 7일 동안 게임에 참여할 수 없어요. 잘못됐다면 48시간 안에 이의를 신청하세요.'),
  ('ko', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '180일 안에 두 번째 노쇼예요. 7일 동안 게임에 참여할 수 없어요. 잘못됐다면 48시간 안에 이의를 신청하세요.'),
  ('ko', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', '180일 안에 세 번째 노쇼예요. 앞으로 게임에 참여할 수 없어요. 잘못됐다면 48시간 안에 이의를 신청하세요.'),
  ('ko', 'Appeal accepted', '이의 신청이 받아들여졌어요'),
  ('ko', 'The missed game was removed from your record.', '이번 노쇼는 기록에서 지워졌어요.'),
  ('ko', 'Appeal declined', '이의 신청이 받아들여지지 않았어요'),
  ('ko', 'We checked, and the missed game stays on your record.', '확인 결과 이번 노쇼는 기록에 남아요.'),
  ('hi', 'Missed game recorded', 'नो-शो दर्ज हुआ'),
  ('hi', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'खिलाड़ियों ने बताया कि आप नहीं आए। 180 दिनों में फिर ऐसा हुआ तो 7 दिन तक आप गेम में शामिल नहीं हो पाएँगे। ग़लत लगे तो 48 घंटे में अपील करें।'),
  ('hi', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', '180 दिनों में दूसरा नो-शो। 7 दिन तक आप गेम में शामिल नहीं हो पाएँगे। ग़लत लगे तो 48 घंटे में अपील करें।'),
  ('hi', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', '180 दिनों में तीसरा नो-शो। अब आप गेम में शामिल नहीं हो पाएँगे। ग़लत लगे तो 48 घंटे में अपील करें।'),
  ('hi', 'Appeal accepted', 'अपील मंज़ूर हुई'),
  ('hi', 'The missed game was removed from your record.', 'यह नो-शो आपके रिकॉर्ड से हटा दिया गया।'),
  ('hi', 'Appeal declined', 'अपील नामंज़ूर हुई'),
  ('hi', 'We checked, and the missed game stays on your record.', 'हमने जाँच की, यह नो-शो आपके रिकॉर्ड में रहेगा।'),
  ('id', 'Missed game recorded', 'Tidak hadir tercatat'),
  ('id', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'Pemain lain bilang kamu tidak datang. Kalau terulang dalam 180 hari, kamu tidak bisa ikut main selama 7 hari. Merasa keliru? Ajukan banding dalam 48 jam.'),
  ('id', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'Kedua kalinya tidak hadir dalam 180 hari. Kamu tidak bisa ikut main selama 7 hari. Merasa keliru? Ajukan banding dalam 48 jam.'),
  ('id', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', 'Ketiga kalinya tidak hadir dalam 180 hari. Kamu tidak bisa ikut main lagi. Merasa keliru? Ajukan banding dalam 48 jam.'),
  ('id', 'Appeal accepted', 'Banding diterima'),
  ('id', 'The missed game was removed from your record.', 'Ketidakhadiran ini sudah dihapus dari catatanmu.'),
  ('id', 'Appeal declined', 'Banding ditolak'),
  ('id', 'We checked, and the missed game stays on your record.', 'Kami sudah memeriksa, dan ketidakhadiran ini tetap tercatat.'),
  ('ms', 'Missed game recorded', 'Tidak hadir direkodkan'),
  ('ms', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'Pemain lain berkata anda tidak hadir. Jika berlaku lagi dalam 180 hari, anda tidak boleh menyertai permainan selama 7 hari. Rasa tidak betul? Buat rayuan dalam 48 jam.'),
  ('ms', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'Kali kedua tidak hadir dalam 180 hari. Anda tidak boleh menyertai permainan selama 7 hari. Rasa tidak betul? Buat rayuan dalam 48 jam.'),
  ('ms', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', 'Kali ketiga tidak hadir dalam 180 hari. Anda tidak boleh menyertai permainan lagi. Rasa tidak betul? Buat rayuan dalam 48 jam.'),
  ('ms', 'Appeal accepted', 'Rayuan diterima'),
  ('ms', 'The missed game was removed from your record.', 'Ketidakhadiran ini telah dibuang daripada rekod anda.'),
  ('ms', 'Appeal declined', 'Rayuan ditolak'),
  ('ms', 'We checked, and the missed game stays on your record.', 'Kami telah menyemak, dan ketidakhadiran ini kekal dalam rekod anda.'),
  ('th', 'Missed game recorded', 'บันทึกการเบี้ยวนัดแล้ว'),
  ('th', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'ผู้เล่นแจ้งว่าคุณไม่มา หากเกิดขึ้นอีกภายใน 180 วัน คุณจะเข้าร่วมเกมไม่ได้ 7 วัน หากคิดว่าไม่ถูกต้อง อุทธรณ์ได้ภายใน 48 ชั่วโมง'),
  ('th', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'เบี้ยวนัดครั้งที่สองใน 180 วัน คุณจะเข้าร่วมเกมไม่ได้ 7 วัน หากคิดว่าไม่ถูกต้อง อุทธรณ์ได้ภายใน 48 ชั่วโมง'),
  ('th', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', 'เบี้ยวนัดครั้งที่สามใน 180 วัน คุณจะเข้าร่วมเกมไม่ได้อีก หากคิดว่าไม่ถูกต้อง อุทธรณ์ได้ภายใน 48 ชั่วโมง'),
  ('th', 'Appeal accepted', 'อุทธรณ์สำเร็จ'),
  ('th', 'The missed game was removed from your record.', 'ลบการเบี้ยวนัดครั้งนี้ออกจากประวัติของคุณแล้ว'),
  ('th', 'Appeal declined', 'อุทธรณ์ไม่สำเร็จ'),
  ('th', 'We checked, and the missed game stays on your record.', 'เราตรวจสอบแล้ว การเบี้ยวนัดครั้งนี้ยังอยู่ในประวัติของคุณ'),
  ('vi', 'Missed game recorded', 'Đã ghi nhận bùng kèo'),
  ('vi', 'Players said you didn’t show up. If it happens again within 180 days, you can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'Người chơi báo bạn không đến. Nếu lặp lại trong 180 ngày, bạn sẽ không thể tham gia trận trong 7 ngày. Thấy không đúng? Hãy khiếu nại trong 48 giờ.'),
  ('vi', 'Second missed game in 180 days. You can’t join games for 7 days. Think it’s wrong? Appeal within 48 hours.', 'Lần bùng kèo thứ hai trong 180 ngày. Bạn không thể tham gia trận trong 7 ngày. Thấy không đúng? Hãy khiếu nại trong 48 giờ.'),
  ('vi', 'Third missed game in 180 days. You can no longer join games. Think it’s wrong? Appeal within 48 hours.', 'Lần bùng kèo thứ ba trong 180 ngày. Bạn không thể tham gia trận nữa. Thấy không đúng? Hãy khiếu nại trong 48 giờ.'),
  ('vi', 'Appeal accepted', 'Khiếu nại được chấp nhận'),
  ('vi', 'The missed game was removed from your record.', 'Lần bùng kèo này đã được xóa khỏi hồ sơ của bạn.'),
  ('vi', 'Appeal declined', 'Khiếu nại không được chấp nhận'),
  ('vi', 'We checked, and the missed game stays on your record.', 'Chúng tôi đã kiểm tra, lần bùng kèo này vẫn nằm trong hồ sơ của bạn.')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;

revoke execute on function public.judged_no_show(uuid, uuid), public.suspended_until(uuid), public.recent_no_shows(uuid),
  public.strike_text(int), public.record_strike(), public.block_suspended(), public.block_suspended_challenge(),
  public.start_suspension(uuid), public.relevel_strikes(uuid, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.my_strikes(), public.mark_strikes_seen(), public.appeal_strike(bigint, text),
  public.admin_strike_appeals(), public.admin_resolve_strike(bigint, boolean, text)
  from public, anon;
grant execute on function public.my_strikes(), public.mark_strikes_seen(), public.appeal_strike(bigint, text),
  public.admin_strike_appeals(), public.admin_resolve_strike(bigint, boolean, text)
  to authenticated;
