-- 安卓推送令牌的校验写错了（PostgreSQL 的正则次数不能超过 255，登记安卓手机时直接报错）：长度单独查

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
  -- FCM 的令牌：字母、数字和 : _ -，一般 150 多个字（正则的次数最多写到 255，长度单独查）
  if p_kind = 'fcm' and (length(p_token) not between 100 and 1000 or p_token !~ '^[A-Za-z0-9:_-]+$') then
    raise exception 'invalid_token' using errcode = '22023';
  end if;
  insert into public.push_devices (user_id, kind, token, keys)
    values (auth.uid(), p_kind, p_token, case when p_kind = 'web' then p_keys end)
    on conflict (token) do update set user_id = excluded.user_id, kind = excluded.kind, keys = excluded.keys, created_at = now();
  delete from public.push_devices where id in (
    select id from public.push_devices where user_id = auth.uid() order by created_at desc, id desc offset 10);
end
$$;
