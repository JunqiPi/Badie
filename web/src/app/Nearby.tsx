import { useEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { t } from './i18n';
import { Icon } from './icons';
import { Avatar, IconButton, LevelBadge, Tag } from './kit';
import { navigate } from './router';
import { problem, supabase, tagText, useLive, type CandidateUser, type PlaySuggestion, type PlayWish, type Profile } from './supabase';
import { dayName, timeOf } from './time';
import { Button, toast } from './ui';

// 常在附近打的人：右滑 = 想一起打。对方同意（或也想和你打）就加为球友

/** 想一起打出错时给人看的话 */
export function wishProblem(error: { message: string }) {
  switch (error.message) {
    case 'wish_limit': return t('You’ve used today’s 10. Try again tomorrow.');
    case 'not_available': return t('They can’t be added right now.');
    default: return problem(error);
  }
}

/** 底部弹出的半屏（手机）/ 居中的小窗（桌面）。onClose：Esc、点外面、程序关掉都会调 */
export function Sheet({ open, onClose, labelledBy, children }: { open: boolean; onClose: () => void; labelledBy: string; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (open && !ref.current?.open) ref.current?.showModal();
    else if (!open && ref.current?.open) ref.current.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      aria-labelledby={labelledBy}
      onClose={onClose}
      onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
      className="m-0 mt-auto max-h-[90dvh] w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet sm:m-auto sm:max-w-md sm:open:animate-pop"
    >
      {open && (
        <div className="grid max-h-[90dvh] gap-4 overflow-y-auto rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas px-5 pt-5 pb-[calc(1.25rem+env(safe-area-inset-bottom))] sm:rounded-[28px] sm:border-b-2 sm:shadow-card">
          {children}
        </div>
      )}
    </dialog>
  );
}

/** 标题旁的“?”：规则放在这里，页面上不写解释 */
export function RulesButton({ points }: { points: string[] }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <IconButton icon="question" label={t('How it works')} onClick={() => setOpen(true)} />
      <Sheet open={open} onClose={() => setOpen(false)} labelledBy="rules-title">
        <div className="flex items-center gap-3">
          <h2 id="rules-title" className="flex-1 text-title3">{t('How it works')}</h2>
          <IconButton icon="x" label={t('Close')} onClick={() => setOpen(false)} />
        </div>
        <ul className="grid gap-2 text-subhead">
          {points.map((p) => (
            <li key={p} className="flex gap-2"><span aria-hidden="true" className="mt-2 size-1.5 shrink-0 rounded-full bg-ink" />{p}</li>
          ))}
        </ul>
      </Sheet>
    </>
  );
}

/** 约这个时间：开一个球局，带上对方、球馆和时间 */
function planLink(other: CandidateUser & { preferred_mode?: string | null }, suggestion: PlaySuggestion) {
  const q = new URLSearchParams({ mode: other.preferred_mode === 'singles' ? 'singles' : 'doubles', invite: other.id, name: other.nickname });
  if (other.gender) q.set('gender', other.gender);
  q.set('venue', suggestion.venue_id);
  q.set('venue_name', suggestion.venue_name);
  if (suggestion.starts_at && suggestion.ends_at) {
    q.set('starts', suggestion.starts_at);
    q.set('ends', suggestion.ends_at);
  }
  return `/rooms/new/?${q}`;
}

/** 你们都想一起打：已加为球友，推荐一个两人都常去、都有空的时间 */
export function Mutual({ me, other, suggestion, onClose }: {
  me: Profile;
  other: CandidateUser & { preferred_mode?: string | null };
  suggestion: PlaySuggestion | null;
  onClose: () => void;
}) {
  const title = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    title.current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      onClose();
    };
    document.addEventListener('keydown', onKey, true);
    return () => document.removeEventListener('keydown', onKey, true);
  }, []);
  const timed = suggestion?.starts_at && suggestion.ends_at;
  return createPortal(
    <div role="dialog" aria-modal="true" aria-labelledby="mutual-title" className="fixed inset-0 z-50 flex flex-col overflow-y-auto bg-lime text-on-accent">
      <div className="mx-auto flex w-full max-w-md flex-1 flex-col gap-6 px-[var(--gutter)] pt-[calc(1rem+env(safe-area-inset-top))] pb-[calc(1.25rem+env(safe-area-inset-bottom))]">
        <div><IconButton icon="x" label={t('Close')} onClick={onClose} /></div>
        <div className="grid justify-items-center gap-2 pt-6 text-center">
          <div className="flex">
            <Avatar id={me.id} name={me.nickname} photo={me.avatar_path} size={104} />
            <Avatar id={other.id} name={other.nickname} photo={other.avatar} size={104} className="-ml-4" />
          </div>
          <h1 id="mutual-title" ref={title} tabIndex={-1} className="mt-4 text-title outline-none">{t('You both want to play')}</h1>
          <p className="text-headline">{t('Added as friends')}</p>
        </div>
        {suggestion && (
          <div className="sticker grid gap-0.5 p-4 text-ink">
            <p className="text-headline">{timed ? `${dayName(suggestion.starts_at!)} ${timeOf(suggestion.starts_at!)}–${timeOf(suggestion.ends_at!)}` : suggestion.venue_name}</p>
            <p className="text-footnote font-bold text-ink-secondary">
              {timed ? `${suggestion.venue_name} · ${t('You both play here and are free then')}` : t('You both often play here')}
            </p>
          </div>
        )}
        <div className="mt-auto grid gap-3">
          {suggestion && (
            <Button className="button-lg button-inverse w-full" onClick={() => { onClose(); navigate(planLink(other, suggestion)); }}>{t('Invite for this time')}</Button>
          )}
          <Button className="button-lg w-full" variant="quiet" onClick={() => { onClose(); navigate(`/messages/dm/${other.id}/`); }}>{t('Send a message')}</Button>
        </div>
      </div>
    </div>,
    document.body,
  );
}

