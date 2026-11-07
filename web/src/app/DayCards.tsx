import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import { activeCount, emptyFilter, eventLabels, inviteVenue, loadFilter, matches, saveFilter, timeLabels, type DayFilter, type TimeOfDay } from './dayFilter';
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
 *  卡片就是对方的约球请求（项目、时间都定好了）。右滑和点爱心一样，直接约：
 *  单打发约球邀请，TA 确认就成局；双打替我开一个公开的双打局并邀请 TA，附近的人可以加入补齐 */
export function DayCards({ date }: { date: string }) {
  const area = useArea();
  const [cards, setCards] = useState<DayCandidate[]>();
  const [drag, setDrag] = useState({ x: 0, y: 0, active: false });
  const [leaving, setLeaving] = useState<'left' | 'right'>();
  const [filter, setFilterState] = useState<DayFilter>(loadFilter);
  const [editing, setEditing] = useState(false);
  const start = useRef<{ x: number; y: number; id: number }>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const title = useRef<HTMLHeadingElement>(null);
  // 已经滑过的，自动刷新时不再加回来
  const seen = useRef(new Set<string>());
  const visible = cards?.filter((c) => matches(filter, c));
  const top = visible?.[0];

  const setFilter = (next: DayFilter) => {
    setFilterState(next);
    saveFilter(next);
  };

  // 打开期间每 30 秒拉一次：新出现的人接在后面，不打乱正在看的那张；已经走了的人拿掉
  useEffect(() => {
    if (!area) return;
    setCards(undefined);
    seen.current.clear();
    const { from, to } = bounds(date);
    let first = true;
    const load = () =>
      supabase!
        .rpc('day_candidates', { p_from: from.toISOString(), p_to: to.toISOString(), p_lat: area.lat, p_lon: area.lon, p_radius_km: NEARBY_KM })
        .then(({ data, error }) => {
          if (error && first) toast(problem(error), 'error');
          first = false;
          if (error) return;
          const fresh = (data ?? []) as DayCandidate[];
          setCards((current) => {
            if (!current) return fresh;
            const ids = new Set(fresh.map((c) => c.ticket));
            const kept = current.filter((c, i) => ids.has(c.ticket) || i === 0);
            const known = new Set(kept.map((c) => c.ticket));
            return [...kept, ...fresh.filter((c) => !known.has(c.ticket) && !seen.current.has(c.ticket))];
          });
        });
    void load();
    const timer = setInterval(() => document.visibilityState === 'visible' && void load(), 30_000);
    return () => clearInterval(timer);
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
    if (editing) dialog.current?.showModal();
    else dialog.current?.close();
  }, [editing]);

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
    seen.current.add(card.ticket);
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

  /** 右滑和点爱心一样：直接约，不再让人选 */
  async function like(card: DayCandidate) {
    const venue = inviteVenue(filter, card);
    if (!venue) return;
    next(card, 'right');
    const starts = inviteStart(card).toISOString();
    const singles = card.mode === 'singles' && !card.mixed;
    const { error } = await supabase!.rpc(singles ? 'invite_ticket' : 'invite_doubles', { p_ticket: card.ticket, p_venue: venue.id, p_starts_at: starts });
    if (error) return toast(problem(error), 'error');
    toast(singles ? t('Invited them to play singles at {time} at {venue}. If they confirm, the game is on.', { time: timeOf(starts), venue: venue.name })
      : t('Opened a doubles game and invited them. Players nearby can join.'));
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
          {Boolean(visible?.length) && (
            <p className="text-footnote font-bold text-ink-secondary">{t('Swipe right to invite, left to skip')} · {t('{n} player|{n} players', { n: visible!.length })}</p>
          )}
        </div>
        <IconButton icon="x" label={t('Close')} onClick={() => navigate('/')} />
      </header>

      {/* 筛选按钮 + 选了的条件（点 ✕ 去掉） */}
      {cards !== undefined && cards.length > 0 && (
        <div className="mx-auto flex w-full max-w-md gap-2 overflow-x-auto px-[var(--gutter)] pt-3 [scrollbar-width:none]">
          <button type="button" onClick={() => setEditing(true)}
                  className="press flex min-h-9 shrink-0 items-center gap-1.5 rounded-full bg-[#17140f] px-3 text-footnote font-bold text-lime">
            <Icon name="filter" className="size-4" />
            {activeCount(filter) ? t('Filters · {n}', { n: activeCount(filter) }) : t('Filters')}
          </button>
          {chips(filter, cards).map(([label, clear]) => (
            <button key={label} type="button" onClick={() => setFilter(clear(filter))} aria-label={t('Remove {name}', { name: label })}
                    className="press flex min-h-9 shrink-0 items-center gap-1 rounded-full border-2 border-stroke bg-lime px-3 text-footnote font-bold text-on-accent">
              {label} <Icon name="x" className="size-3" />
            </button>
          ))}
        </div>
      )}

      <div className="relative mx-auto min-h-0 w-full max-w-md flex-1 px-[var(--gutter)] py-4">
        {!area ? (
          <div className="grid h-full content-center"><AreaPrompt /></div>
        ) : cards === undefined ? (
          <Skeleton className="h-full rounded-[var(--radius-card)]" />
        ) : !top && cards.length > 0 ? (
          <div className="grid h-full content-center">
            <Empty icon="filter" tint="butter" title={t('No one matches your filters')} action={{ label: t('Clear filters'), onClick: () => setFilter(emptyFilter) }}>
              {t('Try loosening them a little.')}
            </Empty>
          </div>
        ) : !top ? (
          <div className="grid h-full content-center">
            <Empty icon="users" tint="sky" title={t('No one nearby to invite that day')} action={{ label: t('Send a match request'), to: `/play/?date=${date}` }}>
              {t('Send a match request and we’ll let you know when someone fits.')}
            </Empty>
          </div>
        ) : (
          <div className="relative h-full">
            {visible![1] && (
              <div aria-hidden="true" className="pointer-events-none absolute inset-0 translate-y-2.5 scale-[0.96]">
                <Card card={visible![1]} filter={filter} />
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
              <Card card={top} filter={filter} hint={leaving ?? (drag.x > 40 ? 'right' : drag.x < -40 ? 'left' : undefined)} />
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

      {/* 筛选：项目、球馆、等级、时间、对方性别、只看没爽约过的 */}
      <dialog
        ref={dialog}
        aria-labelledby="filter-title"
        onClose={() => setEditing(false)}
        onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
        className="m-0 mt-auto max-h-[90dvh] w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet sm:m-auto sm:max-w-md sm:open:animate-pop"
      >
        {editing && cards && (
          <FilterSheet initial={filter} cards={cards} onDone={(next) => { setFilter(next); setEditing(false); }} onCancel={() => setEditing(false)} />
        )}
      </dialog>
    </div>,
    document.body,
  );
}

/** 一张铺满的卡片：上面是背景照片或颜色，下面是等级、项目、时间、球馆（约在哪家的那家排第一） */
function Card({ card, filter, hint }: { card: DayCandidate; filter: DayFilter; hint?: 'left' | 'right' }) {
  const event = eventLabel(card.mode, eventOf(card.play_with, card.mixed)) ?? (card.mode === 'doubles' ? t('Doubles') : t('Singles'));
  const first = inviteVenue(filter, card);
  const venues = first ? [first, ...(card.venues ?? []).filter((v) => v.id !== first.id)] : card.venues ?? [];
  return (
    <DayCard
      person={card.user}
      event={{ icon: card.mode === 'doubles' ? 'users' : 'user', text: event }}
      time={`${timeOf(card.starts_at)} – ${timeOf(card.ends_at)}`}
      venues={venues.map((v) => v.name)}
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

/** 这天卡片里出现的球馆，按人数排 */
function venueCounts(cards: DayCandidate[]) {
  const counts = new Map<string, { id: string; name: string; count: number }>();
  for (const card of cards) for (const v of card.venues ?? []) counts.set(v.id, { id: v.id, name: v.name, count: (counts.get(v.id)?.count ?? 0) + 1 });
  return [...counts.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

/** 选了的条件：显示的字 + 去掉它 */
function chips(f: DayFilter, cards: DayCandidate[]): [string, (f: DayFilter) => DayFilter][] {
  const list: [string, (f: DayFilter) => DayFilter][] = [];
  if (f.event !== 'any') list.push([eventLabels()[f.event], (x) => ({ ...x, event: 'any' })]);
  if (f.venues.length) {
    const names = venueCounts(cards).filter((v) => f.venues.includes(v.id)).map((v) => v.name);
    list.push([names.length === 1 ? names[0] : t('{n} courts', { n: f.venues.length }), (x) => ({ ...x, venues: [] })]);
  }
  if (f.minLevel > 1 || f.maxLevel < 9) list.push([`Lv.${f.minLevel}–${f.maxLevel}`, (x) => ({ ...x, minLevel: 1, maxLevel: 9 })]);
  if (f.times.length) list.push([f.times.map((x) => timeLabels()[x]).join(', '), (x) => ({ ...x, times: [] })]);
  if (f.gender) list.push([f.gender === 'male' ? t('Men') : t('Women'), (x) => ({ ...x, gender: null })]);
  if (f.reliableOnly) list.push([t('No missed games'), (x) => ({ ...x, reliableOnly: false })]);
  return list;
}

function FilterSheet({ initial, cards, onDone, onCancel }: { initial: DayFilter; cards: DayCandidate[]; onDone: (f: DayFilter) => void; onCancel: () => void }) {
  const [draft, setDraft] = useState(initial);
  const set = (patch: Partial<DayFilter>) => setDraft((d) => ({ ...d, ...patch }));
  const count = cards.filter((c) => matches(draft, c)).length;
  const toggle = <T,>(list: T[], value: T) => (list.includes(value) ? list.filter((x) => x !== value) : [...list, value]);
  const section = 'grid gap-2';
  const label = 'text-footnote font-bold text-ink-secondary';
  const chip = (on: boolean) => `toggle ${on ? '' : ''}`;
  return (
    <form method="dialog" onSubmit={(e) => { e.preventDefault(); onDone(draft); }}
          className="grid max-h-[90dvh] grid-rows-[auto_1fr_auto] rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas sm:rounded-[28px] sm:border-b-2 sm:shadow-card">
      <div className="flex items-center gap-3 px-5 pt-5">
        <h2 id="filter-title" className="flex-1 text-title3">{t('Filters')}</h2>
        <button type="button" className="link text-footnote font-bold" onClick={() => setDraft(emptyFilter)}>{t('Reset')}</button>
        <IconButton icon="x" label={t('Close')} onClick={onCancel} />
      </div>
      <div className="grid content-start gap-5 overflow-y-auto px-5 py-4">
        <div className={section} role="group" aria-labelledby="f-event">
          <span id="f-event" className={label}>{t('Event')}</span>
          <div className="flex flex-wrap gap-2">
            {(Object.entries(eventLabels()) as [DayFilter['event'], string][]).map(([value, text]) => (
              <button key={value} type="button" className={chip(draft.event === value)} aria-pressed={draft.event === value} onClick={() => set({ event: value })}>{text}</button>
            ))}
          </div>
        </div>
        <div className={section} role="group" aria-labelledby="f-venues">
          <span id="f-venues" className={label}>{t('Courts')}</span>
          {venueCounts(cards).map((v) => (
            <button key={v.id} type="button" aria-pressed={draft.venues.includes(v.id)} onClick={() => set({ venues: toggle(draft.venues, v.id) })}
                    className={`flex min-h-12 items-center gap-2 rounded-[14px] border-2 border-stroke px-3 text-left text-subhead font-bold ${draft.venues.includes(v.id) ? 'bg-lime text-on-accent' : 'bg-surface'}`}>
              <Icon name={draft.venues.includes(v.id) ? 'check' : 'pin'} className="size-4 shrink-0" />
              <span className="min-w-0 flex-1">{v.name}</span>
              <span className="tabular-nums">{v.count}</span>
            </button>
          ))}
        </div>
        <div className={section} role="group" aria-labelledby="f-level">
          <span id="f-level" className={label}>{t('Level')}</span>
          <div className="flex flex-wrap items-center gap-2 text-subhead font-bold">
            <label className="flex items-center gap-2">{t('From')}
              <select className="field w-auto" value={draft.minLevel} onChange={(e) => set({ minLevel: Number(e.target.value) })}>
                {[1, 2, 3, 4, 5, 6, 7, 8, 9].filter((n) => n <= draft.maxLevel).map((n) => <option key={n} value={n}>Lv.{n}</option>)}
              </select>
            </label>
            <label className="flex items-center gap-2">{t('To')}
              <select className="field w-auto" value={draft.maxLevel} onChange={(e) => set({ maxLevel: Number(e.target.value) })}>
                {[1, 2, 3, 4, 5, 6, 7, 8, 9].filter((n) => n >= draft.minLevel).map((n) => <option key={n} value={n}>Lv.{n}</option>)}
              </select>
            </label>
          </div>
        </div>
        <div className={section} role="group" aria-labelledby="f-time">
          <span id="f-time" className={label}>{t('Time')}</span>
          <div className="flex flex-wrap gap-2">
            {(Object.entries(timeLabels()) as [TimeOfDay, string][]).map(([value, text]) => (
              <button key={value} type="button" className="toggle" aria-pressed={draft.times.includes(value)} onClick={() => set({ times: toggle(draft.times, value) })}>{text}</button>
            ))}
          </div>
        </div>
        <div className={section} role="group" aria-labelledby="f-gender">
          <span id="f-gender" className={label}>{t('Their gender')}</span>
          <div className="flex flex-wrap gap-2">
            {([[null, t('Any')], ['male', t('Men')], ['female', t('Women')]] as const).map(([value, text]) => (
              <button key={text} type="button" className="toggle" aria-pressed={draft.gender === value} onClick={() => set({ gender: value })}>{text}</button>
            ))}
          </div>
        </div>
        <label className="flex cursor-pointer items-center gap-3 text-subhead font-bold">
          <span className="flex-1">{t('Only players with no missed games')}</span>
          <input type="checkbox" role="switch" checked={draft.reliableOnly} onChange={(e) => set({ reliableOnly: e.target.checked })}
                 className="relative h-7 w-12 shrink-0 cursor-pointer appearance-none rounded-full border-2 border-stroke bg-surface-muted transition-colors duration-[var(--dur-1)] before:absolute before:top-0.5 before:left-0.5 before:size-5 before:rounded-full before:border-2 before:border-stroke before:bg-white before:transition-transform before:duration-[var(--dur-2)] checked:bg-lime checked:before:translate-x-5" />
        </label>
      </div>
      <div className="border-t-2 border-stroke px-5 pt-3 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        <Button className="w-full">{t('Show {n} player|Show {n} players', { n: count })}</Button>
      </div>
    </form>
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
