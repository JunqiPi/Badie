-- 照片头像（和 iOS 一致：裁成 320×320 的 JPEG）：
-- - 存在公开的 avatars 桶里，文件名是 <用户 id>/<随机 uuid>.jpg，猜不到；地址只给打过交道的人（和资料页的可见范围一样）
-- - 每张最大 256 KB、只收 JPEG；每人文件夹里最多 3 个文件（换头像时先传新的、再删旧的）
-- - 管理员可以撤下不合适的照片

alter table public.profiles add column avatar_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('avatars', 'avatars', true, 262144, array['image/jpeg'])
  on conflict (id) do update set public = true, file_size_limit = 262144, allowed_mime_types = array['image/jpeg'];

-- 我文件夹里有几个文件（策略里要绕过行级权限数）
create function public.my_avatar_file_count()
returns bigint language sql stable security definer set search_path = '' as $$
  select count(*) from storage.objects where bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
$$;

create policy "players upload their own avatar" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
              and public.my_avatar_file_count() < 3);
create policy "players see their own avatar files" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "players delete their own avatar files" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- 换头像：p_path 是刚传上去的文件（null = 改回文字头像）
create function public.set_avatar(p_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_path is not null and (p_path !~ ('^' || me || '/[0-9a-f-]{36}\.jpg$')
                             or not exists (select 1 from storage.objects where bucket_id = 'avatars' and name = p_path)) then
    raise exception 'invalid_avatar' using errcode = '22023';
  end if;
  update public.profiles set avatar_path = p_path where id = me;
end
$$;

-- 一批球友的头像地址（只给打过交道、没有屏蔽关系的人；最多 100 个）
create function public.avatars(p_users uuid[])
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'path', p.avatar_path)), '[]')
  from public.profiles p
  where p.id = any (p_users[1:100]) and p.avatar_path is not null
    and public.related(auth.uid(), p.id) and not public.blocked_between(auth.uid(), p.id)
$$;

-- 管理员撤下照片（文件留给本人下次换头像时清理），记进审核日志
create function public.admin_clear_avatar(p_user uuid, p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_admin();
  update public.profiles set avatar_path = null where id = p_user;
  insert into public.moderation_log (admin_id, target_type, target_id, action, note)
    values (auth.uid(), 'avatar', p_user::text, 'clear', left(coalesce(p_note, ''), 500));
end
$$;

-- 资料页：加上照片
create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', pr.verified_kind,
    'avatar', pr.avatar_path)
  from public.player_card_base(p_user) base, public.win_rate(p_user) w, public.profiles pr
  where base is not null and pr.id = p_user
$$;

revoke execute on function public.my_avatar_file_count() from public, anon;
grant execute on function public.my_avatar_file_count() to authenticated;
revoke execute on function public.set_avatar(text), public.avatars(uuid[]), public.admin_clear_avatar(uuid, text) from public, anon;
grant execute on function public.set_avatar(text), public.avatars(uuid[]), public.admin_clear_avatar(uuid, text) to authenticated;
