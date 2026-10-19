-- 推送通知：App（Apple 的 APNs）和浏览器（Web Push）都免费。
-- 新通知先推送；推送送达了就不再发邮件。没开推送的人照旧马上收邮件，开了推送但 2 分钟内没推到的也发邮件兜底

-- ---------------------------------------------------------------------------
-- 设备
-- ---------------------------------------------------------------------------

-- 一台设备一行：iOS 是设备令牌（开发版走 sandbox 环境），浏览器是推送地址 + 加密用的两把公钥
create table public.push_devices (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('apns', 'apns_sandbox', 'web')),
  token text not null unique check (length(token) between 16 and 1000),
  keys jsonb,
  created_at timestamptz not null default now()
);

create index push_devices_user_idx on public.push_devices (user_id);
alter table public.push_devices enable row level security;
-- 只通过下面的函数读写：客户端看不到任何设备（包括自己的推送地址）
revoke all on public.push_devices from anon, authenticated;

alter table public.notifications add column push_tried_at timestamptz, add column pushed_at timestamptz;

-- 登记这台设备；同一个地址换了账号就转给新账号。每人最多 10 台，多了删最旧的。
-- 浏览器的推送地址只接受几家浏览器厂商的推送服务（推送服务器会往这个地址发请求，不能让人填任意网址）
create function public.register_push(p_kind text, p_token text, p_keys jsonb default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_kind = 'web' and (p_token !~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|web\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)/'
                         or coalesce(p_keys ->> 'p256dh', '') = '' or coalesce(p_keys ->> 'auth', '') = '') then
    raise exception 'invalid_subscription' using errcode = '22023';
  end if;
  if p_kind <> 'web' and p_token !~ '^[0-9a-f]{64,200}$' then
    raise exception 'invalid_token' using errcode = '22023';
  end if;
  insert into public.push_devices (user_id, kind, token, keys)
    values (auth.uid(), p_kind, p_token, case when p_kind = 'web' then p_keys end)
    on conflict (token) do update set user_id = excluded.user_id, kind = excluded.kind, keys = excluded.keys, created_at = now();
  delete from public.push_devices where id in (
    select id from public.push_devices where user_id = auth.uid() order by created_at desc, id desc offset 10);
end
$$;

-- 退出登录或关掉推送：这台设备不再收这个账号的推送
create function public.unregister_push(p_token text)
returns void language sql security definer set search_path = '' as $$
  delete from public.push_devices where token = p_token and user_id = auth.uid()
$$;

-- ---------------------------------------------------------------------------
-- 推送服务（Edge Function send-push）用的两个函数，只有服务端密钥能调
-- ---------------------------------------------------------------------------

-- 取活：2 分钟内的新通知、还没推过，配上收件人的每台设备
create function public.claim_push_batch()
returns jsonb language sql security definer set search_path = '' as $$
  with picked as (
    update public.notifications n set push_tried_at = now()
    where n.id in (select x.id from public.notifications x
                   where x.push_tried_at is null and x.emailed_at is null and x.created_at > now() - interval '2 minutes'
                     and exists (select 1 from public.push_devices d where d.user_id = x.user_id)
                   order by x.id limit 200 for update skip locked)
    returning n.id, n.user_id, n.title, n.body, n.link)
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'kind', d.kind, 'token', d.token, 'keys', d.keys,
                                               'title', p.title, 'body', p.body, 'link', p.link) order by p.id), '[]')
  from picked p join public.push_devices d on d.user_id = p.user_id
$$;

-- 结果：至少一台设备收到的通知记为已送达（就不再发邮件）；厂商说已失效的设备删掉
create function public.push_done(p_delivered bigint[], p_dead text[])
returns void language sql security definer set search_path = '' as $$
  update public.notifications set pushed_at = now() where id = any(p_delivered) and pushed_at is null;
  delete from public.push_devices where token = any(p_dead);
$$;

-- ---------------------------------------------------------------------------
-- 有新通知、收件人又有设备时，马上叫推送服务（不用等每分钟的定时任务）。
-- 地址和暗号放在 Vault：project_url、push_secret；没配就什么都不做，邮件照常发
-- ---------------------------------------------------------------------------

create function public.push_new_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  url text;
  secret text;
begin
  if not exists (select 1 from fresh f join public.push_devices d on d.user_id = f.user_id) then return null; end if;
  select decrypted_secret into url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_secret';
  if url is null or secret is null then return null; end if;
  -- pg_net 在事务提交后才真正发请求，推送服务一定能读到这些新通知
  perform net.http_post(url := rtrim(url, '/') || '/functions/v1/send-push', body := '{}'::jsonb,
                        headers := jsonb_build_object('x-push-secret', secret, 'Content-Type', 'application/json'));
  return null;
end
$$;

create trigger notifications_push after insert on public.notifications
  referencing new table as fresh for each statement execute function public.push_new_notifications();

-- ---------------------------------------------------------------------------
-- 邮件变成兜底：推送已经送达的不发；有设备的人先等 2 分钟给推送机会，没设备的马上发
-- ---------------------------------------------------------------------------

create or replace function public.send_notification_emails()
returns void language plpgsql security definer set search_path = '' as $$
declare
  api_key text;
  emails jsonb;
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name = 'resend_api_key';
  if api_key is null then return; end if;

  with picked as (
    update public.notifications n set emailed_at = now()
    where n.id in (select x.id from public.notifications x
                   where x.emailed_at is null and x.pushed_at is null and x.kind in ('offer', 'matched', 'cancelled', 'missed')
                     and x.created_at > now() - interval '1 hour'
                     and (x.created_at < now() - interval '2 minutes'
                          or not exists (select 1 from public.push_devices d where d.user_id = x.user_id))
                   order by x.id limit 100 for update skip locked)
    returning n.user_id, n.title, n.body, n.link)
  select jsonb_agg(jsonb_build_object(
      'from', 'Badie <games@badie.rsvp>',
      'to', jsonb_build_array(u.email),
      'subject', p.title,
      'text', p.body || E'\n\nhttps://badie.rsvp' || coalesce(p.link, '/app/') || E'\n\n—\n' ||
              public.render_text(coalesce(pr.locale, 'en'), 'You get this because you asked Badie to find you a game.')))
    into emails
    from picked p join auth.users u on u.id = p.user_id left join public.profiles pr on pr.id = p.user_id
    where u.email is not null;
  if emails is null then return; end if;

  perform net.http_post(url := 'https://api.resend.com/emails/batch', body := emails,
                        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'));
end
$$;

revoke execute on function public.register_push(text, text, jsonb), public.unregister_push(text) from public, anon;
grant execute on function public.register_push(text, text, jsonb), public.unregister_push(text) to authenticated;
revoke execute on function public.claim_push_batch(), public.push_done(bigint[], text[]), public.push_new_notifications()
  from public, anon, authenticated;
grant execute on function public.claim_push_batch(), public.push_done(bigint[], text[]) to service_role;
