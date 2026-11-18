// 访客报名（不用登录的网页 badie.rsvp/g/…）：先向 Cloudflare 核对 Turnstile，再用服务端密钥调数据库的 guest_sign_up。
// 名额、上限、每个 IP 每小时 10 次都在数据库里查；数据库报的错原样转给网页（{ message: 'guest_spots_full' }）。
//
// Secrets：TURNSTILE_SECRET_KEY（Cloudflare → Turnstile 里网站那个组件的 Secret Key，和登录用的同一个）。
// 没配时不核对（本机、CI），每次报名在日志里写一条警告；正式环境一定要配。SUPABASE_URL 和服务端密钥是平台自带的

const env = (name: string) => Deno.env.get(name) ?? '';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: object, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

/** 访客的 IP：网关写在 x-forwarded-for 的第一个 */
export const clientIp = (request: Request) => request.headers.get('x-forwarded-for')?.split(',')[0].trim() ?? '';

/** Turnstile 的 token 是真的（没配密钥时不查） */
export async function human(token: unknown, ip: string) {
  const secret = env('TURNSTILE_SECRET_KEY');
  if (!secret) {
    console.warn('TURNSTILE_SECRET_KEY 没配：访客报名没有核对人机验证。到 Supabase → Edge Functions → Secrets 加上');
    return true;
  }
  if (typeof token !== 'string' || !token) return false;
  const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    body: new URLSearchParams({ secret, response: token, remoteip: ip }),
  });
  return response.ok && (await response.json()).success === true;
}

/** 用服务端密钥调 guest_sign_up（网页的 key 调不了它）。新式密钥是 JSON（取 default），旧式是一串 JWT */
function signUp(args: Record<string, unknown>) {
  const key: string = JSON.parse(env('SUPABASE_SECRET_KEYS') || '{}').default ?? env('SUPABASE_SERVICE_ROLE_KEY');
  const headers: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' };
  if (!key.startsWith('sb_secret_')) headers.Authorization = `Bearer ${key}`;
  return fetch(`${env('SUPABASE_URL')}/rest/v1/rpc/guest_sign_up`, { method: 'POST', headers, body: JSON.stringify(args) });
}

export async function handle(request: Request) {
  if (request.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (request.method !== 'POST') return json({ message: 'method_not_allowed' }, 405);
  const body = await request.json().catch(() => ({}));
  const ip = clientIp(request);
  if (!(await human(body.captcha, ip))) return json({ message: 'captcha_failed' }, 400);

  const response = await signUp({
    p_code: body.code ?? null, p_session: body.session ?? null, p_name: body.name ?? null,
    p_email: body.email ?? null, p_locale: body.locale ?? null, p_ip: ip,
  });
  const result = await response.json().catch(() => ({}));
  return response.ok ? json(result) : json({ message: result.message ?? 'failed' }, 400);
}
