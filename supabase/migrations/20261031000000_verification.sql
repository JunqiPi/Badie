-- 高水平认证（和 iOS 一致，Badie-iOS/docs/DESIGN.md §13）：问卷最高 6+、没认证最高 7−；
-- 7− 起凭公开可查的证据由管理员人工审核：
-- - 赛事成绩（tournamentsoftware.com 成绩页）7−～8；全国排名或运动员等级证书（15 位编号）7−～8+；BWF 球员页 9−～9+
-- - 同时只能有一份在审核，30 天内最多申请 3 次；证据和姓名只有本人和管理员看得到
-- - 通过后：起点分值换成认证档位，球友评价照常算，但不会超过认证档位，最多往下拉 1 档

create type public.verification_kind as enum ('tournament', 'national', 'bwf');
create type public.verification_state as enum ('pending', 'approved', 'rejected', 'withdrawn');

alter table public.profiles
  add column verified_kind public.verification_kind,
  add column verified_rating numeric(4, 2) check (verified_rating between 6.66 and 9.34);

create table public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind public.verification_kind not null,
  claimed_rating numeric(4, 2) not null,
  evidence text not null check (char_length(evidence) between 5 and 300),
  name_on_record text not null check (char_length(name_on_record) between 2 and 60),
  note text not null default '' check (char_length(note) <= 200),
  status public.verification_state not null default 'pending',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id) on delete set null,
  review_note text,
  approved_rating numeric(4, 2)
);

create unique index verification_requests_pending_idx on public.verification_requests (user_id) where status = 'pending';
create index verification_requests_user_idx on public.verification_requests (user_id, created_at);

alter table public.verification_requests enable row level security;
revoke all on public.verification_requests from anon, authenticated;
grant all on public.verification_requests to service_role;

-- 档位代码：6.67 → 7−，7 → 7，7.33 → 7+
create function public.level_code(p_rating numeric)
returns text language sql immutable set search_path = '' as $$
  select round(p_rating)::int::text || case when p_rating - round(p_rating) < -0.1 then '−' when p_rating - round(p_rating) > 0.1 then '+' else '' end
$$;

-- 每类证据能认证的范围
create function public.verification_range(p_kind public.verification_kind)
returns numrange language sql immutable set search_path = '' as $$
  select case p_kind when 'tournament' then numrange(6.66, 8.01) when 'national' then numrange(6.66, 8.34) else numrange(8.66, 9.34) end
$$;

-- 综合分值：认证过的人起点换成认证档位，最高就是认证档位，最低只比它低 1 档；其余规则不变
create or replace function public.refresh_rating(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  update public.profiles p
    set rating = case
      when p.verified_rating is not null then
        greatest(least(case when r.n >= 5 then round(((1 - r.w) * p.verified_rating + r.w * r.peer) * 3) / 3 else p.verified_rating end,
                       p.verified_rating),
                 round(p.verified_rating * 3 - 1) / 3)
      when r.n >= 5 then least(greatest(round(((1 - r.w) * p.self_rating + r.w * r.peer) * 3) / 3, 0.67), 6.67)
      else p.self_rating end
  from (select count(gr.reviewer_id) as n, avg(gr.peer_rating) as peer,
               case when pr.verified_rating is null and (pr.assessed_at is null or pr.self_rating >= 6.33) then 0.85 else 0.7 end as w
        from public.profiles pr left join public.game_reviews gr on gr.reviewee_id = pr.id and gr.attendance <> 'no_show'
        where pr.id = p_user group by pr.assessed_at, pr.self_rating, pr.verified_rating) r
  where p.id = p_user
$$;

-- 电子证书最后一位是等级码：X、0 = 运动健将以上（最高 8+），1 = 一级（8），2 = 二级（7），3 = 三级（7−）
create function public.certificate_cap(p_code text)
returns numeric language sql immutable set search_path = '' as $$
  select case right(p_code, 1) when 'X' then 8.34 when '0' then 8.34 when '1' then 8.01 when '2' then 7.01 when '3' then 6.68 else 0 end
$$;

-- 提交申请：证据是成绩页 / 球员页链接，全国排名也可以填 15 位电子证书编号（最后一位是等级码）
create function public.request_verification(p_kind public.verification_kind, p_rating numeric, p_evidence text, p_name text,
                                            p_note text default '')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  rating numeric := round(p_rating * 3) / 3;
  evidence text := btrim(coalesce(p_evidence, ''));
  certificate boolean;
  host text;
  new_id uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if exists (select 1 from public.verification_requests where user_id = me and status = 'pending') then
    raise exception 'verification_pending' using errcode = '22023';
  end if;
  if (select count(*) from public.verification_requests where user_id = me and created_at > now() - interval '30 days') >= 3 then
    raise exception 'too_many_verifications' using errcode = '54000';
  end if;
  if rating is null or not public.verification_range(p_kind) @> rating then raise exception 'invalid_level' using errcode = '22023'; end if;

  certificate := p_kind = 'national' and evidence ~* '^[0-9]{14}[0-9x]$';
  if certificate then
    evidence := upper(evidence);
    if rating > public.certificate_cap(evidence) then
      raise exception 'invalid_level' using errcode = '22023';
    end if;
  else
    if evidence !~* '^[a-z]+://' then evidence := 'https://' || evidence; end if;
    host := lower(substring(evidence from '^https://([^/?#:]+)'));
    if host is null or host !~ '\.' or char_length(evidence) > 300
       or (p_kind = 'tournament' and host !~ '(^|\.)tournamentsoftware\.com$')
       or (p_kind = 'bwf' and (host !~ '(^|\.)(bwfbadminton\.com|bwf\.tournamentsoftware\.com)$'
                               or evidence !~* '^https://[^/]+/(player|player-profile)/[^/?#]+')) then
      raise exception 'invalid_evidence' using errcode = '22023';
    end if;
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 2 and 60 then raise exception 'invalid_name' using errcode = '22023'; end if;

  insert into public.verification_requests (user_id, kind, claimed_rating, evidence, name_on_record, note)
    values (me, p_kind, rating, evidence, btrim(p_name), left(btrim(coalesce(p_note, '')), 200))
    returning id into new_id;
  return new_id;
end
$$;

-- 我最近的一次申请
create function public.my_verification()
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(r) - 'user_id' - 'reviewed_by' from (
    select id, user_id, kind, claimed_rating, evidence, name_on_record, note, status, created_at, reviewed_at, reviewed_by,
           review_note, approved_rating
    from public.verification_requests where user_id = auth.uid() order by created_at desc limit 1) r
$$;

create function public.withdraw_verification()
returns void language sql security definer set search_path = '' as $$
  update public.verification_requests set status = 'withdrawn' where user_id = auth.uid() and status = 'pending'
$$;

-- 管理员：待审核的申请（先来先审），带上申请人的昵称、现在的档位和以前的申请次数
create function public.admin_verification_queue()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_admin();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'user_id', r.user_id, 'nickname', p.nickname, 'rating', p.rating, 'kind', r.kind,
      'claimed_rating', r.claimed_rating, 'evidence', r.evidence, 'name_on_record', r.name_on_record, 'note', r.note,
      'created_at', r.created_at,
      'previous', (select count(*) from public.verification_requests x where x.user_id = r.user_id and x.id <> r.id)) order by r.created_at)
    from public.verification_requests r join public.profiles p on p.id = r.user_id where r.status = 'pending'), '[]'::jsonb);
