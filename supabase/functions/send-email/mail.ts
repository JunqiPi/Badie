// 发邮件：先用 Resend，当天 / 当月额度用完或出错就换 Mailjet（两家免费额度合起来每天约 300 封）。
// Mailjet 超过当天额度不报错，而是排到第二天才发，所以它只做后备、放在最后。
//
// 两种调用：
// - Supabase Auth 的 Send Email Hook（注册确认码、验证码登录、重置密码）：Standard Webhooks 签名，
//   密钥 SEND_EMAIL_HOOK_SECRET（后台开 Hook 时生成的 v1,whsec_…）
// - 数据库发约球邮件：带 x-push-secret 暗号（和推送同一个），正文是邮件数组
//
// Secrets：RESEND_API_KEY；MAILJET_API_KEY + MAILJET_SECRET_KEY。没配的那家直接跳过。只用 WebCrypto，不引第三方库

export type Email = { from: string; to: string; subject: string; text: string; html?: string };

const env = (name: string) => Deno.env.get(name) ?? '';
const utf8 = (text: string) => new TextEncoder().encode(text);
const fromBase64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
// Auth 最多等 5 秒，两家各给 2 秒
const timeout = () => AbortSignal.timeout(2000);

// ---------------------------------------------------------------------------
// 两家发信服务：成功返回 true；没配、被拒、超时都返回 false，换下一家
// ---------------------------------------------------------------------------

async function resend(emails: Email[]) {
  const key = env('RESEND_API_KEY');
  if (!key) return false;
  const response = await fetch('https://api.resend.com/emails/batch', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(emails.map(({ to, ...email }) => ({ ...email, to: [to] }))),
    signal: timeout(),
  });
  if (!response.ok) console.error(`resend ${response.status}: ${await response.text()}`);
  return response.ok;
}

async function mailjet(emails: Email[]) {
  const key = env('MAILJET_API_KEY'), secret = env('MAILJET_SECRET_KEY');
  if (!key || !secret) return false;
  // “Badie <games@badie.rsvp>” 拆成名字和地址
  const sender = (from: string) => {
    const [, name, address] = from.match(/^(.*?)\s*<(.+)>$/) ?? [, '', from];
    return { Name: name, Email: address };
  };
  const response = await fetch('https://api.mailjet.com/v3.1/send', {
    method: 'POST',
    headers: { Authorization: `Basic ${btoa(`${key}:${secret}`)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      Messages: emails.map((email) => ({
        From: sender(email.from), To: [{ Email: email.to }], Subject: email.subject, TextPart: email.text, HTMLPart: email.html,
      })),
    }),
    signal: timeout(),
  });
  if (!response.ok) console.error(`mailjet ${response.status}: ${await response.text()}`);
  return response.ok;
}

export async function deliver(emails: Email[]) {
  for (const send of [resend, mailjet]) {
    try {
      if (await send(emails)) return true;
    } catch (error) {
      console.error(`${send.name}: ${error}`);
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// 登录邮件：内容和 supabase/templates 里本地用的模板一样（测试会对比）
// ---------------------------------------------------------------------------

const footer = 'Badie · find people to play badminton with · badie.rsvp';
const texts = {
  signin: ['Your Badie sign-in code', 'Enter this code to sign in. It expires in 1 hour. If you didn\'t ask for it, you can ignore this email.'],
  recovery: ['Reset your Badie password', 'Enter this code in Badie with your new password. It expires in 1 hour. If you didn\'t ask for it, you can ignore this email. Your password won\'t change.'],
  other: ['Your Badie code', 'Enter this code in Badie. It expires in 1 hour. If you didn\'t ask for it, you can ignore this email.'],
};

export function codeEmail(to: string, kind: keyof typeof texts, code: string): Email {
  const [subject, body] = texts[kind];
  return {
    from: 'Badie <noreply@badie.rsvp>',
    to,
    subject,
    text: `${subject}\n\n${code}\n\n${body}\n\n${footer}`,
    html: `<h2>${subject}</h2>
<p style="font-size:28px;font-weight:800;letter-spacing:6px">${code}</p>
<p>${body}</p>
<p style="color:#6b6b6b;font-size:13px">${footer}</p>
`,
  };
}

type HookPayload = {
  user: { email?: string; new_email?: string };
  email_data: { email_action_type: string; token?: string; token_new?: string };
};

/** Auth 要发的邮件。改邮箱（默认的安全模式）两边各发一封：旧地址收 token，新地址收 token_new；
 *  只是通知、没有验证码的（改了密码之类，后台默认关）不发 */
export function authEmails({ user, email_data: data }: HookPayload): Email[] {
  const type = data.email_action_type;
  const kind = type === 'recovery' ? 'recovery' : ['signup', 'magiclink', 'email'].includes(type) ? 'signin' : 'other';
  const codes: [string | undefined, string | undefined][] =
    type === 'email_change' ? [[user.email, data.token], [user.new_email, data.token_new]] : [[user.email, data.token]];
  return codes.filter(([to, code]) => to && code).map(([to, code]) => codeEmail(to!, kind, code!));
}

/** Standard Webhooks 签名：HMAC-SHA256(id.timestamp.body)，5 分钟内有效 */
export async function verified(request: Request, body: string) {
  const secret = env('SEND_EMAIL_HOOK_SECRET').replace(/^v1,whsec_/, '');
  const id = request.headers.get('webhook-id'), timestamp = request.headers.get('webhook-timestamp');
  const signatures = request.headers.get('webhook-signature');
  if (!secret || !id || !timestamp || !signatures || !(Math.abs(Date.now() / 1000 - Number(timestamp)) <= 300)) return false;
  const key = await crypto.subtle.importKey('raw', fromBase64(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  for (const signature of signatures.split(' ')) {
    const [version, value] = signature.split(',');
    // crypto.subtle.verify 是定时比较，不会从响应时间泄露签名
    if (version === 'v1' && value && await crypto.subtle.verify('HMAC', key, fromBase64(value), utf8(`${id}.${timestamp}.${body}`))) {
      return true;
    }
  }
  return false;
}

const json = (body: object, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

export async function handle(request: Request) {
  const body = await request.text();

  // 数据库发来的约球邮件
  if (request.headers.has('x-push-secret')) {
    if (!env('PUSH_SECRET') || request.headers.get('x-push-secret') !== env('PUSH_SECRET')) return new Response('forbidden', { status: 403 });
    return (await deliver(JSON.parse(body))) ? json({}) : json({ error: 'not sent' }, 502);
  }

  // Auth Hook：出错时 Auth 会把 message 显示给用户
  if (!(await verified(request, body).catch(() => false))) {
    return json({ error: { http_code: 401, message: 'Invalid signature' } }, 401);
  }
  const emails = authEmails(JSON.parse(body));
  if (emails.length && !(await deliver(emails))) {
    return json({ error: { http_code: 503, message: 'We couldn’t send the email. Wait a few minutes and try again.' } }, 503);
  }
  return json({});
}
