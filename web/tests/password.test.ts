// 密码规则：长度，和“泄露过的密码”查询（只发 SHA-1 前 5 位，查不了就放行）
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { passwordProblem } from '../src/app/password.ts';

// "password" 的 SHA-1 是 5BAA6 1E4C9B93F3F0682250B6CF8331B7EE68FD8
const list = (lines: string[]) => (async (url: string) => {
  assert.equal(url, 'https://api.pwnedpasswords.com/range/5BAA6', '只发前 5 位');
  return new Response(lines.join('\r\n'));
}) as typeof fetch;

test('too short', async () => {
  assert.match((await passwordProblem('short', list([])))!, /at least 8/);
});

test('breached passwords are refused', async () => {
  assert.match((await passwordProblem('password', list(['0018A45C4D1DEF81644B54AB7F969B88D65:1', '1E4C9B93F3F0682250B6CF8331B7EE68FD8:9545824'])))!, /data breach/);
});

test('padding entries (count 0) do not count', async () => {
  assert.equal(await passwordProblem('password', list(['1E4C9B93F3F0682250B6CF8331B7EE68FD8:0'])), undefined);
});

test('the check fails open when the service is unreachable', async () => {
  const offline = (async () => { throw new TypeError('offline'); }) as typeof fetch;
  assert.equal(await passwordProblem('correct horse battery', offline), undefined);
});

test('too long for bcrypt', async () => {
  assert.match((await passwordProblem('x'.repeat(73), list([])))!, /too long/);
});
