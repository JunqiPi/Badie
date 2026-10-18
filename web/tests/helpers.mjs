// 端到端测试共用：用本地 Supabase 的收件箱（Mailpit）拿验证码登录
const mailpit = process.env.MAILPIT_URL ?? 'http://127.0.0.1:54324';
export const base = process.env.BASE_URL ?? 'http://127.0.0.1:4321';

async function emailedCode(email) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const { messages = [] } = await (await fetch(`${mailpit}/api/v1/messages`)).json();
    const message = messages.find((m) => m.To?.some((to) => to.Address === email));
    if (message) {
      const full = await (await fetch(`${mailpit}/api/v1/message/${message.ID}`)).json();
      const code = (full.Text || full.HTML).match(/\b\d{6,10}\b/)?.[0];
      if (code) return code;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`no sign-in email for ${email}`);
}

/** 登录并建好资料，停在定级问卷 */
export async function signUp(page, email, nickname) {
  page.on('pageerror', (error) => {
    throw error;
  });
  await page.goto(`${base}/signin/`);
  await page.getByLabel('Email').fill(email);
  await page.getByRole('button', { name: 'Email me a code' }).click();
  await page.getByLabel('Sign-in code').fill(await emailedCode(email));
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.getByLabel('Nickname').fill(nickname);
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByText('Level quiz').waitFor();
}
