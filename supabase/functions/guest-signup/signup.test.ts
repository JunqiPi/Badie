// 访客报名函数的测试：deno test --allow-env --allow-read supabase/functions/
// 不连网：fetch 换成假的，记下调了谁、带了什么
import assert from 'node:assert/strict';
import { clientIp, handle } from './signup.ts';

const calls: { url: string; body: string; headers: Headers }[] = [];
function network(answers: { captcha?: boolean; database?: [number, object] }) {
  calls.length = 0;
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, body: String(init?.body ?? ''), headers: new Headers(init?.headers) });
    if (url.includes('challenges.cloudflare.com')) return Response.json({ success: answers.captcha ?? false });
    const [status, body] = answers.database ?? [200, {}];
    return Response.json(body, { status });
  }) as typeof fetch;
}
Deno.env.set('SUPABASE_URL', 'http://db.test');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'service-jwt');

const signUp = (body: object) =>
  handle(new Request('http://fn.test', { method: 'POST', body: JSON.stringify(body), headers: { 'x-forwarded-for': '203.0.113.5, 10.0.0.1' } }));
const fields = { code: 'abcd1234', session: '00000000-0000-0000-0000-000000000001', name: 'Tina', captcha: 'token' };

Deno.test('取访客的 IP：x-forwarded-for 的第一个', () => {
  assert.equal(clientIp(new Request('http://fn.test', { headers: { 'x-forwarded-for': '203.0.113.5, 10.0.0.1' } })), '203.0.113.5');
});

Deno.test('人机验证没过：不调数据库', async () => {
  Deno.env.set('TURNSTILE_SECRET_KEY', 'secret');
  network({ captcha: false });
  const response = await signUp(fields);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { message: 'captcha_failed' });
  assert.equal(calls.length, 1);
});

Deno.test('验证通过：用服务端密钥调 guest_sign_up，带上 IP', async () => {
  Deno.env.set('TURNSTILE_SECRET_KEY', 'secret');
  network({ captcha: true, database: [200, { status: 'confirmed', token: 't' }] });
  const response = await signUp(fields);
  assert.deepEqual(await response.json(), { status: 'confirmed', token: 't' });
  const call = calls[1];
  assert.equal(call.url, 'http://db.test/rest/v1/rpc/guest_sign_up');
  assert.equal(call.headers.get('Authorization'), 'Bearer service-jwt');
  assert.equal(JSON.parse(call.body).p_ip, '203.0.113.5');
  assert.ok(calls[0].body.includes('remoteip=203.0.113.5'));
});

Deno.test('数据库报的错原样转给网页；没配人机验证的密钥时在日志里警告', async () => {
  Deno.env.delete('TURNSTILE_SECRET_KEY');
  const warnings: string[] = [];
  const warn = console.warn;
  console.warn = (message: string) => warnings.push(message);
  network({ database: [400, { code: '54000', message: 'guest_spots_full' }] });
  const response = await signUp(fields).finally(() => (console.warn = warn));
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { message: 'guest_spots_full' });
  assert.ok(warnings.some((w) => w.includes('TURNSTILE_SECRET_KEY')));
});

Deno.test('网页先发的 OPTIONS 预检', async () => {
  const response = await handle(new Request('http://fn.test', { method: 'OPTIONS' }));
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
});
