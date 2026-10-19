import { useEffect, useState, type ReactNode, type SubmitEvent } from 'react';
import { useCaptcha } from './captcha';
import { t } from './i18n';
import { enabledProviders, supabase } from './supabase';
import { CardFan, Tag } from './kit';
import { Button, Field } from './ui';

const RESEND_SECONDS = 60;

// Supabase 的报错是给开发者看的，这里换成用户能照着做的话
function friendly(message: string) {
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

/** “通过 Google / Apple 继续”：跳到对方的登录页，回来时 Supabase 用一次性的 code 换登录状态 */
function ProviderButtons({ onError }: { onError: (message: string) => void }) {
  const [providers, setProviders] = useState<Provider[]>([]);
  const [busy, setBusy] = useState<Provider>();
  useEffect(() => {
    enabledProviders().then((names) => setProviders((['google', 'apple'] as const).filter((p) => names.includes(p))), () => {});
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

export function SignIn() {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  // 从 Google / Apple 跳回来时没成功（比如点了取消）
  const [error, setError] = useState<string | undefined>(() =>
    new URLSearchParams(location.search).has('error') ? t('Sign-in didn’t finish. Try again, or use your email.') : undefined);
  const [wait, setWait] = useState(0);
  const captcha = useCaptcha();

  useEffect(() => {
    if (wait <= 0) return;
    const timer = setTimeout(() => setWait(wait - 1), 1000);
    return () => clearTimeout(timer);
  }, [wait]);

  async function send(event?: SubmitEvent) {
    event?.preventDefault();
    setBusy(true);
    setError(undefined);
    const { error } = await supabase!.auth.signInWithOtp({
      email: email.trim(),
      options: { captchaToken: captcha.token },
    });
    captcha.reset();
    setBusy(false);
    if (error) return setError(friendly(error.message));
    setSent(true);
    setWait(RESEND_SECONDS);
  }

  async function verify(event: SubmitEvent) {
    event.preventDefault();
    setBusy(true);
    setError(undefined);
    const { error } = await supabase!.auth.verifyOtp({ email: email.trim(), token: code, type: 'email' });
    setBusy(false);
    if (error) setError(t('That code didn’t work. Check the latest email, or send a new one.'));
  }

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
      <div className="grid gap-4">
        <div className="sticker p-6 sm:p-8">
          <h2 className="text-title">{sent ? t('Check your email') : t('Sign in or sign up')}</h2>
          {sent && <p className="mt-2 text-subhead text-ink-secondary">{t('We sent a 6-digit code to {email}.', { email: email.trim() })}</p>}

          {!sent && <div className="mt-6 grid gap-5"><ProviderButtons onError={setError} /></div>}

          <form onSubmit={sent ? verify : send} className="mt-6 grid gap-4">
            {sent ? (
              <Field label={t('Sign-in code')} error={error}>
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
            ) : (
              <Field label={t('Email')} error={error}>
                {(props) => (
                  <input
                    {...props}
                    type="email"
                    autoComplete="email"
                    required
                    placeholder="you@example.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="field"
                  />
                )}
              </Field>
            )}
            {!sent && <p className="-mt-2 text-footnote text-ink-secondary">{t('We’ll email you a sign-in code. No password needed.')}</p>}

            {/* 只有 Cloudflare 觉得可疑时才会显示验证框 */}
            <div ref={captcha.container} className="empty:hidden" />
            {captcha.failed && <p className="text-sm font-bold text-danger">{t('The security check didn’t load. Turn off content blockers for this page and refresh.')}</p>}

            <Button busy={busy} disabled={!sent && !captcha.ready} className="button-lg button-inverse">{sent ? t('Sign in') : t('Email me a code')}</Button>

            {sent && (
              <div className="flex flex-wrap justify-between gap-3 text-sm">
                <button type="button" disabled={wait > 0 || busy || !captcha.ready} onClick={() => send()} className="link disabled:cursor-not-allowed disabled:no-underline disabled:opacity-60">
                  {wait > 0 ? t('Send a new code in {n}s', { n: wait }) : t('Send a new code')}
                </button>
                <button type="button" onClick={() => { setSent(false); setCode(''); setError(undefined); }} className="link">
                  {t('Use a different email')}
                </button>
              </div>
            )}
          </form>
        </div>
        <p className="text-center text-footnote text-ink-secondary">
          {t('Can’t find it? Check spam, or search your inbox for “Badie”.')}
        </p>
      </div>
    </div>
  );
}
