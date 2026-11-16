-- 安卓推送：设备登记加一种 fcm（Firebase Cloud Messaging 的令牌）。
-- 发送在 functions/send-push（要在 Supabase 的 Secrets 里填 FCM_SERVICE_ACCOUNT，没填时安卓设备算没送达，其他照常）

alter table public.push_devices drop constraint push_devices_kind_check;
alter table public.push_devices add constraint push_devices_kind_check check (kind in ('apns', 'apns_sandbox', 'web', 'fcm'));

create or replace function public.register_push(p_kind text, p_token text, p_keys jsonb default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_kind = 'web' and (p_token !~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|web\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)/'
                         or coalesce(p_keys ->> 'p256dh', '') = '' or coalesce(p_keys ->> 'auth', '') = '') then
    raise exception 'invalid_subscription' using errcode = '22023';
  end if;
  if p_kind in ('apns', 'apns_sandbox') and p_token !~ '^[0-9a-f]{64,200}$' then
    raise exception 'invalid_token' using errcode = '22023';
  end if;
  -- FCM 的令牌：字母、数字和 : _ -，一般 150 多个字
  if p_kind = 'fcm' and p_token !~ '^[A-Za-z0-9:_-]{100,1000}$' then
    raise exception 'invalid_token' using errcode = '22023';
  end if;
  insert into public.push_devices (user_id, kind, token, keys)
    values (auth.uid(), p_kind, p_token, case when p_kind = 'web' then p_keys end)
    on conflict (token) do update set user_id = excluded.user_id, kind = excluded.kind, keys = excluded.keys, created_at = now();
  delete from public.push_devices where id in (
    select id from public.push_devices where user_id = auth.uid() order by created_at desc, id desc offset 10);
end
$$;
