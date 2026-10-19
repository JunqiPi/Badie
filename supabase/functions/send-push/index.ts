// 推送服务：数据库有新通知时调用（带 x-push-secret 暗号），取一批“通知 × 设备”，
// 发给 Apple（iOS App）和浏览器的推送服务。只用 WebCrypto，不引第三方库。
// 送达的告诉数据库，厂商说已失效的设备删掉；没配密钥的那一类直接算没送达。
//
// Secrets：PUSH_SECRET（和 Vault 里的 push_secret 一样）；
// iOS：APPLE_TEAM_ID + APNS_KEY_ID / APNS_PRIVATE_KEY（没有就用 Apple 登录那把 APPLE_KEY_ID / APPLE_PRIVATE_KEY）；
// 浏览器：VAPID_PUBLIC_KEY、VAPID_PRIVATE_KEY（supabase/scripts/vapid_keys.mjs 生成）

type Item = { id: number; kind: 'apns' | 'apns_sandbox' | 'web'; token: string; keys?: { p256dh: string; auth: string }; title: string; body: string; link?: string };
type Result = 'ok' | 'dead' | 'failed';

const env = (name: string) => Deno.env.get(name) ?? '';
const bundleId = env('APPLE_BUNDLE_ID') || 'com.badie.app';
// 新式密钥是 JSON（取 default），旧式是一串 JWT
const serviceKey: string = JSON.parse(env('SUPABASE_SECRET_KEYS') || '{}').default ?? env('SUPABASE_SERVICE_ROLE_KEY');

const utf8 = (text: string) => new TextEncoder().encode(text);
const concat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  parts.reduce((offset, p) => (out.set(p, offset), offset + p.length), 0);
  return out;
};
const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const fromBase64url = (text: string) => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

/** ES256 的 JWT：私钥是 PKCS8（.p8 文件的内容，或去掉头尾的 base64） */
async function jwt(header: object, claims: object, pkcs8: string) {
  const der = Uint8Array.from(atob(pkcs8.replace(/-----[^-]+-----|\s/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const unsigned = `${base64url(utf8(JSON.stringify(header)))}.${base64url(utf8(JSON.stringify(claims)))}`;
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, utf8(unsigned));
  return `${unsigned}.${base64url(new Uint8Array(signature))}`;
}

async function rpc(name: string, body: object = {}) {
  const headers: Record<string, string> = { apikey: serviceKey, 'Content-Type': 'application/json' };
  if (!serviceKey.startsWith('sb_secret_')) headers.Authorization = `Bearer ${serviceKey}`;
  const response = await fetch(`${env('SUPABASE_URL')}/rest/v1/rpc/${name}`, { method: 'POST', headers, body: JSON.stringify(body) });
  if (!response.ok) throw new Error(`${name}: ${response.status}`);
  return response.status === 204 ? null : response.json();
}

// ---------------------------------------------------------------------------
// iOS：Apple 的 APNs（HTTP/2）。令牌 1 小时内有效，Apple 不让频繁换：按半小时取整，同一时段用同一个
// ---------------------------------------------------------------------------

let apnsToken = { iat: 0, value: '' };
async function apnsJwt() {
  const iat = Math.floor(Date.now() / 1000 / 1800) * 1800;
  if (apnsToken.iat !== iat) {
    const value = await jwt({ alg: 'ES256', kid: env('APNS_KEY_ID') || env('APPLE_KEY_ID') }, { iss: env('APPLE_TEAM_ID'), iat },
                            env('APNS_PRIVATE_KEY') || env('APPLE_PRIVATE_KEY'));
    apnsToken = { iat, value };
  }
  return apnsToken.value;
}

async function sendApns(item: Item): Promise<Result> {
  const host = item.kind === 'apns_sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  const response = await fetch(`https://${host}/3/device/${item.token}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${await apnsJwt()}`,
      'apns-topic': bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600),
    },
    body: JSON.stringify({ aps: { alert: { title: item.title, body: item.body }, sound: 'default' }, link: item.link }),
  });
  if (response.ok) return 'ok';
  const { reason } = await response.json().catch(() => ({ reason: '' }));
  return response.status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered' ? 'dead' : 'failed';
}

// ---------------------------------------------------------------------------
// 浏览器：Web Push。内容按 RFC 8291（aes128gcm）加密，只有那个浏览器能解开；身份用 VAPID（RFC 8292）
// ---------------------------------------------------------------------------

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, length: number) {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, length * 8));
}

export async function encrypt(text: string, keys: { p256dh: string; auth: string }) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const browserKey = fromBase64url(keys.p256dh);
  const local = (await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits'])) as CryptoKeyPair;
  const localKey = new Uint8Array(await crypto.subtle.exportKey('raw', local.publicKey));
  const peer = await crypto.subtle.importKey('raw', browserKey, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: peer }, local.privateKey, 256));

  const ikm = await hkdf(fromBase64url(keys.auth), shared, concat(utf8('WebPush: info\0'), browserKey, localKey), 32);
  const cek = await hkdf(salt, ikm, utf8('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, utf8('Content-Encoding: nonce\0'), 12);
  const aes = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  // 整条消息一个记录：内容后面加 0x02 表示最后一个记录
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aes, concat(utf8(text), new Uint8Array([2]))));

  const header = new Uint8Array(21);
  header.set(salt);
  new DataView(header.buffer).setUint32(16, 4096);
  header[20] = localKey.length;
  return concat(header, localKey, cipher);
}

async function sendWeb(item: Item): Promise<Result> {
  const endpoint = new URL(item.token);
  const vapid = await jwt({ typ: 'JWT', alg: 'ES256' },
                          { aud: endpoint.origin, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: 'https://badie.rsvp' },
                          env('VAPID_PRIVATE_KEY'));
  const response = await fetch(item.token, {
    method: 'POST',
    headers: {
      Authorization: `vapid t=${vapid}, k=${env('VAPID_PUBLIC_KEY')}`,
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      TTL: '3600',
      Urgency: 'high',
    },
    body: await encrypt(JSON.stringify({ title: item.title, body: item.body, link: item.link }), item.keys!),
  });
  if (response.ok) return 'ok';
  return response.status === 404 || response.status === 410 ? 'dead' : 'failed';
}

// ---------------------------------------------------------------------------

Deno.serve(async (request) => {
  if (!env('PUSH_SECRET') || request.headers.get('x-push-secret') !== env('PUSH_SECRET')) return new Response('forbidden', { status: 403 });

  const items: Item[] = await rpc('claim_push_batch');
  const delivered = new Set<number>();
  const dead: string[] = [];
  await Promise.all(items.map(async (item) => {
    const result = await (item.kind === 'web' ? sendWeb(item) : sendApns(item)).catch((): Result => 'failed');
    if (result === 'ok') delivered.add(item.id);
    if (result === 'dead') dead.push(item.token);
  }));
  await rpc('push_done', { p_delivered: [...delivered], p_dead: dead });
  return Response.json({ sent: items.length, delivered: delivered.size, dead: dead.length });
});