end
$$;

-- 管理员审核：p_rating 是通过的档位（可以比申请的低，限制在这类证据的范围内），null = 不通过
create function public.admin_review_verification(p_request uuid, p_rating numeric, p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.verification_requests;
  approved numeric;
  remark text := left(btrim(coalesce(p_note, '')), 500);
begin
  perform public.require_admin();
  select * into r from public.verification_requests where id = p_request and status = 'pending' for update;
  if r.id is null then raise exception 'request_not_found' using errcode = 'P0002'; end if;
  -- 不能审核自己的申请
  if r.user_id = auth.uid() then raise exception 'not_allowed' using errcode = '42501'; end if;
  if p_rating is null then
    update public.verification_requests set status = 'rejected', reviewed_at = now(), reviewed_by = auth.uid(), review_note = remark
      where id = r.id;
    perform public.notify(r.user_id, 'verification', 'Verification not approved',
      case when remark = '' then 'We couldn’t check the details on your evidence. You can add more and apply again.' else '{note}' end,
      '/app/me/', jsonb_build_object('note', remark));
  else
    approved := round(p_rating * 3) / 3;
    if not public.verification_range(r.kind) @> approved then raise exception 'invalid_level' using errcode = '22023'; end if;
    update public.profiles set verified_kind = r.kind, verified_rating = approved where id = r.user_id;
    perform public.refresh_rating(r.user_id);
    update public.verification_requests
      set status = 'approved', reviewed_at = now(), reviewed_by = auth.uid(), review_note = remark, approved_rating = approved
      where id = r.id;
    perform public.notify(r.user_id, 'verification', 'Level verified: {level}',
      'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.',
      '/app/me/', jsonb_build_object('level', public.level_code(approved)));
  end if;
  insert into public.moderation_log (admin_id, target_type, target_id, action, note)
    values (auth.uid(), 'verification', r.id::text, case when p_rating is null then 'reject' else 'approve' end, remark);
end
$$;

-- 资料页：加上认证类型
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', (select verified_kind from public.profiles where id = p_user))
  from public.player_card_base(p_user) base, public.win_rate(p_user) w
  where base is not null
$$;

revoke execute on function public.level_code(numeric), public.verification_range(public.verification_kind), public.certificate_cap(text)
  from public, anon, authenticated;
revoke execute on function public.request_verification(public.verification_kind, numeric, text, text, text), public.my_verification(),
  public.withdraw_verification(), public.admin_verification_queue(), public.admin_review_verification(uuid, numeric, text)
  from public, anon;
grant execute on function public.request_verification(public.verification_kind, numeric, text, text, text), public.my_verification(),
  public.withdraw_verification(), public.admin_verification_queue(), public.admin_review_verification(uuid, numeric, text)
  to authenticated;

insert into public.notification_texts (locale, english, translated) values
  ('zh-Hans', 'Verification not approved', '认证没有通过'),
  ('zh-Hans', 'We couldn’t check the details on your evidence. You can add more and apply again.', '证据上的信息无法核实，可以补充材料后重新申请。'),
  ('zh-Hans', 'Level verified: {level}', '认证通过：{level}'),
  ('zh-Hans', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', '资料上已显示认证徽章。之后的等级会结合球友评价，但不会超过认证档位。'),
  ('zh-Hant', 'Verification not approved', '認證沒有通過'),
  ('zh-Hant', 'We couldn’t check the details on your evidence. You can add more and apply again.', '證據上的資訊無法核實，可以補充資料後重新申請。'),
  ('zh-Hant', 'Level verified: {level}', '認證通過：{level}'),
  ('zh-Hant', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', '資料上已顯示認證徽章。之後的等級會結合球友評價，但不會超過認證檔位。'),
  ('ja', 'Verification not approved', '認証は承認されませんでした'),
  ('ja', 'We couldn’t check the details on your evidence. You can add more and apply again.', '提出された証拠の内容を確認できませんでした。資料を追加して再申請できます。'),
  ('ja', 'Level verified: {level}', 'レベル認証：{level}'),
  ('ja', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', 'プロフィールに認証バッジが表示されます。試合の評価も反映されますが、このレベルを超えることはありません。'),
  ('ko', 'Verification not approved', '인증이 승인되지 않았어요'),
  ('ko', 'We couldn’t check the details on your evidence. You can add more and apply again.', '제출한 증거의 내용을 확인할 수 없었어요. 자료를 보완해서 다시 신청할 수 있어요.'),
  ('ko', 'Level verified: {level}', '레벨 인증: {level}'),
  ('ko', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', '프로필에 인증 배지가 표시돼요. 경기 평가도 반영되지만 이 레벨을 넘지는 않아요.'),
  ('id', 'Verification not approved', 'Verifikasi tidak disetujui'),
  ('id', 'We couldn’t check the details on your evidence. You can add more and apply again.', 'Kami tidak bisa memeriksa detail buktimu. Kamu bisa menambahkan bukti lalu mengajukan lagi.'),
  ('id', 'Level verified: {level}', 'Level terverifikasi: {level}'),
  ('id', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', 'Profilmu sekarang menampilkan lencana terverifikasi. Ulasan dari permainan tetap dihitung, tapi tidak akan melewati level ini.'),
  ('ms', 'Verification not approved', 'Pengesahan tidak diluluskan'),
  ('ms', 'We couldn’t check the details on your evidence. You can add more and apply again.', 'Kami tidak dapat menyemak butiran bukti anda. Anda boleh menambah bukti dan memohon semula.'),
  ('ms', 'Level verified: {level}', 'Tahap disahkan: {level}'),
  ('ms', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', 'Profil anda kini memaparkan lencana disahkan. Ulasan daripada permainan masih dikira, tetapi tidak akan melebihi tahap ini.'),
  ('th', 'Verification not approved', 'การยืนยันไม่ผ่าน'),
  ('th', 'We couldn’t check the details on your evidence. You can add more and apply again.', 'เราตรวจสอบรายละเอียดในหลักฐานของคุณไม่ได้ คุณเพิ่มหลักฐานแล้วยื่นใหม่ได้'),
  ('th', 'Level verified: {level}', 'ยืนยันระดับแล้ว: {level}'),
  ('th', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', 'โปรไฟล์ของคุณแสดงตราการยืนยันแล้ว คะแนนจากเกมยังนับอยู่ แต่จะไม่เกินระดับนี้'),
  ('vi', 'Verification not approved', 'Xác minh không được duyệt'),
  ('vi', 'We couldn’t check the details on your evidence. You can add more and apply again.', 'Chúng tôi không kiểm tra được thông tin trong bằng chứng của bạn. Bạn có thể bổ sung và nộp lại.'),
  ('vi', 'Level verified: {level}', 'Đã xác minh trình độ: {level}'),
  ('vi', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', 'Hồ sơ của bạn giờ có huy hiệu đã xác minh. Đánh giá từ các trận vẫn được tính, nhưng không vượt quá trình độ này.'),
  ('hi', 'Verification not approved', 'वेरिफ़िकेशन मंज़ूर नहीं हुआ'),
  ('hi', 'We couldn’t check the details on your evidence. You can add more and apply again.', 'हम आपके सबूत की जानकारी जाँच नहीं पाए। आप और सबूत जोड़कर फिर से आवेदन कर सकते हैं।'),
  ('hi', 'Level verified: {level}', 'लेवल वेरिफ़ाई हुआ: {level}'),
  ('hi', 'Your profile now shows a verified badge. Reviews from games still count, but won’t take you above this level.', 'आपकी प्रोफ़ाइल पर अब वेरिफ़ाइड बैज दिखता है। गेम के रिव्यू गिने जाते रहेंगे, पर इस लेवल से ऊपर नहीं ले जाएँगे।');
