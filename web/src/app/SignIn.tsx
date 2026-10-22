import type { AuthError } from '@supabase/supabase-js';
import { Fragment, useEffect, useState, type ReactNode, type SubmitEvent } from 'react';
import { useCaptcha } from './captcha';
import { t } from './i18n';
import { enabledProviders, knownProviders, supabase } from './supabase';
import { CardFan, Tag } from './kit';
import { MIN_PASSWORD, passwordProblem } from './password';
import { Link } from './router';
import { Button, Field, PasswordInput, toast } from './ui';

const RESEND_SECONDS = 60;

// Supabase 的报错是给开发者看的，这里换成用户能照着做的话
function friendly(message: string, code?: string) {
  if (code === 'invalid_credentials') return t('Wrong email or password. If you used to sign in with an email code, tap “Forgot password?” to set one.');
  if (code === 'weak_password') return t('Use at least {n} characters.', { n: MIN_PASSWORD });
  if (/after \d+ seconds|rate limit|too many/i.test(message)) return t('Too many tries. Wait a minute, then try again.');
  if (/captcha/i.test(message)) return t('We couldn’t check that you’re human. Refresh the page and try again.');
  if (/invalid.*email|email.*invalid/i.test(message)) return t('That email address doesn’t look right.');
  return t('Something went wrong. Try again in a moment.');
}

type Provider = 'google' | 'apple';

/** Google 的四色 G 和 Apple 标志：按两家的品牌规范，不改颜色和形状 */
const logos: Record<Provider, ReactNode> = {
  google: (
    <svg viewBox="0 0 48 48" className="size-5" aria-hidden="true">
      <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z" />
      <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z" />
      <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z" />
      <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z" />
    </svg>
  ),
  apple: (
    <svg viewBox="0 0 814 1000" className="size-5 fill-current" aria-hidden="true">
      <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
    </svg>
  ),
};

const pick = (names: string[]) => (['google', 'apple'] as const).filter((p) => names.includes(p));

/** “通过 Google / Apple 继续”：跳到对方的登录页，回来时 Supabase 用一次性的 code 换登录状态 */
function ProviderButtons({ onError }: { onError: (message: string) => void }) {
  // 先按上次的结果马上显示，再在后台问服务器
  const [providers, setProviders] = useState<Provider[]>(() => pick(knownProviders()));
  const [busy, setBusy] = useState<Provider>();
  useEffect(() => {
    enabledProviders().then((names) => setProviders(pick(names)));
  }, []);

  async function go(provider: Provider) {
    setBusy(provider);
    const next = new URLSearchParams(location.search).get('next');
    const { error } = await supabase!.auth.signInWithOAuth({
      provider,
      options: { redirectTo: `${location.origin}/signin/${next ? `?next=${encodeURIComponent(next)}` : ''}` },
    });
    if (error) {
      setBusy(undefined);
      onError(friendly(error.message));
    }
  }

  if (providers.length === 0) return null;
  return (
    <>
      <div className="grid gap-3">
        {providers.map((provider) => (
          <Button key={provider} type="button" busy={busy === provider} onClick={() => go(provider)}
                  className={`button-lg ${provider === 'apple' ? 'button-inverse' : 'button-quiet'}`}>
            {busy !== provider && logos[provider]}
            {provider === 'google' ? t('Continue with Google') : t('Continue with Apple')}
          </Button>
        ))}
      </div>
      <p className="flex items-center gap-3 text-footnote font-bold text-ink-secondary before:h-0.5 before:flex-1 before:bg-stroke/15 after:h-0.5 after:flex-1 after:bg-stroke/15">
        {t('or')}
      </p>
    </>
  );
}

/** “继续即表示同意用户协议和隐私政策”：各语言语序不同，按译文里 {terms}、{privacy} 的位置放链接 */
function Agreement() {
  const links: Record<string, ReactNode> = {
    '{terms}': <a href="/terms/" className="link">{t('Terms of Service')}</a>,
    '{privacy}': <a href="/privacy/" className="link">{t('Privacy Policy')}</a>,
  };
  return (
    <p className="text-center text-footnote text-ink-secondary">
      {t('By continuing, you agree to the {terms} and {privacy}.').split(/(\{terms\}|\{privacy\})/).map((part, i) => <Fragment key={i}>{links[part] ?? part}</Fragment>)}
    </p>
  );
}

type Mode = 'signin' | 'signup';
/** 邮件里的 6 位码用来做什么：确认注册的邮箱、免密码登录、重设密码 */
type CodeFor = 'signup' | 'email' | 'recovery';
const looksLikeEmail = (text: string) => /^\S+@\S+\.\S+$/.test(text);

