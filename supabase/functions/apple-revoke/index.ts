// 注销账号时撤销 Sign in with Apple 的授权（Apple 要求，Supabase 不会代办）：
// App 让用户用 Apple 再确认一次，拿到一次性的授权码（5 分钟内有效），这里换成 refresh token 再调 Apple 的撤销接口。
// Apple 的私钥（.p8）只放在这里的 Secrets：APPLE_TEAM_ID、APPLE_KEY_ID、APPLE_PRIVATE_KEY

const team = Deno.env.get('APPLE_TEAM_ID') ?? '';
const keyId = Deno.env.get('APPLE_KEY_ID') ?? '';
const privateKey = Deno.env.get('APPLE_PRIVATE_KEY') ?? '';
const clientId = Deno.env.get('APPLE_BUNDLE_ID') ?? 'com.badie.app';

const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const encode = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));

/** 给 Apple 的 client secret：用 .p8 私钥签的 ES256 JWT，5 分钟有效 */
async function clientSecret() {
  const der = Uint8Array.from(atob(privateKey.replace(/-----[^-]+-----|\s/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encode({ alg: 'ES256', kid: keyId })}.${encode({ iss: team, iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: clientId })}`;
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(new Uint8Array(signature))}`;
}

Deno.serve(async (request) => {
  // 只有登录的用户能调：拿调用者的令牌问登录服务（新旧两种 JWT 都适用，所以不用网关的 verify_jwt）
  const caller = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`, {
    headers: { Authorization: request.headers.get('Authorization') ?? '', apikey: request.headers.get('apikey') ?? '' },
  });
  if (!caller.ok) return new Response('unauthorized', { status: 401 });

  const { code } = await request.json().catch(() => ({}));
  if (typeof code !== 'string' || !code) return new Response('missing_code', { status: 400 });
  if (!team || !keyId || !privateKey) return new Response('not_configured', { status: 503 });

  const secret = await clientSecret();
  const form = (fields: Record<string, string>) => new URLSearchParams({ client_id: clientId, client_secret: secret, ...fields });
  const tokens = await fetch('https://appleid.apple.com/auth/token', { method: 'POST', body: form({ grant_type: 'authorization_code', code }) });
  if (!tokens.ok) return new Response('apple_token_failed', { status: 502 });
  const { refresh_token: refreshToken } = await tokens.json();
  const revoked = await fetch('https://appleid.apple.com/auth/revoke', {
    method: 'POST',
    body: form({ token: refreshToken, token_type_hint: 'refresh_token' }),
  });
  return new Response(null, { status: revoked.ok ? 204 : 502 });
});
