-- 约球邮件改由 send-email 函数发：Resend 额度用完就换 Mailjet，和登录验证码共用同一套。
-- 发信服务的 API key 只放在函数的 Secrets 里，Vault 里的 resend_api_key 不再用。
-- 地址和暗号和推送一样：Vault 里的 project_url、push_secret；没配就不发。
-- 每批最多 50 封（Mailjet 一次最多收 50 封）

create or replace function public.send_notification_emails()
returns void language plpgsql security definer set search_path = '' as $$
declare
  url text;
  secret text;
  emails jsonb;
begin
  select decrypted_secret into url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_secret';
  if url is null or secret is null then return; end if;

  with picked as (
    update public.notifications n set emailed_at = now()
    where n.id in (select x.id from public.notifications x
                   where x.emailed_at is null and x.kind in ('offer', 'matched', 'cancelled', 'missed')
                     and x.created_at > now() - interval '1 hour'
                     and exists (select 1 from public.profiles pr where pr.id = x.user_id and pr.email_alerts)
                   order by x.id limit 50 for update skip locked)
    returning n.user_id, n.title, n.body, n.link)
  select jsonb_agg(jsonb_build_object(
      'from', 'Badie <games@badie.rsvp>',
      'to', u.email,
      'subject', p.title,
      'text', p.body || E'\n\nhttps://badie.rsvp' || coalesce(p.link, '/app/') || E'\n\n—\n' ||
              public.render_text(coalesce(pr.locale, 'en'), 'You get this because you turned on match emails. Turn them off anytime in Settings.')))
    into emails
    from picked p join auth.users u on u.id = p.user_id left join public.profiles pr on pr.id = p.user_id
    where u.email is not null;
  if emails is null then return; end if;

  perform net.http_post(url := rtrim(url, '/') || '/functions/v1/send-email', body := emails,
                        headers := jsonb_build_object('x-push-secret', secret, 'Content-Type', 'application/json'));
end
$$;
