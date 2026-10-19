-- 推送通知：登记设备的校验、客户端看不到设备、推送服务取活和回报；约球邮件要自己打开
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid, 'p' || n || '@test.local' from generate_series(1, 3) n;
insert into public.profiles (id, nickname)
  select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid, 'Push' || n from generate_series(1, 3) n;

create function pg_temp.u(n int) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true);
$$;
create function pg_temp.devices(n int) returns int language sql security definer as $$
  select count(*)::int from public.push_devices where user_id = pg_temp.u(n)
$$;

-- 登记设备：要登录，格式要对，浏览器只接受各家浏览器的推送服务地址
select throws_ok($$ select public.register_push('apns', repeat('a', 64)) $$, '42501', null, '没登录不能登记');
select pg_temp.login(1);
select throws_ok($$ select public.register_push('fax', repeat('a', 64)) $$, '23514', null, '只有 apns / apns_sandbox / web');
select throws_ok($$ select public.register_push('apns', 'not-a-token') $$, '22023', null, 'iOS 令牌是十六进制');
select throws_ok($$ select public.register_push('web', 'https://evil.example.com/push/1', '{"p256dh": "k", "auth": "a"}') $$,
                 '22023', null, '浏览器推送地址只能是浏览器厂商的');
select throws_ok($$ select public.register_push('web', 'https://fcm.googleapis.com/fcm/send/abc123', '{"p256dh": "k"}') $$,
                 '22023', null, '浏览器推送要带两把公钥');
select lives_ok($$ select public.register_push('apns', repeat('a', 64)) $$, '登记 iPhone');
select lives_ok($$ select public.register_push('web', 'https://fcm.googleapis.com/fcm/send/abc123', '{"p256dh": "k", "auth": "a"}') $$,
                '登记 Chrome');
select lives_ok($$ select public.register_push('apns', repeat('a', 64)) $$, '重复登记同一台不出错');
select is(pg_temp.devices(1), 2, '两台设备');
select throws_ok($$ select * from public.push_devices $$, '42501', null, '客户端不能直接读设备表');

-- 同一台设备换了账号：转给新账号，旧账号不再收；别人注销不了我的设备
select pg_temp.login(2);
select public.register_push('web', 'https://fcm.googleapis.com/fcm/send/abc123', '{"p256dh": "k2", "auth": "a2"}');
select public.unregister_push(repeat('a', 64));
reset role;
select is(pg_temp.devices(2), 1, '新账号拿到这台 Chrome');
select is(pg_temp.devices(1), 1, '旧账号只剩 iPhone，别人注销不了');

-- 最多 10 台，多了删最旧的
select pg_temp.login(1);
select public.register_push('apns', lpad(n::text, 64, 'b')) from generate_series(1, 12) n;
reset role;
select is(pg_temp.devices(1), 10, '每人最多 10 台');

-- 推送服务的函数客户端不能调
select pg_temp.login(1);
select throws_ok($$ select public.claim_push_batch() $$, '42501', null, '客户端不能取推送任务');
select throws_ok($$ select public.push_done('{}', '{}') $$, '42501', null, '客户端不能回报推送结果');
reset role;

-- 约球邮件默认关，本人可以在设置里打开
select is((select count(*)::int from public.profiles where id in (pg_temp.u(1), pg_temp.u(2), pg_temp.u(3)) and email_alerts),
          0, '约球邮件默认关');
select pg_temp.login(2);
select lives_ok($$ update public.profiles set email_alerts = true where id = pg_temp.u(2) $$, '本人可以打开约球邮件');
reset role;

-- 邮件：只发给打开了的人，开着推送也照发（交给 send-email 函数，Vault 里配了地址和暗号才发）
select vault.create_secret('http://functions.test', 'project_url');
select vault.create_secret('s3cret', 'push_secret');
create function pg_temp.emailed(n int) returns boolean language sql security definer as $$
  select emailed_at is not null from public.notifications where user_id = pg_temp.u(n) order by id desc limit 1
$$;
select public.notify(pg_temp.u(2), 'matched', 'Game on!', 'x');
select public.notify(pg_temp.u(3), 'matched', 'Game on!', 'y');
select public.send_notification_emails();
select ok(pg_temp.emailed(2), '打开了邮件的人收邮件');
select ok(not pg_temp.emailed(3), '没打开的人不发邮件');
select is((select count(*)::int from net.http_request_queue
           where url = 'http://functions.test/functions/v1/send-email' and headers ->> 'x-push-secret' = 's3cret'),
          1, '一批邮件交给 send-email 函数，带暗号');
select ok((select convert_from(body, 'utf8')::jsonb -> 0 ->> 'to' from net.http_request_queue
           where url like '%/send-email' order by id desc limit 1) = 'p2@test.local', '收件人是打开了邮件的人');

-- 推送：只取有设备的人的新通知，每台设备一条（发过邮件也照推）；取过的不再取
set local role service_role;
select is((select jsonb_array_length(public.claim_push_batch())), 1, '只有用户 2 有设备，一台');
select is((select jsonb_array_length(public.claim_push_batch())), 0, '取过的不再取');

-- 回报：送达的记下来，失效的设备删掉
select public.push_done(array(select id from public.notifications where user_id = pg_temp.u(2)),
                        array['https://fcm.googleapis.com/fcm/send/abc123']);
reset role;
select ok((select pushed_at is not null from public.notifications where user_id = pg_temp.u(2) order by id desc limit 1), '记下已送达');
select is(pg_temp.devices(2), 0, '失效的设备删掉了');

select * from finish();
rollback;
