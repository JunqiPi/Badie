import { useEffect, useState, type SubmitEvent } from 'react';
import { useCaptcha } from './captcha';
import { t } from './i18n';
import { supabase } from './supabase';
import { Button, Field, LanguagePicker } from './ui';

const RESEND_SECONDS = 60;

// Supabase 的报错是给开发者看的，这里换成用户能照着做的话
function friendly(message: string) {
  if (/after \d+ seconds|rate limit|too many/i.test(message)) return t('Too many tries. Wait a minute, then try again.');
  if (/captcha/i.test(message)) return t('We couldn’t check that you’re human. Refresh the page and try again.');
  if (/invalid.*email|email.*invalid/i.test(message)) return t('That email address doesn’t look right.');
  return t('Something went wrong. Try again in a moment.');
}

export function SignIn() {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
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

  return (
    <div className="grid min-h-dvh place-items-center bg-canvas px-[var(--gutter)] py-10">
      <div className="animate-enter grid w-full max-w-md gap-6">
        <a href="/" className="flex items-center gap-2 text-2xl font-black">
          <span className="sticker grid size-9 place-items-center rounded-xl! bg-lime text-on-accent">B</span>
          Badie
        </a>
        <div className="sticker p-6 sm:p-8">
          <h1 className="display text-4xl">{sent ? t('Check your email') : t('Sign in')}</h1>
          <p className="mt-2 text-ink-secondary">
            {sent ? t('We sent a 6-digit code to {email}.', { email: email.trim() }) : t('We’ll email you a sign-in code. No password needed.')}
          </p>

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
                    className="field h-14 text-center text-2xl tracking-[0.4em]"
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
                    className="field h-12"
                  />
                )}
              </Field>
            )}

            {/* 只有 Cloudflare 觉得可疑时才会显示验证框 */}
            <div ref={captcha.container} className="empty:hidden" />
            {captcha.failed && <p className="text-sm font-bold text-danger">{t('The security check didn’t load. Turn off content blockers for this page and refresh.')}</p>}

            <Button busy={busy} disabled={!sent && !captcha.ready}>{sent ? t('Sign in') : t('Email me a code')}</Button>

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
        <p className="text-center text-sm font-semibold text-ink-tertiary">
          {t('Can’t find it? Check spam, or search your inbox for “Badie”.')}
        </p>
        <LanguagePicker className="justify-self-center" />
      </div>
    </div>
  );
}