/** 小卡片：头像、名字、等级、靠谱、也常去哪家 */
function MiniCard({ wish }: { wish: PlayWish }) {
  const user = wish.from;
  return (
    <div className="sticker flex items-center gap-3 p-3">
      <Avatar id={user.id} name={user.nickname} photo={user.avatar} size={48} />
      <div className="grid min-w-0 flex-1 gap-1">
        <p className="flex min-w-0 font-bold">
          <span className="truncate">{user.nickname}</span>
          {user.tag != null && <span className="shrink-0 text-ink-tertiary">&nbsp;{tagText(user.tag)}</span>}
        </p>
        <span className="flex flex-wrap gap-1.5">
          <LevelBadge rating={user.rating} compact />
          {(user.recent_no_shows ?? 0) === 0 && <Tag icon="reliable" tint="mint">{t('Reliable')}</Tag>}
        </span>
        {wish.shared_venue && <p className="truncate text-footnote text-ink-secondary">{t('Also plays at {venue}', { venue: wish.shared_venue })}</p>}
      </div>
    </div>
  );
}

type Answer = { other: PlayWish['from']; suggestion: PlaySuggestion | null };

/** 别人发来的“想一起打”：不了 / 好。好 → 加为球友，onAccepted 里打开“你们都想一起打” */
export function PlayWishList({ wishes, onAnswered, onAccepted }: { wishes: PlayWish[]; onAnswered: () => void; onAccepted: (answer: Answer) => void }) {
  const [busy, setBusy] = useState<string>();
  const [gone, setGone] = useState<string[]>([]);

  async function respond(wish: PlayWish, accept: boolean) {
    setBusy(wish.from.id);
    const { data, error } = await supabase!.rpc('respond_play_wish', { p_from: wish.from.id, p_accept: accept });
    setBusy(undefined);
    if (error) return toast(wishProblem(error), 'error');
    setGone((list) => [...list, wish.from.id]);
    if (accept) onAccepted({ other: wish.from, suggestion: (data as { suggestion?: PlaySuggestion | null } | null)?.suggestion ?? null });
    onAnswered();
  }

  return wishes.filter((w) => !gone.includes(w.from.id)).map((wish) => (
    <section key={wish.from.id} aria-labelledby={`wish-${wish.from.id}`} className="grid gap-3">
      <h2 id={`wish-${wish.from.id}`} className="text-title3">{t('{name} wants to play with you', { name: wish.from.nickname })}</h2>
      <MiniCard wish={wish} />
      <div className="grid grid-cols-[1fr_2fr] gap-3">
        <Button variant="quiet" disabled={busy === wish.from.id} onClick={() => respond(wish, false)}>{t('No thanks')}</Button>
        <Button busy={busy === wish.from.id} onClick={() => respond(wish, true)}>{t('Sure')}</Button>
      </div>
    </section>
  ));
}

/** 通知页最上面：还没回的“想一起打” */
export function PlayWishInbox({ me }: { me: Profile }) {
  const { data, refresh } = useLive<PlayWish[]>('pending_play_wishes', { every: 60_000 });
  const [mutual, setMutual] = useState<Answer>();
  return (
    <>
      {Boolean(data?.length) && (
        <div className="sticker grid gap-6 bg-butter/40 p-4">
          <PlayWishList wishes={data!} onAnswered={() => void refresh()} onAccepted={setMutual} />
        </div>
      )}
      {mutual && <Mutual me={me} other={mutual.other} suggestion={mutual.suggestion} onClose={() => setMutual(undefined)} />}
    </>
  );
}

/** 首页：有人想和我打时，标题下面一个小标签“想一起打 N”，点开回复 */
export function PlayWishPill({ me }: { me: Profile }) {
  const { data, refresh } = useLive<PlayWish[]>('pending_play_wishes', { every: 60_000 });
  const [open, setOpen] = useState(false);
  const [mutual, setMutual] = useState<Answer>();
  const count = data?.length ?? 0;
  return (
    <>
      {count > 0 && (
        <button type="button" onClick={() => setOpen(true)}
                className="press mt-3 flex min-h-9 items-center gap-1.5 rounded-full border-2 border-stroke bg-surface px-3 text-footnote font-bold">
          <Icon name="heart" className="size-4" />
          {t('Want to play')}
          <span className="grid h-5 min-w-5 place-items-center rounded-full bg-danger-fill px-1 text-[11px] font-black text-white tabular-nums">{count}</span>
        </button>
      )}
      <Sheet open={open && count > 0} onClose={() => setOpen(false)} labelledBy="wishes-title">
        <div className="flex items-center gap-3">
          <p id="wishes-title" className="kicker flex-1 text-ink-secondary">{t('Want to play')}</p>
          <IconButton icon="x" label={t('Close')} onClick={() => setOpen(false)} />
        </div>
        <PlayWishList wishes={data ?? []} onAnswered={() => void refresh()}
                      onAccepted={(answer) => { setOpen(false); setMutual(answer); }} />
      </Sheet>
      {mutual && <Mutual me={me} other={mutual.other} suggestion={mutual.suggestion} onClose={() => setMutual(undefined)} />}
    </>
  );
}
