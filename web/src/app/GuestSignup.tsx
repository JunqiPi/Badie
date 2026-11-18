import { useState, type ReactNode, type SubmitEvent } from 'react';
import { useCaptcha } from './captcha';
import { t, useLocale } from './i18n';
import { Icon } from './icons';
import { Empty, IconTile, Notice, Tag } from './kit';
import { GuestPayCard } from './Pay';
import { Link, navigate } from './router';
import { problem, supabase, useLive, type GuestGroup, type GuestSession } from './supabase';
import { dayName, hours } from './time';
import { Button, Field, Skeleton, toast } from './ui';

// 不用注册的报名页（badie.rsvp/g/<链接码>/）：看接下来的场次和谁报了名，填名字报名或候补。
// 报名后的取消凭证存在这台设备上；确认邮件里也有取消链接（?cancel=<凭证>）

const TOKENS = 'badie.guestSignups';
const NAME = 'badie.guestName';

/** 这台设备上的报名凭证：{ 场次 id: 凭证 }。浏览器不让存时只在这次打开里有效 */
export function loadTokens(): Record<string, string> {
  try {
    return JSON.parse(localStorage.getItem(TOKENS) ?? '{}') ?? {};
  } catch {
    return {};
  }
}

function store(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {}
}

function savedName() {
  try {
    return localStorage.getItem(NAME) ?? '';
  } catch {
    return '';
  }
}

/** 给组织者复制的报名链接 */
export const guestLink = (code: string) => `${location.origin}/g/${code}/`;

/** guest-signup 函数的错误：数据库报的错原样转回来（{ message: 'guest_spots_full' }） */
async function signupProblem(error: unknown) {
  const response = (error as { context?: unknown }).context;
  const body = response instanceof Response ? await response.json().catch(() => null) : null;
  return problem({ message: body?.message ?? '' });
}

export function GuestSignup({ code, signedIn }: { code: string; signedIn: boolean }) {
  const [tokens, setTokens] = useState(loadTokens);
  const { data: page, refresh } = useLive<GuestGroup | null>('guest_group_page', {
    args: { p_code: code, p_tokens: Object.values(tokens).slice(-50) },
    every: 60_000,
  });
  // 展开的那一场：没点过时是我报了的那场，或者第一场还能报的
  const [open, setOpen] = useState<string | null>();

  function remember(session: string, token?: string) {
    const next = { ...tokens };
    if (token) next[session] = token;
    else delete next[session];
    setTokens(next);
    store(TOKENS, JSON.stringify(next));
  }

  // 从确认邮件的取消链接来的（?cancel=<凭证>）
  const [cancel, setCancel] = useState(() => new URLSearchParams(location.search).get('cancel'));
  const closeCancel = () => {
    setCancel(null);
    navigate(`/g/${code}/`, true);
  };
  const cancelNotice = cancel && (
    <CancelFromEmail token={cancel} onClose={closeCancel} onCancelled={() => {
      const session = Object.keys(tokens).find((id) => tokens[id] === cancel);
      if (session) remember(session);
      closeCancel();
      refresh();
    }} />
  );

  if (page === undefined) return <Skeleton className="mx-auto h-96 max-w-xl" />;
  if (page === null) {
    return (
      <div className="mx-auto grid max-w-xl gap-4">
        {cancelNotice}
        <Empty icon="link" tint="butter" title={t('This link doesn’t work anymore')} action={{ label: t('Home'), to: '/' }}>
          {t('Ask the organizer for the new link.')}
        </Empty>
      </div>
    );
  }

  const expanded = open === undefined
    ? (page.sessions.find((s) => s.players.some((p) => p.me)) ?? page.sessions.find((s) => !s.cancelled))?.id
    : open;
  return (
    <div className="mx-auto grid max-w-xl gap-4">
      {cancelNotice}
      <GuestPayCard group={page.group_id} />
      <section className="sticker grid gap-3 p-4">
        <h1 className="text-display max-[379px]:text-[1.75rem]">{page.name}</h1>
        <div className="flex items-center gap-3">
          <IconTile icon="pin" tint="sky" />
          <div className="min-w-0">
            <p className="truncate font-black">{[page.venue.name, page.venue.city].filter(Boolean).join(' · ')}</p>
            {page.organizer && <p className="text-footnote font-bold text-ink-secondary">{t('Organized by {name}', { name: page.organizer })}</p>}
          </div>
        </div>
        {page.summary && <p className="text-subhead">{page.summary}</p>}
      </section>

      <section aria-labelledby="upcoming" className="grid gap-2.5">
        <h2 id="upcoming" className="text-title3">{t('Upcoming')}</h2>
        {page.sessions.length === 0 && <p className="text-footnote text-ink-secondary">{t('No sessions scheduled.')}</p>}
        {page.sessions.map((s) => (
          <SessionCard key={s.id} session={s} mainVenue={page.venue.name} expanded={expanded === s.id}
                       onToggle={() => setOpen(expanded === s.id ? null : s.id)}>
            {signedIn ? (
              <Notice icon="user" tint="lavender" action={{ label: t('Open group'), to: `/groups/${page.group_id}/` }}>
                {t('You have a Badie account. Sign up from the group page.')}
              </Notice>
            ) : (
              <GuestActions session={s} code={code} token={tokens[s.id]} onChange={(token) => {
                remember(s.id, token);
                refresh();
              }} />
            )}
          </SessionCard>
        ))}
      </section>

      <footer className="flex items-center justify-between gap-3 pb-2 text-footnote font-bold text-ink-secondary">
        <span>{t('Badie is a free badminton app.')}</span>
        <Link to="/" className="flex min-h-11 items-center font-black text-ink underline underline-offset-4">{t('Get the app')}</Link>
      </footer>
    </div>
  );
}

