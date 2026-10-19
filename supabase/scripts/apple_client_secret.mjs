// 生成 Supabase 网页 Apple 登录要的 Secret Key（用 .p8 私钥签的 ES256 JWT，Apple 规定最长 6 个月）。
// 在自己电脑上运行，私钥不离开本机，输出直接粘到 Supabase → Authentication → Providers → Apple：
//   node supabase/scripts/apple_client_secret.mjs <Team ID> <Key ID> <Services ID> <AuthKey_XXXX.p8 的路径>
import { readFileSync } from 'node:fs';

const [team, keyId, servicesId, keyPath] = process.argv.slice(2);
if (!keyPath) {
  console.error('用法：node supabase/scripts/apple_client_secret.mjs <Team ID> <Key ID> <Services ID> <.p8 路径>');
  process.exit(1);
}

const base64url = (bytes) => Buffer.from(bytes).toString('base64url');
const encode = (value) => base64url(JSON.stringify(value));
const der = Buffer.from(readFileSync(keyPath, 'utf8').replace(/-----[^-]+-----|\s/g, ''), 'base64');
const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
const now = Math.floor(Date.now() / 1000);
const days = 180;
const unsigned = `${encode({ alg: 'ES256', kid: keyId })}.${encode({ iss: team, iat: now, exp: now + days * 86400, aud: 'https://appleid.apple.com', sub: servicesId })}`;
const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned));
console.log(`${unsigned}.${base64url(new Uint8Array(signature))}`);
console.error(`有效到 ${new Date((now + days * 86400) * 1000).toISOString().slice(0, 10)}，记得在那之前重新生成。`);
