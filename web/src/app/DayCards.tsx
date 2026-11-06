import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import { createPortal } from 'react-dom';
import { NEARBY_KM, useArea } from './area';
import { eventLabel, eventOf } from './gender';
import { AreaPrompt } from './Home';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { Empty, IconButton } from './kit';
import { DayCard } from './PlayerCard';
import { Link, navigate } from './router';
import { problem, supabase, type DayCandidate } from './supabase';
import { dateChip, timeOf } from './time';
import { Button, Skeleton, toast } from './ui';

/** 从 TA 的开始时间约；来不及的话至少半小时后、按半小时对齐（和 iOS 一样） */
export function inviteStart(card: DayCandidate, now = Date.now()) {
  const earliest = now + 30 * 60000;
  const start = new Date(card.starts_at).getTime();
  return new Date(start >= earliest ? start : Math.ceil(earliest / 1800000) * 1800000);
}

/** 这天的 0 点到第二天 0 点（本地时区） */
function bounds(date: string) {
  const [y, m, d] = date.split('-').map(Number);
  return { from: new Date(y, m - 1, d), to: new Date(y, m - 1, d + 1) };
}

const SWIPE = 110;

/** 首页点某一天：这天附近在找人、和我水平对得上的球友，一张张卡片左右滑（iOS 的 DayCandidatesView）。
 *  右滑约 TA：单打直接发约球邀请，TA 确认就成局；双打先约 TA 一起开个局 */