/** 一场：收起时一行（时间、人数、满了），展开后是名单和报名 */
function SessionCard({ session: s, mainVenue, expanded, onToggle, children }: {
  session: GuestSession;
  mainVenue: string;
  expanded: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  const going = s.players.filter((p) => !p.waitlisted);
  const waiting = s.players.filter((p) => p.waitlisted);
  const counts = [t('{n}/{total} signed up', { n: going.length, total: s.capacity }), waiting.length > 0 && t('{n} on waitlist', { n: waiting.length })]
    .filter(Boolean).join(' · ');
  const badge = s.cancelled ? t('Cancelled') : going.length >= s.capacity ? t('Full') : null;
  return (
    <article className={`grid ${expanded ? 'sticker' : 'rounded-[14px] border-2 border-stroke bg-surface'}`}>
      <button type="button" onClick={onToggle} aria-expanded={expanded} className="press flex min-h-15 items-center gap-3 px-3.5 py-3 text-left">
        <span className="grid min-w-0 flex-1 gap-0.5">
          <span className="font-black">{dayName(s.starts_at, s.tz)} · {hours(s.starts_at, s.ends_at, s.tz)}</span>
          {s.venue !== mainVenue && <span className="truncate text-footnote font-bold">{s.venue}</span>}
          <span className="text-footnote font-bold text-ink-secondary tabular-nums">{s.cancelled ? t('Cancelled by the organizer') : counts}</span>
        </span>
        {badge && <Tag tint="muted">{badge}</Tag>}
        <Icon name="chevronDown" className={`size-5 shrink-0 transition-transform ${expanded ? 'rotate-180' : ''}`} />
      </button>
      {expanded && !s.cancelled && (
        <div className="grid gap-3.5 px-3.5 pb-3.5">
          <span className="block h-1.5 overflow-hidden rounded-full bg-surface-muted" aria-hidden="true">
            <span className="block h-full rounded-full bg-ink" style={{ width: `${Math.min(100, (going.length / s.capacity) * 100)}%` }} />
          </span>
          <Names players={going} />
          {waiting.length > 0 && (
            <div className="grid gap-2">
              <h3 className="text-footnote font-black">{t('Waitlist')}</h3>
              <Names players={waiting} numbered />
            </div>
          )}
          {children}
        </div>
      )}
    </article>
  );
}

/** 报名的人的名字；多了先显示 11 个，点“+n”看全部 */
function Names({ players, numbered = false }: { players: GuestSession['players']; numbered?: boolean }) {
  const [all, setAll] = useState(false);
  const shown = all || players.length <= 12 ? players : players.slice(0, 11);
  if (players.length === 0) return null;
  return (
    <ul className="flex flex-wrap gap-1.5">
      {shown.map((p, i) => (
        <li key={i} className={`flex items-center gap-1.5 rounded-full border-[1.5px] border-stroke py-1 pl-2.5 text-footnote font-bold ${p.guest ? 'pr-1' : 'pr-2.5'} ${p.me ? 'bg-butter text-on-accent' : ''}`}>
          {numbered && `${i + 1}. `}{p.me ? t('You') : p.name}
          {p.guest && !p.me && <span className="rounded-full bg-mint px-1.5 text-caption font-black text-on-accent">{t('Guest')}</span>}
        </li>
      ))}
      {shown.length < players.length && (
        <li>
          <button type="button" onClick={() => setAll(true)} className="rounded-full bg-surface-muted px-2.5 py-1 text-footnote font-bold">+{players.length - shown.length}</button>
        </li>
      )}
    </ul>
  );
}

/** 没报：填名字报名；报了：我的位置、留邮箱、取消 */
function GuestActions({ session: s, code, token, onChange }: {
  session: GuestSession;
  code: string;
  /** 这台设备上这一场的凭证 */
  token?: string;
  onChange: (token?: string) => void;
}) {
  const mine = s.players.filter((p) => p.waitlisted).findIndex((p) => p.me) + 1;
  const signedUp = token && s.players.some((p) => p.me);
  if (signedUp) return <MySpot session={s} token={token} position={mine} onLeft={() => onChange()} />;
  if (Date.parse(s.starts_at) <= Date.now()) return null;
  if (s.guest_spots <= 0) return <p className="text-footnote font-bold text-ink-secondary">{t('Guest spots for this day are taken. Ask the organizer.')}</p>;
  return <SignUpForm session={s} code={code} onDone={onChange} />;
}

function SignUpForm({ session: s, code, onDone }: { session: GuestSession; code: string; onDone: (token: string) => void }) {
  const captcha = useCaptcha();
  const locale = useLocale();
  const [name, setName] = useState(savedName);
  const [email, setEmail] = useState('');
  const [wantsEmail, setWantsEmail] = useState(false);
  // 同一场已经有同名的人：先问一句，再按一次才报
  const [sameNameOk, setSameNameOk] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const clean = name.trim().replace(/\s+/g, ' ');
  const sameName = s.players.some((p) => p.name.toLowerCase() === clean.toLowerCase());
  const full = s.players.filter((p) => !p.waitlisted).length >= s.capacity;

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (clean.length < 2) return setError(t('Enter your name (2–20 characters).'));
    if (sameName && !sameNameOk) return setSameNameOk(true);
    setBusy(true);
    setError(undefined);
    const { data, error } = await supabase!.functions.invoke('guest-signup', {
      body: { code, session: s.id, name: clean, email: wantsEmail ? email.trim() : null, locale, captcha: captcha.token },
    });
    captcha.reset();
    setBusy(false);
    if (error) return setError(await signupProblem(error));
    store(NAME, clean);
    const result = data as { status: 'confirmed' | 'waitlisted'; position: number | null; token: string };
    toast(result.status === 'confirmed' ? t('You’re signed up.') : t('You’re #{n} on the waitlist', { n: result.position ?? 1 }));
    onDone(result.token);
  }

  return (
    <form onSubmit={submit} noValidate className="grid gap-2.5">
      <Field label={t('Your name')} error={error}>
        {(props) => (
          <input {...props} value={name} maxLength={20} autoComplete="given-name" placeholder={t('First name is fine')}
                 onChange={(e) => { setName(e.target.value); setSameNameOk(false); }} className="field" />
        )}
      </Field>
      {wantsEmail ? (
        <Field label={t('Email')}>
          {(props) => <input {...props} type="email" value={email} maxLength={254} autoComplete="email" placeholder="you@example.com"
                             onChange={(e) => setEmail(e.target.value)} className="field" />}
        </Field>
      ) : (
        <button type="button" onClick={() => setWantsEmail(true)} className="flex min-h-8 items-center gap-1.5 justify-self-start text-footnote font-bold text-ink-secondary">
          <Icon name="plus" className="size-3.5" />{t('Email me if anything changes (optional)')}
        </button>
      )}
      {sameName && sameNameOk && <p role="alert" className="text-footnote font-bold">{t('Someone named {name} already signed up. Sign up anyway?', { name: clean })}</p>}
      <Button busy={busy} disabled={!captcha.ready} className="button-lg w-full">
        {sameName && sameNameOk ? t('Sign up anyway') : full ? t('Join waitlist') : t('Sign up')}
      </Button>
      <div ref={captcha.container} className="empty:hidden" />
      {captcha.failed && <p className="text-footnote font-bold text-danger">{t('The security check didn’t load. Turn off content blockers for this page and refresh.')}</p>}
    </form>
  );
}

