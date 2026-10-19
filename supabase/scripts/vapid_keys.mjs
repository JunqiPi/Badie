// 生成浏览器推送（Web Push）用的 VAPID 密钥对，在自己电脑上运行一次：
//   node supabase/scripts/vapid_keys.mjs
// 公钥可以公开：填到 GitHub Variables 的 VAPID_PUBLIC_KEY，以及 Supabase Edge Function Secrets 的 VAPID_PUBLIC_KEY；
// 私钥只填到 Supabase Edge Function Secrets 的 VAPID_PRIVATE_KEY，别处都不要放。换了密钥，所有人要重新开一次通知
const { publicKey, privateKey } = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const base64url = (buffer) => Buffer.from(buffer).toString('base64url');
console.log(`VAPID_PUBLIC_KEY=${base64url(await crypto.subtle.exportKey('raw', publicKey))}`);
console.log(`VAPID_PRIVATE_KEY=${Buffer.from(await crypto.subtle.exportKey('pkcs8', privateKey)).toString('base64')}`);
