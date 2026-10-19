// 密码规则：至少 8 位，不强制大小写、数字、符号（NIST 800-63B 的建议）；注册、重设、修改时查一下是不是泄露过的密码。
// 查法是 k-匿名：只把 SHA-1 的前 5 位发给 Have I Been Pwned，密码本身不离开浏览器。查不了（离线、超时）就放行
import { t } from './i18n.ts';

export const MIN_PASSWORD = 8;
/** Supabase 用 bcrypt，超过 72 字节的部分不起作用 */
const MAX_BYTES = 72;

/** 返回要显示给用户的问题；没问题返回 undefined */
export async function passwordProblem(password: string, lookup: typeof fetch = fetch): Promise<string | undefined> {
  if (password.length < MIN_PASSWORD) return t('Use at least {n} characters.', { n: MIN_PASSWORD });
  if (new TextEncoder().encode(password).length > MAX_BYTES) return t('That password is too long. Use a shorter one.');
  if (await leaked(password, lookup)) return t('This password has appeared in a data breach. Choose a different one.');
}

async function leaked(password: string, lookup: typeof fetch) {
  try {
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-1', new TextEncoder().encode(password)));
    const hash = [...digest].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
    // Add-Padding：回复里混进次数为 0 的假条目，别人看流量大小也猜不出是哪个前缀
    const response = await lookup(`https://api.pwnedpasswords.com/range/${hash.slice(0, 5)}`,
                                  { headers: { 'Add-Padding': 'true' }, signal: AbortSignal.timeout(4000) });
    if (!response.ok) return false;
    return (await response.text()).split('\n').some((line) => {
      const [suffix, count] = line.trim().split(':');
      return suffix === hash.slice(5) && Number(count) > 0;
    });
  } catch {
    return false;
  }
}
