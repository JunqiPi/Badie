import { useState, type SubmitEvent } from 'react';
import { supabase } from './supabase';

export function SignIn() {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  async function send(event: SubmitEvent) {
    event.preventDefault();
    setBusy(true);
    setError(undefined);
    const { error } = await supabase!.auth.signInWithOtp({ email: email.trim() });
    setBusy(false);
    if (error) setError(error.message);
    else setSent(true);
  }

  async function verify(event: SubmitEvent) {
    event.preventDefault();
    setBusy(true);
    setError(undefined);
    const { error } = await supabase!.auth.verifyOtp({ email: email.trim(), token: code.trim(), type: 'email' });
    setBusy(false);
    if (error) setError('That code didn’t work. Check the latest email, or send a new one.');
  }

  return (
    <div className="mx-auto grid min-h-screen max-w-md content-center gap-6 px-5">
      <a href="/" className="flex items-center gap-2 text-2xl font-black">
        <span className="sticker grid size-9 place-items-center rounded-xl! bg-lime text-on-accent">B</span>
        Badie
      </a>
      <div className="sticker p-6">
        <h1 className="display text-4xl">{sent ? 'Check your email' : 'Sign in'}</h1>
        <p className="mt-2 text-ink-secondary">
          {sent ? `We sent a sign-in code to ${email}.` : 'We’ll email you a sign-in code. No password needed.'}
        </p>
        <form onSubmit={sent ? verify : send} className="mt-6 grid gap-3">
          {sent ? (
            <input
              aria-label="Sign-in code"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={10}
              required
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
              className="tile h-14 bg-surface px-4 text-center text-2xl font-black tracking-[0.4em] outline-none focus:border-lavender"
            />
          ) : (
            <input
              aria-label="Email"
              type="email"
              autoComplete="email"
              required
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="tile h-14 bg-surface px-4 font-bold outline-none placeholder:text-ink-tertiary focus:border-lavender"
            />
          )}
          {error && <p role="alert" className="text-sm font-bold text-danger">{error}</p>}
          <button disabled={busy} className="button disabled:opacity-60">
            {sent ? 'Sign in' : 'Email me a code'}
          </button>
          {sent && (
            <button type="button" onClick={() => { setSent(false); setCode(''); }} className="text-sm font-bold text-ink-secondary underline">
              Use a different email
            </button>
          )}
        </form>
      </div>
    </div>
  );
}