export function SignIn() {
  const [mode, setMode] = useState<Mode>(() => (new URLSearchParams(location.search).has('new') ? 'signup' : 'signin'));
  const [codeFor, setCodeFor] = useState<CodeFor>();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  // 从 Google / Apple 跳回来时没成功（比如点了取消）
  const [error, setError] = useState<string | undefined>(() =>
    new URLSearchParams(location.search).has('error') ? t('Sign-in didn’t finish. Try again, or use your email.') : undefined);
  const [wait, setWait] = useState(0);
  const captcha = useCaptcha();
  const address = email.trim();

  useEffect(() => {
    if (wait <= 0) return;
    const timer = setTimeout(() => setWait(wait - 1), 1000);
    return () => clearTimeout(timer);
  }, [wait]);

  /** 要过人机验证的请求（登录、注册、发邮件）：带上令牌，用完换一个 */
  async function guarded<T>(call: (captchaToken?: string) => Promise<T>) {
    setBusy(true);
    setError(undefined);
    const result = await call(captcha.token);
    captcha.reset();
    setBusy(false);
    return result;
  }

  function codeSent(purpose: CodeFor) {
    setCodeFor(purpose);
    setCode('');
    setWait(RESEND_SECONDS);
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (mode === 'signup') {
      setBusy(true);
      const problem = await passwordProblem(password);
      setBusy(false);
      if (problem) return setError(problem);
      const { data, error } = await guarded((captchaToken) => supabase!.auth.signUp({ email: address, password, options: { captchaToken } }));
      // 邮箱已注册：服务器要么直接报错，要么（防止探测邮箱）返回一个没有登录方式的空账号
      if (error?.code === 'user_already_exists' || (!error && data.user?.identities?.length === 0)) {
        setMode('signin');
        return setError(t('This email already has an account. Sign in, or reset your password.'));
      }
      if (error) return setError(friendly(error.message, error.code));
      if (!data.session) codeSent('signup');
      return;
    }
    const { error } = await guarded((captchaToken) => supabase!.auth.signInWithPassword({ email: address, password, options: { captchaToken } }));
    if (error?.code === 'email_not_confirmed') {
      setCodeFor('signup');
      return setError(t('Confirm your email first: enter the code we sent when you signed up, or send a new one.'));
    }
    if (error) setError(friendly(error.message, error.code));
  }

  /** 忘记密码 / 改用验证码登录：都是往邮箱发 6 位码 */
  async function emailCode(purpose: 'email' | 'recovery') {
    if (!looksLikeEmail(address)) return setError(t('Enter your email first.'));
    const { error } = await guarded<{ error: AuthError | null }>((captchaToken) => purpose === 'recovery'
      ? supabase!.auth.resetPasswordForEmail(address, { captchaToken })
      : supabase!.auth.signInWithOtp({ email: address, options: { captchaToken } }));
    if (error) return setError(friendly(error.message, error.code));
    codeSent(purpose);
  }

  async function resend() {
    if (codeFor !== 'signup') return emailCode(codeFor!);
    const { error } = await guarded((captchaToken) => supabase!.auth.resend({ type: 'signup', email: address, options: { captchaToken } }));
    if (error) return setError(friendly(error.message, error.code));
    codeSent('signup');
  }

  async function verify(event: SubmitEvent) {
    event.preventDefault();
    setBusy(true);
    setError(undefined);
    const problem = codeFor === 'recovery' ? await passwordProblem(password) : undefined;
    if (problem) {
      setBusy(false);
      return setError(problem);
    }
    const { error } = await supabase!.auth.verifyOtp({ email: address, token: code, type: codeFor! });
    if (error) {
      setBusy(false);
      return setError(t('That code didn’t work. Check the latest email, or send a new one.'));
    }
    // 重设密码：码对了就已经登录（页面随即跳走），接着把新密码存上
    if (codeFor === 'recovery') {
      const { error: saveError } = await supabase!.auth.updateUser({ password });
      toast(saveError ? t('You’re signed in, but the new password wasn’t saved. Set it in Settings.') : t('Password saved'), saveError ? 'error' : undefined);
    }
  }

  function backToPassword() {
    setCodeFor(undefined);
    setCode('');
    setError(undefined);
  }

  const switchTo = (next: Mode) => {
    setMode(next);
    setError(undefined);
  };

  const headline = t('Find a *buddy*\nfor a game\ntonight.').split('*');
  return (
    <div className="mx-auto grid max-w-5xl items-center gap-8 lg:grid-cols-2 lg:gap-12 lg:py-6">
      <div className="grid gap-5">
        <CardFan />
        <h1 className="display text-[2.5rem] whitespace-pre-line lg:text-[3.25rem]">
          {headline.map((part, i) => (i % 2 ? <mark key={i} className="marker">{part}</mark> : part))}
        </h1>
        <p className="max-w-md text-subhead text-ink-secondary">
          {t('Get matched with nearby players by level, time and distance. Costs split evenly and transparently, check in on arrival, and reliable players get games more easily.')}
        </p>
        <ul className="flex flex-wrap gap-2">
          <li><Tag icon="level" tint="lavender">{t('Level match')}</Tag></li>
          <li><Tag icon="coins" tint="peach">{t('Fair cost split')}</Tag></li>
          <li><Tag icon="verified" tint="mint">{t('Check in')}</Tag></li>
        </ul>
      </div>
      {/* 手机上表单放最前面：来这页就是要登录 */}
      <div className="grid gap-4 max-lg:order-first">
        <div className="sticker p-6 sm:p-8">
          {codeFor ? (
            <>
              <h2 className="text-title">{t('Check your email')}</h2>
              <p className="mt-2 text-subhead text-ink-secondary wrap-anywhere">{t('We sent a 6-digit code to {email}.', { email: address })}</p>
              <form onSubmit={verify} className="mt-6 grid gap-4">
                <Field label={t('6-digit code')} error={codeFor === 'recovery' ? undefined : error}>
                  {(props) => (
                    <input
                      {...props}
                      autoFocus
                      inputMode="numeric"
                      autoComplete="one-time-code"
                      pattern="\d{6,10}"
                      maxLength={10}
                      required
                      value={code}
                      onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
                      className="field h-16 text-center font-mono text-[1.75rem] font-black tracking-[0.4em]"
                    />
                  )}
                </Field>
                {codeFor === 'recovery' && (
                  <Field label={t('New password')} hint={t('At least 8 characters. A short sentence is easy to remember.')} error={error}>
                    {(props) => <PasswordInput {...props} autoComplete="new-password" value={password} onChange={setPassword} />}
                  </Field>
                )}
                {/* 自动填入的账号：让钥匙串 / 密码管理器把新密码存到这个邮箱名下 */}
                {codeFor === 'recovery' && <input type="email" autoComplete="username" value={address} readOnly hidden />}
                <Button busy={busy} className="button-lg button-inverse">
                  {codeFor === 'recovery' ? t('Save password and sign in') : codeFor === 'signup' ? t('Create account') : t('Sign in')}
                </Button>
                <div className="flex flex-wrap justify-between gap-3 text-sm">
                  <button type="button" disabled={wait > 0 || busy || !captcha.ready} onClick={resend} className="link disabled:cursor-not-allowed disabled:no-underline disabled:opacity-60">
                    {wait > 0 ? t('Send a new code in {n}s', { n: wait }) : t('Send a new code')}
                  </button>
                  <button type="button" onClick={backToPassword} className="link">{t('Back')}</button>
                </div>
              </form>
            </>
          ) : (
            <>
              <h2 className="text-title">{mode === 'signin' ? t('Sign in') : t('Create your account')}</h2>
              <p className="mt-2 text-subhead text-ink-secondary">
                {mode === 'signin' ? t('New to Badie?') : t('Already have an account?')}{' '}
                <button type="button" onClick={() => switchTo(mode === 'signin' ? 'signup' : 'signin')} className="link">
                  {mode === 'signin' ? t('Create an account') : t('Sign in instead')}
                </button>
              </p>

              <div className="mt-6 grid gap-5 empty:hidden"><ProviderButtons onError={setError} /></div>

              <form onSubmit={submit} className="mt-6 grid gap-4">
                <Field label={t('Email')}>
                  {(props) => (
                    <input {...props} type="email" autoComplete="username" required placeholder="you@example.com"
                           value={email} onChange={(e) => setEmail(e.target.value)} className="field" />
                  )}
                </Field>
                <Field label={t('Password')} hint={mode === 'signup' ? t('At least 8 characters. A short sentence is easy to remember.') : undefined} error={error}>
                  {(props) => <PasswordInput {...props} autoComplete={mode === 'signup' ? 'new-password' : 'current-password'} value={password} onChange={setPassword} />}
                </Field>
                <Button busy={busy} disabled={!captcha.ready} className="button-lg button-inverse">{mode === 'signin' ? t('Sign in') : t('Create account')}</Button>
                {mode === 'signin' && (
                  <div className="flex flex-wrap justify-between gap-3 text-sm">
                    <button type="button" disabled={busy || !captcha.ready} onClick={() => emailCode('recovery')} className="link disabled:opacity-60">{t('Forgot password?')}</button>
                    <button type="button" disabled={busy || !captcha.ready} onClick={() => emailCode('email')} className="link disabled:opacity-60">{t('Email me a code instead')}</button>
                  </div>
                )}
              </form>
            </>
          )}
          {/* 人机验证框只挂一次（两种界面共用），只有 Cloudflare 觉得可疑时才显示 */}
          <div ref={captcha.container} className="mt-4 empty:hidden" />
          {captcha.failed && <p className="mt-4 text-sm font-bold text-danger">{t('The security check didn’t load. Turn off content blockers for this page and refresh.')}</p>}
        </div>
        {codeFor ? (
          <p className="text-center text-footnote text-ink-secondary">
            {t('Can’t find it? Check spam, or search your inbox for “Badie”.')}
          </p>
        ) : <Agreement />}
        <p className="text-center text-footnote text-ink-secondary">
          {t('Trouble signing in?')} <Link to="/contact/" className="link">{t('Contact us')}</Link>
        </p>
      </div>
    </div>
  );
}
