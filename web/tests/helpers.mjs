// 端到端测试共用：注册、登录，验证码从本地 Supabase 的收件箱（Mailpit）里拿
const mailpit = process.env.MAILPIT_URL ?? 'http://127.0.0.1:54324';
export const base = process.env.BASE_URL ?? 'http://127.0.0.1:4321';

/** 发到这个邮箱的最新一封邮件里的 6 位码；already 是之前已经收到的封数，等新的一封到了再取 */
export async function emailedCode(email, already = 0) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const { messages = [] } = await (await fetch(`${mailpit}/api/v1/messages`)).json();
    const mine = messages.filter((m) => m.To?.some((to) => to.Address === email));
    const message = mine.length > already ? mine[0] : undefined;
    if (message) {
      const full = await (await fetch(`${mailpit}/api/v1/message/${message.ID}`)).json();
      const code = (full.Text || full.HTML).match(/\b\d{6,10}\b/)?.[0];
      if (code) return code;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`no sign-in email for ${email}`);
}

/** 发到这个邮箱的邮件数 */
export async function emailCount(email) {
  const { messages = [] } = await (await fetch(`${mailpit}/api/v1/messages`)).json();
  return messages.filter((m) => m.To?.some((to) => to.Address === email)).length;
}

export const password = 'shuttle rally court nine';

/** 不连真正的泄露密码库（测试不依赖外网）：默认当作没泄露，leaked 里的密码当作泄露过 */
export async function pwnedPasswords(page, leaked = []) {
  const { createHash } = await import('node:crypto');
  const lines = leaked.map((p) => `${createHash('sha1').update(p).digest('hex').toUpperCase().slice(5)}:42`);
  await page.route('https://api.pwnedpasswords.com/range/**', (route) => route.fulfill({
    body: lines.join('\r\n'),
    headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Add-Padding' },
  }));
}

/** 用邮箱 + 密码注册（输入邮件里的确认码）并建好资料，停在定级问卷 */
export async function signUp(page, email, nickname) {
  page.on('pageerror', (error) => {
    throw error;
  });
  await pwnedPasswords(page);
  await page.goto(`${base}/signin/?new`);
  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Password', { exact: true }).fill(password);
  await page.getByRole('button', { name: 'Create account' }).click();
  await page.getByLabel('6-digit code').fill(await emailedCode(email));
  await page.getByRole('button', { name: 'Create account' }).click();
  await page.getByLabel('Nickname').fill(nickname);
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByText('Level quiz').waitFor();
}
