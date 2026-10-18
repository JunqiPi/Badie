import { useState, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { t } from './i18n';
import { Link } from './router';
import { problem, supabase, useLive, type Profile, type VerificationKind } from './supabase';
import { day } from './time';
import { ScreenHeader, Starburst } from './kit';
import { Button, EmptyState, Field, PageHeader, Skeleton, toast } from './ui';

/** 每类证据能认证的档位（和服务器、iOS 一致） */
const kinds: { kind: VerificationKind; label: string; hint: string; placeholder: string; levels: number[] }[] = [
  {
    kind: 'tournament', label: 'Tournament results', placeholder: 'usab.tournamentsoftware.com/…',
    hint: 'A results page on tournamentsoftware.com showing you in the top draw of a state or regional open.',
    levels: [20, 21, 22, 23, 24].map((n) => n / 3),
  },
  {
    kind: 'national', label: 'National ranking or athlete certificate', placeholder: 'https://… or 15-digit number',
    hint: 'A national ranking page, or the 15-digit number on your athlete grade certificate.',
    levels: [20, 21, 22, 23, 24, 25].map((n) => n / 3),
  },
  {
    kind: 'bwf', label: 'BWF world ranking', placeholder: 'bwfbadminton.com/player/…',
    hint: 'Your player page on bwfbadminton.com.',
    levels: [26, 27, 28].map((n) => n / 3),
  },
];

export const kindLabel = (kind: VerificationKind) => t(kinds.find((k) => k.kind === kind)?.label ?? '');

interface Request {
  id: string;
  kind: VerificationKind;
  claimed_rating: number;
  status: 'pending' | 'approved' | 'rejected' | 'withdrawn';
  created_at: string;
  review_note: string | null;
}

/** 资料页：认证状态和申请表。问卷最高 6+，7− 起要凭公开可查的证据由人工审核 */
/** 高水平认证页（iOS 的 VerificationView） */
export function VerificationPage({ profile }: { profile: Profile }) {
  return (
    <div className="mx-auto grid max-w-2xl gap-5">
      <ScreenHeader title={t('Level verification')} back="/me/" />
      <div className="sticker flex items-center gap-4 bg-lime p-5 text-on-accent">
        <Starburst size={64}>7+</Starburst>
        <p className="text-subhead font-bold">{t('Levels 7 to 9 need proof: tournament results, a national ranking or certificate, or a BWF profile. An admin checks it, usually within 3 working days.')}</p>
      </div>
      <Verification profile={profile} />
    </div>
  );
}

export function Verification({ profile }: { profile: Profile }) {
  const { data: request, refresh } = useLive<Request | null>('my_verification', { every: 300_000 });
  const [open, setOpen] = useState(false);
  if (request === undefined) return null;
  const pending = request?.status === 'pending';

  async function withdraw() {
    const { error } = await supabase!.rpc('withdraw_verification');
    if (error) return toast(problem(error), 'error');
    refresh();
  }

  return (
    <section aria-labelledby="verification" className="sticker grid gap-3 p-5">
      <h2 id="verification" className="text-headline">{t('Verified level')}</h2>
      {profile.verified_kind && profile.verified_rating && (
        <p className="font-bold">
          <span className="chip bg-mint">{t('Verified {level}', { level: tier(profile.verified_rating).label })}</span>{' '}
          <span className="text-ink-secondary">{kindLabel(profile.verified_kind)}</span>
        </p>
      )}
      {pending ? (
        <>
          <p role="status">
            {t('Under review: level {level}, {kind}. We usually reply within 3 working days.', { level: tier(request.claimed_rating).label, kind: kindLabel(request.kind) })}
          </p>
          <Button variant="quiet" onClick={withdraw} className="justify-self-start">{t('Withdraw request')}</Button>
        </>
      ) : (
        <>
          {request?.status === 'rejected' && (
            <p role="status" className="text-ink-secondary">
              {t('Your request from {date} wasn’t approved.', { date: day(request.created_at) })} {request.review_note}
            </p>
          )}
          <p className="text-footnote text-ink-secondary">
            {t('The quiz goes up to 6+. If you’ve played the top draw of a state open, have a national ranking or certificate, or a BWF ranking, you can show it to get 7− to 9+.')}
          </p>
          {open ? <RequestForm onDone={() => { setOpen(false); refresh(); }} onCancel={() => setOpen(false)} />
            : <Button onClick={() => setOpen(true)} className="justify-self-start">{t('Verify a higher level')}</Button>}
        </>
      )}
    </section>
  );
}

function RequestForm({ onDone, onCancel }: { onDone: () => void; onCancel: () => void }) {
  const [kind, setKind] = useState<VerificationKind>('tournament');
  const option = kinds.find((k) => k.kind === kind)!;
  const [level, setLevel] = useState(option.levels[0]);
  const [evidence, setEvidence] = useState('');
  const [name, setName] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  function pick(next: VerificationKind) {
    setKind(next);
    setLevel(kinds.find((k) => k.kind === next)!.levels[0]);
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!evidence.trim()) return setError(t('Add a link or certificate number.'));
    if (name.trim().length < 2) return setError(t('Enter the name shown on the results or certificate.'));
    setBusy(true);
    const { error } = await supabase!.rpc('request_verification', { p_kind: kind, p_rating: level, p_evidence: evidence, p_name: name, p_note: note });
    setBusy(false);
    if (error) return setError(problem(error));
    toast(t('Sent. We’ll let you know when it’s reviewed.'));
    onDone();
  }

  return (
    <form onSubmit={submit} noValidate className="grid gap-4">
      <div role="group" aria-label={t('Evidence')} className="flex flex-wrap gap-2">
        {kinds.map((k) => (
          <button key={k.kind} type="button" onClick={() => pick(k.kind)} aria-pressed={kind === k.kind} className="toggle">{t(k.label)}</button>
        ))}
      </div>
      <p className="text-sm text-ink-secondary">{t(option.hint)}</p>
      <Field label={t('Level')}>
        {(props) => (
          <select {...props} value={level} onChange={(e) => setLevel(Number(e.target.value))} className="field">
            {option.levels.map((value) => <option key={value} value={value}>{tier(value).label}</option>)}
          </select>
        )}
      </Field>
      <Field label={t('Link or certificate number')}>
        {(props) => <input {...props} value={evidence} maxLength={300} placeholder={option.placeholder} onChange={(e) => setEvidence(e.target.value)} className="field" />}
      </Field>
      <Field label={t('Name on the results or certificate')} hint={t('We check it against your ID. Only reviewers see it.')}>
        {(props) => <input {...props} value={name} maxLength={60} autoComplete="name" onChange={(e) => setName(e.target.value)} className="field" />}
      </Field>
      <Field label={t('Note (optional)')}>
        {(props) => <input {...props} value={note} maxLength={200} onChange={(e) => setNote(e.target.value)} className="field" />}
      </Field>
      {error && <p role="alert" className="font-bold text-danger">{error}</p>}
      <div className="flex flex-wrap gap-2">
        <Button busy={busy}>{t('Send for review')}</Button>
        <Button type="button" variant="quiet" onClick={onCancel}>{t('Cancel')}</Button>
      </div>
    </form>
  );
}

