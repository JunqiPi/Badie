// 发信函数的测试：deno test --allow-env --allow-read supabase/functions/
// 不连网：fetch 换成假的，记下调了哪家
import assert from 'node:assert/strict';
import { authEmails, codeEmail, deliver, handle } from './mail.ts';

const calls: string[] = [];
function providers(answers: Record<string, number | Error>) {
  calls.length = 0;
  globalThis.fetch = (async (input: string | URL | Request) => {
    const host = new URL(String(input)).host;
    calls.push(host);
    const answer = answers[host];
    if (answer instanceof Error) throw answer;
    return new Response('{}', { status: answer ?? 500 });
  }) as typeof fetch;
}
const resendOk = 'api.resend.com', mailjetOk = 'api.mailjet.com';
Deno.env.set('RESEND_API_KEY', 're_test');
Deno.env.set('MAILJET_API_KEY', 'mj_key');
Deno.env.set('MAILJET_SECRET_KEY', 'mj_secret');
Deno.env.set('PUSH_SECRET', 'push');
const hookSecret = btoa('a secret of at least 24 bytes!!');
Deno.env.set('SEND_EMAIL_HOOK_SECRET', `v1,whsec_${hookSecret}`);

const email = codeEmail('a@test.local', 'signin', '123456');

Deno.test('邮件内容和本地用的模板一样', async () => {
  for (const [kind, file] of [['signin', 'otp.html'], ['recovery', 'recovery.html']] as const) {
    const template = await Deno.readTextFile(new URL(`../../templates/${file}`, import.meta.url));
    assert.equal(codeEmail('a@test.local', kind, '123456').html, template.replace('{{ .Token }}', '123456'));
  }
});

Deno.test('Resend 发成功就不找 Mailjet', async () => {
  providers({ [resendOk]: 200 });
  assert.equal(await deliver([email]), true);
  assert.deepEqual(calls, ['api.resend.com']);
});

Deno.test('Resend 额度用完、出错或超时就换 Mailjet', async () => {
  for (const failure of [429, 500, new Error('timed out')]) {
    providers({ [resendOk]: failure, [mailjetOk]: 200 });
    assert.equal(await deliver([email]), true);
    assert.deepEqual(calls, ['api.resend.com', 'api.mailjet.com']);
  }
});

Deno.test('没配 Resend 直接用 Mailjet；两家都不行算失败', async () => {
  Deno.env.delete('RESEND_API_KEY');
  providers({ [mailjetOk]: 200 });
  assert.equal(await deliver([email]), true);
  assert.deepEqual(calls, ['api.mailjet.com']);
  Deno.env.set('RESEND_API_KEY', 're_test');

  providers({ [resendOk]: 429, [mailjetOk]: 401 });
  assert.equal(await deliver([email]), false);
});

Deno.test('Auth 要发的邮件：验证码、重置密码、改邮箱两封、纯通知不发', () => {
  const user = { email: 'old@test.local', new_email: 'new@test.local' };
  const of = (type: string, extra = {}) => authEmails({ user, email_data: { email_action_type: type, token: '111111', ...extra } });
  assert.deepEqual(of('signup').map((e) => [e.to, e.subject]), [['old@test.local', 'Your Badie sign-in code']]);
  assert.deepEqual(of('recovery').map((e) => e.subject), ['Reset your Badie password']);
  assert.deepEqual(of('email_change', { token_new: '222222' }).map((e) => [e.to, e.text.includes('222222')]),
                   [['old@test.local', false], ['new@test.local', true]]);
  assert.deepEqual(of('password_changed_notification', { token: '' }), []);
});

async function signed(body: string, secret = hookSecret, timestamp = Math.floor(Date.now() / 1000)) {
  const id = 'msg_1';
  const key = await crypto.subtle.importKey('raw', Uint8Array.from(atob(secret), (c) => c.charCodeAt(0)),
                                            { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${id}.${timestamp}.${body}`));
  return new Request('http://local/send-email', {
    method: 'POST', body,
    headers: { 'webhook-id': id, 'webhook-timestamp': String(timestamp),
               'webhook-signature': `v1,${btoa(String.fromCharCode(...new Uint8Array(signature)))}` },
  });
}

Deno.test('Auth Hook：签名对才发；伪造、过期的拒绝', async () => {
  const body = JSON.stringify({ user: { email: 'a@test.local' }, email_data: { email_action_type: 'magiclink', token: '123456' } });
  providers({ [resendOk]: 200 });
  assert.equal((await handle(await signed(body))).status, 200);
  assert.deepEqual(calls, ['api.resend.com']);

  providers({ [resendOk]: 200 });
  assert.equal((await handle(await signed(body, btoa('somebody else secret 1234')))).status, 401);
  assert.equal((await handle(await signed(body, hookSecret, Math.floor(Date.now() / 1000) - 600))).status, 401);
  const forged = await signed(body);
  forged.headers.set('webhook-timestamp', 'soon');
  assert.equal((await handle(forged)).status, 401);
  assert.equal((await handle(new Request('http://local/send-email', { method: 'POST', body }))).status, 401);
  assert.deepEqual(calls, [], '没签名的一封都不发');
});

Deno.test('Auth Hook：两家都发不出去时告诉用户', async () => {
  providers({ [resendOk]: 429, [mailjetOk]: 500 });
  const body = JSON.stringify({ user: { email: 'a@test.local' }, email_data: { email_action_type: 'signup', token: '123456' } });
  const response = await handle(await signed(body));
  assert.equal(response.status, 503);
  assert.match((await response.json()).error.message, /try again/);
});

Deno.test('数据库发来的约球邮件要带对暗号', async () => {
  const body = JSON.stringify([{ from: 'Badie <games@badie.rsvp>', to: 'a@test.local', subject: 'Game confirmed', text: 'x' }]);
  providers({ [resendOk]: 200 });
  assert.equal((await handle(new Request('http://local', { method: 'POST', body, headers: { 'x-push-secret': 'wrong' } }))).status, 403);
  assert.deepEqual(calls, []);
  assert.equal((await handle(new Request('http://local', { method: 'POST', body, headers: { 'x-push-secret': 'push' } }))).status, 200);
  assert.deepEqual(calls, ['api.resend.com']);
});