export function DayCards({ date }: { date: string }) {
  const area = useArea();
  const [cards, setCards] = useState<DayCandidate[]>();
  const [drag, setDrag] = useState({ x: 0, y: 0, active: false });
  const [leaving, setLeaving] = useState<'left' | 'right'>();
  const [inviting, setInviting] = useState<DayCandidate>();
  const [busy, setBusy] = useState<string>();
  const start = useRef<{ x: number; y: number; id: number }>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const title = useRef<HTMLHeadingElement>(null);
  const top = cards?.[0];

  useEffect(() => {
    if (!area) return;
    setCards(undefined);
    const { from, to } = bounds(date);
    supabase!
      .rpc('day_candidates', { p_from: from.toISOString(), p_to: to.toISOString(), p_lat: area.lat, p_lon: area.lon, p_radius_km: NEARBY_KM })
      .then(({ data, error }) => {
        if (error) toast(problem(error), 'error');
        setCards((data ?? []) as DayCandidate[]);
      });
  }, [date, area?.lat, area?.lon]);

  // 全屏：底下的页面不滚动，焦点放到标题上
  useEffect(() => {
    const root = document.documentElement;
    const before = root.style.overflow;
    root.style.overflow = 'hidden';
    title.current?.focus();
    return () => void (root.style.overflow = before);
  }, []);

  useEffect(() => {
    if (inviting) dialog.current?.showModal();
    else dialog.current?.close();
  }, [inviting]);

  // 键盘：左右方向键跳过 / 约 TA，Esc 关闭（邀请框开着时不管）
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented || dialog.current?.open || (event.target as HTMLElement).closest?.('input, textarea, select')) return;
      if (event.key === 'Escape') navigate('/');
      else if (top && !leaving && event.key === 'ArrowLeft') skip(top);
      else if (top && !leaving && event.key === 'ArrowRight') like(top);
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  });

  /** 卡片飞出去，然后换下一张 */
  function next(card: DayCandidate, side: 'left' | 'right') {
    setLeaving(side);
    setTimeout(() => {
      setCards((list) => list?.filter((c) => c.ticket !== card.ticket));
      setLeaving(undefined);
      setDrag({ x: 0, y: 0, active: false });
    }, 220);
  }

  function skip(card: DayCandidate) {
    next(card, 'left');
    void supabase!.rpc('skip_candidate', { p_ticket: card.ticket });
  }

  function like(card: DayCandidate) {
    setDrag({ x: 0, y: 0, active: false });
    if (card.mode === 'singles' && !card.mixed) return setInviting(card);
    // 双打：先约 TA 一起开个局，再让附近的人补齐
    const q = new URLSearchParams({ mode: 'doubles', invite: card.user.id, name: card.user.nickname });
    if (card.user.gender) q.set('gender', card.user.gender);
    navigate(`/rooms/new/?${q}`);
  }

  async function invite(card: DayCandidate, venue: string) {
    setBusy(venue);
    const { error } = await supabase!.rpc('invite_ticket', { p_ticket: card.ticket, p_venue: venue, p_starts_at: inviteStart(card).toISOString() });
    setBusy(undefined);
    setInviting(undefined);
    if (error) return toast(problem(error), 'error');
    toast(t('Invite sent. If they confirm, the game is on.'));
    next(card, 'right');
  }

  // 拖动：从按钮、链接上开始的不算（还能点）
  function down(event: ReactPointerEvent<HTMLElement>) {
    if (leaving || (event.target as HTMLElement).closest('a, button')) return;
    start.current = { x: event.clientX, y: event.clientY, id: event.pointerId };
    event.currentTarget.setPointerCapture(event.pointerId);
    setDrag({ x: 0, y: 0, active: true });
  }
  function move(event: ReactPointerEvent<HTMLElement>) {
    const s = start.current;
    if (s?.id === event.pointerId) setDrag({ x: event.clientX - s.x, y: event.clientY - s.y, active: true });
  }
  function up(event: ReactPointerEvent<HTMLElement>) {
    const s = start.current;
    if (s?.id !== event.pointerId || !top) return;
    start.current = null;
    const dx = event.clientX - s.x;
    if (dx > SWIPE) like(top);
    else if (dx < -SWIPE) skip(top);
    else setDrag({ x: 0, y: 0, active: false });
  }
  function cancel() {
    start.current = null;
    setDrag({ x: 0, y: 0, active: false });
  }

  const x = leaving === 'left' ? -1.2 * innerWidth : leaving === 'right' ? 1.2 * innerWidth : drag.x;
  const day = dateChip(date, 0).full;

  return createPortal(
    <div role="dialog" aria-modal="true" aria-labelledby="day-title" className="fixed inset-0 z-40 flex flex-col bg-canvas text-ink">
      <header className="mx-auto flex w-full max-w-xl items-start gap-3 px-[var(--gutter)] pt-[calc(1rem+env(safe-area-inset-top))]">
        <div className="min-w-0 flex-1">
          <h1 id="day-title" ref={title} tabIndex={-1} className="text-title2 outline-none">{day}</h1>
          {Boolean(cards?.length) && <p className="text-footnote font-bold text-ink-secondary">{t('Swipe right to invite, left to skip')}</p>}
        </div>
        <IconButton icon="x" label={t('Close')} onClick={() => navigate('/')} />
      </header>

      <div className="relative mx-auto min-h-0 w-full max-w-md flex-1 px-[var(--gutter)] py-4">
        {!area ? (
          <div className="grid h-full content-center"><AreaPrompt /></div>
        ) : cards === undefined ? (
          <Skeleton className="h-full rounded-[var(--radius-card)]" />
        ) : !top ? (
          <div className="grid h-full content-center">
            <Empty icon="users" tint="sky" title={t('No one nearby to invite that day')} action={{ label: t('Send a match request'), to: `/play/?date=${date}` }}>
              {t('Send a match request and we’ll let you know when someone fits.')}
            </Empty>
          </div>
        ) : (
          <div className="relative h-full">
            {cards[1] && (
              <div aria-hidden="true" className="pointer-events-none absolute inset-0 translate-y-2.5 scale-[0.96]">
                <Card card={cards[1]} />
              </div>
            )}
            <div
              key={top.ticket}
              onPointerDown={down}
              onPointerMove={move}
              onPointerUp={up}
              onPointerCancel={cancel}
              style={{
                transform: `translate(${x}px, ${drag.y * 0.2}px) rotate(${x / 25}deg)`,
                transition: drag.active && !leaving ? 'none' : 'transform 220ms var(--ease-out)',
              }}
              className="absolute inset-0 cursor-grab touch-none select-none active:cursor-grabbing"
            >
              <Card card={top} hint={leaving ?? (drag.x > 40 ? 'right' : drag.x < -40 ? 'left' : undefined)} />
            </div>
          </div>
        )}
      </div>

      {top && (
        <div className="flex justify-center gap-10 px-[var(--gutter)] pt-1 pb-[calc(1.25rem+env(safe-area-inset-bottom))]">
          <Round icon="x" label={t('Skip')} className="bg-surface text-ink" disabled={Boolean(leaving)} onClick={() => skip(top)} />
          <Round icon="heart" label={t('Invite')} className="bg-lime text-on-accent" disabled={Boolean(leaving)} onClick={() => like(top)} />
        </div>
      )}

      {/* 约单打：选在哪家球馆（TA 请求里的球馆） */}
      <dialog
        ref={dialog}
        aria-labelledby="invite-title"
        onClose={() => setInviting(undefined)}
        onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
        className="m-0 mt-auto w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet sm:m-auto sm:max-w-md sm:open:animate-pop"
      >
        {inviting && (
          <div className="grid gap-3 rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas px-5 pt-5 pb-[calc(1.5rem+env(safe-area-inset-bottom))] sm:rounded-[28px] sm:border-b-2 sm:p-6 sm:shadow-card">
            <h2 id="invite-title" className="text-title3">{t('Invite them to play singles at {time}?', { time: timeOf(inviteStart(inviting).toISOString()) })}</h2>
            <p className="text-footnote text-ink-secondary">{t('If they confirm, the game is on. If not, your request keeps looking for someone.')}</p>
            {(inviting.venues ?? []).map((v) => (
              <Button key={v.id} type="button" className="w-full" busy={busy === v.id} disabled={Boolean(busy)} onClick={() => invite(inviting, v.id)}>
                {t('At {venue}', { venue: v.name })}
              </Button>
            ))}
            <Button type="button" variant="quiet" className="w-full" onClick={() => setInviting(undefined)}>{t('Cancel')}</Button>
          </div>
        )}
      </dialog>
    </div>,
    document.body,
  );
}