/** 管理员才看得到的入口 */
export function AdminLink() {
  const { data: admin } = useLive<boolean>('is_admin', { every: 3_600_000 });
  if (!admin) return null;
  return (
    <div className="mt-6">
      <Link to="/admin/" className="button button-quiet">{t('Review queue')}</Link>
    </div>
  );
}

interface QueueItem {
  id: string;
  user_id: string;
  nickname: string;
  rating: number;
  kind: VerificationKind;
  claimed_rating: number;
  evidence: string;
  name_on_record: string;
  note: string;
  created_at: string;
  previous: number;
}

/** 管理员审核认证申请：核对证据上的姓名和档位，可以批得比申请的低 */
export function Admin() {
  const { data: queue, failed, refresh } = useLive<QueueItem[]>('admin_verification_queue', { every: 60_000 });
  if (failed && !queue) return <EmptyState title={t('Admins only')}>{t('This page is for reviewers.')}</EmptyState>;
  return (
    <div className="max-w-3xl">
      <PageHeader back="/me/" eyebrow={t('Admin')} title={t('Level verification')} />
      {!queue ? <Skeleton className="h-40" /> : queue.length === 0 ? (
        <EmptyState title={t('Nothing to review')} />
      ) : (
        <div className="grid gap-4">{queue.map((item) => <Review key={item.id} item={item} onDone={refresh} />)}</div>
      )}
    </div>
  );
}

