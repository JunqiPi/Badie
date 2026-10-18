-- 注销账号：本人在网页或 App 里删除账号和数据（App Store 要求可以在应用内删除）。
-- 先把会影响别人的事处理好，再删 auth.users，其余数据按外键级联删除：
-- 以后的球局取消并通知其他人（和自己取消一样），进行中的约球请求撤回，
-- 自己建的球群交给下一位组织者（没有就交给最早加入的成员；没人就随账号删除），以后场次的名额让给候补

create function public.delete_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  item record;
  heir uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  -- 管理员的审核记录要保留：先由人工撤掉管理员身份
  if public.is_admin() then raise exception 'admin_account' using errcode = '42501'; end if;

  for item in select t.id from public.match_tickets t where t.user_id = me and t.status in ('searching', 'offered', 'paused') loop
    perform public.cancel_ticket(item.id);
  end loop;

  for item in select g.id from public.games g join public.game_players gp on gp.game_id = g.id
              where gp.user_id = me and g.status = 'scheduled' and g.starts_at > now() loop
    perform public.cancel_game(item.id);
  end loop;

  for item in select id, name from public.play_groups where owner_id = me loop
    select m.user_id into heir from public.group_members m
      where m.group_id = item.id and m.user_id <> me and not m.pending
      order by m.role = 'organizer' desc, m.joined_at
      limit 1;
    continue when heir is null;
    update public.play_groups set owner_id = heir where id = item.id;
    update public.group_members set role = 'owner' where group_id = item.id and user_id = heir;
    perform public.notify(heir, 'group', 'You now run {group}', 'The owner left Badie, so the group is yours now.',
      '/app/groups/' || item.id || '/', jsonb_build_object('group', item.name));
  end loop;

  for item in delete from public.session_signups s using public.group_sessions gs
              where s.session_id = gs.id and s.user_id = me and gs.starts_at > now()
              returning s.session_id loop
    perform public.promote_waitlist(item.session_id);
  end loop;

  delete from auth.users where id = me;
end
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

insert into public.notification_texts (locale, english, translated) values
  ('zh-Hans', 'You now run {group}', '你现在是 {group} 的群主'),
  ('zh-Hans', 'The owner left Badie, so the group is yours now.', '原群主已离开 Badie，这个球群交给你了。'),
  ('zh-Hant', 'You now run {group}', '你現在是 {group} 的群主'),
  ('zh-Hant', 'The owner left Badie, so the group is yours now.', '原群主已離開 Badie，這個球群交給你了。'),
  ('ja', 'You now run {group}', '{group} のオーナーになりました'),
  ('ja', 'The owner left Badie, so the group is yours now.', '前のオーナーが Badie を退会したため、このグループはあなたに引き継がれました。'),
  ('ko', 'You now run {group}', '이제 {group}의 그룹장이에요'),
  ('ko', 'The owner left Badie, so the group is yours now.', '그룹장이 Badie를 떠나서 이제 이 그룹은 당신이 운영해요.'),
  ('id', 'You now run {group}', 'Sekarang kamu pengelola {group}'),
  ('id', 'The owner left Badie, so the group is yours now.', 'Pemilik grup sudah keluar dari Badie, jadi grup ini sekarang kamu yang kelola.'),
  ('ms', 'You now run {group}', 'Anda kini pengendali {group}'),
  ('ms', 'The owner left Badie, so the group is yours now.', 'Pemilik kumpulan telah meninggalkan Badie, jadi kumpulan ini kini milik anda.'),
  ('th', 'You now run {group}', 'ตอนนี้คุณเป็นเจ้าของ {group}'),
  ('th', 'The owner left Badie, so the group is yours now.', 'เจ้าของกลุ่มออกจาก Badie แล้ว กลุ่มนี้จึงเป็นของคุณ'),
  ('vi', 'You now run {group}', 'Giờ bạn là trưởng nhóm {group}'),
  ('vi', 'The owner left Badie, so the group is yours now.', 'Trưởng nhóm cũ đã rời Badie, nên nhóm này giờ do bạn quản lý.'),
  ('hi', 'You now run {group}', 'अब {group} आप चलाते हैं'),
  ('hi', 'The owner left Badie, so the group is yours now.', 'ग्रुप के मालिक ने Badie छोड़ दिया है, इसलिए अब यह ग्रुप आपका है।');