/** 我报了这一场：报上了还是候补第几、留邮箱、取消 */
function MySpot({ session: s, token, position, onLeft }: { session: GuestSession; token: string; position: number; onLeft: () => void }) {
  const [email, setEmail] = useState('');
  const [saved, setSaved] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState<string>();

  async function call(name: string, fn: string, args: Record<string, unknown>) {
    setBusy(name);
    const { error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    return !error;
  }

  async function saveEmail(event: SubmitEvent) {
    event.preventDefault();
    if (await call('email', 'guest_set_email', { p_token: token, p_email: email })) setSaved(true);
  }

  async function leave() {
    if (!(await call('leave', 'guest_cancel', { p_token: token }))) return;
    toast(t('You’re off the list.'));
    onLeft();
  }

  const started = Date.parse(s.starts_at) <= Date.now();
  return (
    <div className="tile grid gap-3 rounded-[16px]! p-3.5">
      <div className="flex items-center gap-3">
        {position ? (
          <span aria-hidden="true" className="grid size-14 shrink-0 place-items-center rounded-[16px] border-2 border-stroke bg-butter text-[1.75rem] font-black text-on-accent">#{position}</span>
        ) : (
          <IconTile icon="check" tint="lime" size="lg" />
        )}
        <p className="text-headline">{position ? t('You’re #{n} on the waitlist', { n: position }) : t('You’re signed up')}</p>
      </div>
      {saved ? (
        <p className="text-footnote font-bold text-ink-secondary">{t('We’ll email you if anything changes.')}</p>
      ) : (
        <form onSubmit={saveEmail} noValidate className="grid gap-2">
          <Field label={position ? t('Email me if a spot opens') : t('Email me if anything changes')}>
            {(props) => <input {...props} type="email" value={email} maxLength={254} autoComplete="email" placeholder="you@example.com"
                               onChange={(e) => setEmail(e.target.value)} className="field" />}
          </Field>
          <Button busy={busy === 'email'} disabled={!email.trim()} className="w-full">{t('Save')}</Button>
        </form>
      )}
      {!started && (confirming ? (
        <Button variant="danger" busy={busy === 'leave'} onClick={leave}>{t('Yes, take me off')}</Button>
      ) : (
        <button type="button" onClick={() => setConfirming(true)} className="min-h-11 justify-self-center text-footnote font-black text-danger hover:underline">
          {position ? t('Leave the waitlist') : t('Can’t make it')}
        </button>
      ))}
    </div>
  );
}

/** 从确认邮件里的取消链接来的 */
function CancelFromEmail({ token, onCancelled, onClose }: { token: string; onCancelled: () => void; onClose: () => void }) {
  const [busy, setBusy] = useState(false);
  async function cancel() {
    setBusy(true);
    const { error } = await supabase!.rpc('guest_cancel', { p_token: token });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    toast(t('You’re off the list.'));
    onCancelled();
  }
  return (
    <div role="alert" className="tile grid gap-2 rounded-[16px]! bg-pink p-3 text-on-accent">
      <p className="text-headline">{t('Take yourself off this session?')}</p>
      <div className="flex flex-wrap gap-2">
        <Button variant="danger" className="button-sm" busy={busy} onClick={cancel}>{t('Yes, take me off')}</Button>
        <Button variant="quiet" className="button-sm" disabled={busy} onClick={onClose}>{t('Keep my spot')}</Button>
      </div>
    </div>
  );
}