/** 一张铺满的卡片：上面是背景照片或颜色，下面是等级、项目、时间、球馆 */
function Card({ card, hint }: { card: DayCandidate; hint?: 'left' | 'right' }) {
  const event = eventLabel(card.mode, eventOf(card.play_with, card.mixed)) ?? (card.mode === 'doubles' ? t('Doubles') : t('Singles'));
  return (
    <DayCard
      person={card.user}
      event={{ icon: card.mode === 'doubles' ? 'users' : 'user', text: event }}
      time={`${timeOf(card.starts_at)} – ${timeOf(card.ends_at)}`}
      venues={(card.venues ?? []).map((v) => v.name)}
      footer={<Link to={`/players/${card.user.id}/`} className="link -my-2 flex min-h-11 items-center justify-self-start text-footnote font-bold">{t('View profile')}</Link>}
    >
      {hint && (
        <span aria-hidden="true" className={`absolute top-4 rounded-[12px] border-2 border-stroke px-3 py-1 text-headline font-black ${hint === 'right' ? 'left-4 -rotate-6 bg-lime text-on-accent' : 'right-4 rotate-6 bg-surface text-ink'}`}>
          {hint === 'right' ? t('Invite') : t('Skip')}
        </span>
      )}
    </DayCard>
  );
}

function Round({ icon, label, className, disabled, onClick }: { icon: IconName; label: string; className: string; disabled: boolean; onClick: () => void }) {
  return (
    <button type="button" aria-label={label} title={label} disabled={disabled} onClick={onClick}
            className={`press grid size-[4.5rem] place-items-center rounded-full border-2 border-stroke shadow-low disabled:opacity-60 ${className}`}>
      <Icon name={icon} className="size-7" />
    </button>
  );
}