function Review({ item, onDone }: { item: QueueItem; onDone: () => void }) {
  const levels = kinds.find((k) => k.kind === item.kind)!.levels;
  const [level, setLevel] = useState(Math.round(item.claimed_rating * 3) / 3);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState<string>();
  const link = item.evidence.startsWith('https://');

  async function review(approve: boolean) {
    setBusy(approve ? 'approve' : 'reject');
    const { error } = await supabase!.rpc('admin_review_verification', { p_request: item.id, p_rating: approve ? level : null, p_note: note });
    setBusy(undefined);
    if (error) return toast(problem(error), 'error');
    toast(approve ? t('Approved') : t('Not approved'));
    onDone();
  }

  return (
    <article className="tile grid gap-3 bg-surface p-5">
      <p className="font-black">
        <Link to={`/players/${item.user_id}/`} className="link">{item.nickname}</Link>{' '}
        <span className="font-bold text-ink-secondary">
          · {t('now {level}', { level: tier(item.rating).label })} · {t('asks for {level}', { level: tier(item.claimed_rating).label })}
        </span>
      </p>
      <dl className="grid gap-1 text-sm sm:grid-cols-[10rem_1fr]">
        <dt className="font-bold text-ink-tertiary">{t('Evidence')}</dt>
        <dd className="break-all">
          {kindLabel(item.kind)}:{' '}
          {link ? <a href={item.evidence} target="_blank" rel="noopener noreferrer nofollow" className="link">{item.evidence}</a> : <code>{item.evidence}</code>}
        </dd>
        <dt className="font-bold text-ink-tertiary">{t('Name on record')}</dt>
        <dd>{item.name_on_record}</dd>
        {item.note && (<><dt className="font-bold text-ink-tertiary">{t('Note')}</dt><dd>{item.note}</dd></>)}
        <dt className="font-bold text-ink-tertiary">{t('Sent')}</dt>
        <dd>{day(item.created_at)}{item.previous > 0 && ` · ${t('{n} earlier request|{n} earlier requests', { n: item.previous })}`}</dd>
      </dl>
      <div className="grid gap-3 sm:grid-cols-[8rem_1fr]">
        <Field label={t('Level')}>
          {(props) => (
            <select {...props} value={level} onChange={(e) => setLevel(Number(e.target.value))} className="field">
              {levels.map((value) => <option key={value} value={value}>{tier(value).label}</option>)}
            </select>
          )}
        </Field>
        <Field label={t('Note to the player (optional)')}>
          {(props) => <input {...props} value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} className="field" />}
        </Field>
      </div>
      <div className="flex flex-wrap gap-2">
        <Button busy={busy === 'approve'} disabled={Boolean(busy)} onClick={() => review(true)}>{t('Approve')}</Button>
        <Button variant="quiet" busy={busy === 'reject'} disabled={Boolean(busy)} onClick={() => review(false)}>{t('Don’t approve')}</Button>
      </div>
    </article>
  );
}
