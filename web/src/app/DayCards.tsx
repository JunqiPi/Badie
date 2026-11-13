import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import { activeCount, emptyFilter, eventLabels, inviteVenue, loadFilter, matches, matchesNearby, saveFilter, timeLabels, type DayFilter, type TimeOfDay } from './dayFilter';
import { AvatarCrop, decode } from './AvatarCrop';
import { uploadCardPhoto } from './CardBackground';
import { InviteSheet, inviteProblem as nearbyProblem } from './Invites';
import { Sheet, UsualChips } from './Nearby';
import { RANGES, setNearbyKm, useArea, useNearbyKm } from './area';
import { km as distance } from './Courts';
import { eventLabel, eventOf } from './gender';
import { AreaPrompt } from './Home';
import { currentLocale, t } from './i18n';
import { Icon, type IconName } from './icons';
import { Avatar, Empty, IconButton, IconTile } from './kit';
import { DayCard, type CardPerson } from './PlayerCard';
import { Link, navigate } from './router';
import { problem, supabase, type DayCandidate, type InviteUser, type NearbyPlayer, type Profile } from './supabase';
import { capitalize, dateChip, timeOf } from './time';
import { Button, Skeleton, toast } from './ui';
import type { UsualTime } from './usual';

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

/** 一叠卡片里的一张：这天在找人的请求，或附近的人（接在这天的后面） */
type Item = { kind: 'day'; key: string; card: DayCandidate } | { kind: 'nearby'; key: string; card: NearbyPlayer };
const dayItem = (card: DayCandidate): Item => ({ kind: 'day', key: card.ticket, card });
const nearbyItem = (card: NearbyPlayer): Item => ({ kind: 'nearby', key: `n:${card.user.id}`, card });

/** 第一次约附近的人之前，没有卡片照片的提醒一次（记在本机） */
const PHOTO_ASKED = 'badie.nearbyPhotoAsked';
function photoAsked() {
  try {
    return localStorage.getItem(PHOTO_ASKED) === '1';
  } catch {
    return true;
  }
}
function rememberPhotoAsked() {
  try {
    localStorage.setItem(PHOTO_ASKED, '1');
  } catch {}
}

/** 约附近的人：TA 是谁，点的是 TA 哪段空闲时间 */
type Composing = { card: NearbyPlayer; slot?: UsualTime };

/** 发现页（第一个 tab）的一叠卡片，一张张左右滑（iOS 的 DayCandidatesView）。
 *  选了某一天（在筛选里）：这天附近在找人、和我水平对得上的球友，刷完接着看附近的人；不给 date 就是“附近的人”：只有附近的人的卡片。
 *  这天的卡片就是对方的约球请求（项目、时间都定好了），右滑直接约：单打发约球邀请，双打替我开一个公开的双打局并邀请 TA。
 *  附近的人右滑打开约 TA 的半屏（项目、哪天、几点到几点、球馆），发出一个邀请。
 *  上面：左边附近范围，右边球馆和筛选；下面一排圆头像是这叠卡片里的人，点一个就翻到 TA */
export function Deck({ date, days, onDate, profile, onProfile }: {
  date?: string;
  /** 筛选里能选的日子（接下来 30 天） */
  days: string[];
  onDate: (date?: string) => void;
  profile: Profile;
  onProfile: (p: Profile) => void;
}) {
  const area = useArea();
  const km = useNearbyKm();
  const lobby = !date;
  const [cards, setCards] = useState<DayCandidate[]>();
  const [nearby, setNearby] = useState<NearbyPlayer[]>();
  // 约附近的人之前要先问的（让附近的人看到你 / 加一张照片）
  const [asking, setAsking] = useState<{ kind: 'visible' | 'photo' } & Composing>();
  const [cropping, setCropping] = useState<{ image: ImageBitmap } & Composing>();
  const [composing, setComposing] = useState<Composing>();
  const me = useRef(profile);
  me.current = profile;
  const [drag, setDrag] = useState({ x: 0, y: 0, active: false });
  const [leaving, setLeaving] = useState<'left' | 'right'>();
  const [filter, setFilterState] = useState<DayFilter>(loadFilter);
  const [editing, setEditing] = useState(false);
  const [ranging, setRanging] = useState(false);
  // 点了上面那排头像里的谁：TA 的卡片排到最前面（滑走以后照原来的顺序）
  const [front, setFront] = useState<string>();
  const start = useRef<{ x: number; y: number; id: number }>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  // 已经滑过的，自动刷新时不再加回来
  const seen = useRef(new Set<string>());
  const loaded = cards !== undefined && nearby !== undefined;
  // 和这天的卡片重复的人只出现一次
  const dayPeople = new Set(cards?.map((c) => c.user.id));
  const visibleDay = cards?.filter((c) => matches(filter, c)) ?? [];
  const visibleNearby = nearby?.filter((c) => !dayPeople.has(c.user.id) && matchesNearby(filter, c)) ?? [];
  const ordered = loaded ? [...visibleDay.map(dayItem), ...visibleNearby.map(nearbyItem)] : undefined;
  const picked = ordered?.find((item) => item.key === front);
  const deck = picked ? [picked, ...ordered!.filter((item) => item !== picked)] : ordered;
  const total = (cards?.length ?? 0) + (nearby?.filter((c) => !dayPeople.has(c.user.id)).length ?? 0);
  const top = deck?.[0];
  // 正在看的那张：自动刷新时不能让它突然消失
  const currentTop = useRef<string>(undefined);
  currentTop.current = top?.key;
  // 附近的人里滑过几个：一个都没滑时，第一张上面写“这天的刷完了”
  const [nearbySeen, setNearbySeen] = useState(0);
  // 加球友（★）之后的状态，按人记
  const [friendship, setFriendship] = useState<Record<string, FriendState>>({});
  const [befriending, setBefriending] = useState(false);

  const setFilter = (next: DayFilter) => {
    setFilterState(next);
    saveFilter(next);
  };

  // 换天、换范围时重新拉；选了某一天时每 30 秒拉一次这天的请求：新出现的人接在后面，不打乱正在看的那张；已经走了的人拿掉。
  // 连着换天时，上一天晚到的结果不要（stale）
  useEffect(() => {
    if (!area) return;
    let stale = false;
    setCards(lobby ? [] : undefined);
    setNearby(undefined);
    setNearbySeen(0);
    seen.current.clear();
    supabase!
      .rpc('nearby_players', { p_lat: area.lat, p_lon: area.lon, p_radius_km: km })
      .then(({ data, error }) => !stale && setNearby(error ? [] : ((data ?? []) as NearbyPlayer[])));
    if (!date) return () => {
      stale = true;
    };
    const { from, to } = bounds(date);
    let first = true;
    const load = () =>
      supabase!
        .rpc('day_candidates', { p_from: from.toISOString(), p_to: to.toISOString(), p_lat: area.lat, p_lon: area.lon, p_radius_km: km })
        .then(({ data, error }) => {
          if (stale) return;
          if (error && first) {
            toast(problem(error), 'error');
            setCards((list) => list ?? []);
          }
          first = false;
          if (error) return;
          const fresh = (data ?? []) as DayCandidate[];
          setCards((current) => {
            if (!current) return fresh;
            const ids = new Set(fresh.map((c) => c.ticket));
            const kept = current.filter((c) => ids.has(c.ticket) || c.ticket === currentTop.current);
            // 已经在看附近的人了：新来的请求不再插到前面
            if (currentTop.current?.startsWith('n:')) return kept;
            const known = new Set(kept.map((c) => c.ticket));
            return [...kept, ...fresh.filter((c) => !known.has(c.ticket) && !seen.current.has(c.ticket))];
          });
        });
    void load();
    const timer = setInterval(() => document.visibilityState === 'visible' && void load(), 30_000);
    return () => {
      stale = true;
      clearInterval(timer);
    };
  }, [date, area?.lat, area?.lon, km]);

  useEffect(() => {
    if (editing) dialog.current?.showModal();
    else dialog.current?.close();
  }, [editing]);

  // 键盘：左右方向键跳过 / 约 TA（半屏开着、在输入框或日期标签上时不管）
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented || document.querySelector('dialog[open]') || (event.target as HTMLElement).closest?.('input, textarea, select, .rail')) return;
      if (top && !leaving && event.key === 'ArrowLeft') skip(top);
      else if (top && !leaving && event.key === 'ArrowRight') like(top);
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  });

  /** 卡片飞出去，然后换下一张 */
  function next(item: Item, side: 'left' | 'right') {
    seen.current.add(item.key);
    setLeaving(side);
    setTimeout(() => {
      if (item.kind === 'day') setCards((list) => list?.filter((c) => c.ticket !== item.card.ticket));
      else {
        setNearby((list) => list?.filter((c) => c.user.id !== item.card.user.id));
        setNearbySeen((n) => n + 1);
      }
      setLeaving(undefined);
      setDrag({ x: 0, y: 0, active: false });
    }, 220);
  }

  function skip(item: Item) {
    next(item, 'left');
    if (item.kind === 'day') void supabase!.rpc('skip_candidate', { p_ticket: item.card.ticket });
    else void supabase!.rpc('skip_nearby', { p_user: item.card.user.id });
  }

  function like(item: Item) {
    if (leaving) return;
    if (item.kind === 'day') void invite(item.card);
    else compose({ card: item.card });
  }

  /** 卡片回到原位（没滑出去） */
  const settle = () => setDrag({ x: 0, y: 0, active: false });

  /** 约附近的人：先确认附近的人能看到我；没有卡片照片的，第一次提醒一下；然后打开约 TA 的半屏 */
  function compose(c: Composing) {
    settle();
    if (!me.current.show_as_regular) return setAsking({ kind: 'visible', ...c });
    if (!me.current.card_photo_path && !photoAsked()) {
      rememberPhotoAsked();
      return setAsking({ kind: 'photo', ...c });
    }
    setComposing(c);
  }

  /** 发出去了：卡片飞走，提示还能约几个 */
  function sent(card: NearbyPlayer, remaining: number | null, label: string) {
    setComposing(undefined);
    next(nearbyItem(card), 'right');
    const done = t('Invited {name} · {when}', { name: card.user.nickname, when: label });
    toast(remaining === null ? done : `${done}\n${t('{n} left today', { n: remaining })}`);
  }

  function failed(card: NearbyPlayer, error: { message: string }) {
    setComposing(undefined);
    if (error.message === 'not_visible') {
      onProfile({ ...me.current, show_as_regular: false });
      return setAsking({ kind: 'visible', card });
    }
    toast(nearbyProblem(error), 'error');
    // TA 已经约不了（或者已经有一个邀请了）：拿掉这张
    if (error.message === 'not_available' || error.message === 'already_invited') next(nearbyItem(card), 'left');
  }

  /** 让附近的人也能看到我：打开“在同馆常客里显示我”，然后接着约 */
  async function becomeVisible(c: Composing) {
    setAsking(undefined);
    const { data, error } = await supabase!.from('profiles').update({ show_as_regular: true }).eq('id', me.current.id).select().single();
    if (error) return toast(t('Couldn’t save. Try again.'), 'error');
    me.current = data as Profile;
    onProfile(data as Profile);
    compose(c);
  }

  async function pickPhoto(file: File, c: Composing) {
    setAsking(undefined);
    try {
      setCropping({ image: await decode(file), ...c });
    } catch {
      toast(t('Couldn’t upload the photo. Try another one.'), 'error');
    }
  }

  async function uploadPhoto(jpeg: Blob) {
    const { image, ...c } = cropping!;
    image.close();
    setCropping(undefined);
    try {
      const path = await uploadCardPhoto(me.current, jpeg);
      me.current = { ...me.current, card_photo_path: path };
      onProfile(me.current);
    } catch {
      return toast(t('Couldn’t upload the photo. Try another one.'), 'error');
    }
    setComposing(c);
  }

  /** 和 TA 是不是球友：★ 之后记下的，没有就看附近的人里 TA 的（这天的卡片上没有这个） */
  const friendOf = (item: Item): FriendState =>
    friendship[item.card.user.id] ?? nearby?.find((c) => c.user.id === item.card.user.id) ?? { is_friend: false, friend_request: null };

  /** ★ 加球友：不占每天 10 个邀请，也不翻到下一张。已经是球友就去聊天；申请过了提示一下；TA 申请过我就直接接受 */
  async function star(item: Item) {
    const id = item.card.user.id;
    const state = friendOf(item);
    if (state.is_friend) return navigate(`/messages/dm/${id}/`);
    if (state.friend_request === 'sent') return toast(t('Requested'));
    if (befriending) return;
    setBefriending(true);
    const accept = state.friend_request === 'received';
    const { data, error } = accept
      ? await supabase!.rpc('respond_friend_request', { p_user: id, p_accept: true })
      : await supabase!.rpc('send_friend_request', { p_user: id });
    setBefriending(false);
    if (error) return toast(problem(error), 'error');
    const friends = accept || data === 'friends';
    setFriendship((all) => ({ ...all, [id]: friends ? { is_friend: true, friend_request: null } : { is_friend: false, friend_request: 'sent' } }));
    toast(friends ? t('You’re now friends') : t('Friend request sent'));
  }

  /** 这天的请求：右滑和点爱心一样，直接约，不再让人选 */
  async function invite(card: DayCandidate) {
    const venue = inviteVenue(filter, card);
    if (!venue || leaving) return;
    next(dayItem(card), 'right');
    const starts = inviteStart(card).toISOString();
    const singles = card.mode === 'singles' && !card.mixed;
    const { error } = await supabase!.rpc(singles ? 'invite_ticket' : 'invite_doubles', { p_ticket: card.ticket, p_venue: venue.id, p_starts_at: starts });
    if (error) {
      toast(inviteProblem(error), 'error');
      // 没约成（网络、撞时间等）：卡片放回最前面，还能再滑；TA 已经约不了的就不放回
      if (error.message !== 'not_available') {
        seen.current.delete(card.ticket);
        setTimeout(() => setCards((list) => [card, ...(list ?? []).filter((c) => c.ticket !== card.ticket)]), 300);
      }
      return;
    }
    toast(singles ? t('Invited them to play singles at {time} at {venue}. If they confirm, the game is on.', { time: timeOf(starts), venue: venue.name })
      : t('Opened a doubles game and invited them. Players nearby can join.'));
  }

  // 拖动：从按钮、链接上开始的不算（还能点）
  function down(event: ReactPointerEvent<HTMLElement>) {
    if (leaving || event.button !== 0 || (event.target as HTMLElement).closest('a, button')) return;
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
    const dy = event.clientY - s.y;
    if (dx > SWIPE) like(top);
    else if (dx < -SWIPE) skip(top);
    else {
      settle();
      // 没怎么动：是点了一下卡片，打开 TA 的资料
      if (Math.abs(dx) < 8 && Math.abs(dy) < 8) navigate(`/players/${top.card.user.id}/`);
    }
  }
  function cancel() {
    start.current = null;
    setDrag({ x: 0, y: 0, active: false });
  }

  const x = leaving === 'left' ? -1.2 * innerWidth : leaving === 'right' ? 1.2 * innerWidth : drag.x;
  const inNearby = top?.kind === 'nearby';
  // 这天的卡片刷完了、第一次看到附近的人：上面一条虚线框
  const divider = !lobby && inNearby && nearbySeen === 0 && !deck?.some((item) => item.kind === 'day');
  const second = deck?.[1];
  const actions = { onSlot: (card: NearbyPlayer, slot: UsualTime) => compose({ card, slot }) };
  const friend = top ? friendOf(top) : undefined;
  // 这天有过请求（滑过的也算）：刷完了说“都看完了”，一个都没有说“这天还没人约”
  const dayHadCards = (cards?.length ?? 0) > 0 || [...seen.current].some((key) => !key.startsWith('n:'));
  const filters = activeCount(filter) + (date ? 1 : 0);

  return (
    // 附近范围、一排头像在上面，卡片占满剩下的高度，三个按钮在标签栏上面
    <div className="mx-auto flex min-h-[calc(100dvh-4rem-1.25rem-var(--tabbar)-1.5rem)] w-full max-w-md flex-col gap-3 lg:min-h-[calc(100dvh-4rem-2rem-4rem)]">
      <header className="flex items-center gap-2.5">
        <h1 className="sr-only">{t('Discover')}</h1>
        <RangePicker open={ranging} onOpen={() => setRanging(true)} onClose={() => setRanging(false)} />
        <IconButton icon="building" label={t('Courts')} to="/courts/" />
        <IconButton icon="filter" label={filters ? t('Filters · {n}', { n: filters }) : t('Filters')} badge={filters} onClick={() => setEditing(true)} />
      </header>

      {deck && deck.length > 0 && <People items={deck} onPick={(key) => !leaving && setFront(key)} />}

      {/* 选了的条件（点 ✕ 去掉） */}
      {filters > 0 && (
        <div className="rail gap-2! py-0!">
          {date && (
            <button type="button" onClick={() => onDate(undefined)} aria-label={t('Remove {name}', { name: dayLabel(date, days.indexOf(date)) })}
                    className="press flex min-h-9 items-center gap-1 rounded-full border-2 border-stroke bg-lime px-3 text-footnote font-bold text-on-accent">
              {dayLabel(date, days.indexOf(date))} <Icon name="x" className="size-3" />
            </button>
          )}
          {chips(filter, places(cards, nearby)).map(([label, clear]) => (
            <button key={label} type="button" onClick={() => setFilter(clear(filter))} aria-label={t('Remove {name}', { name: label })}
                    className="press flex min-h-9 items-center gap-1 rounded-full border-2 border-stroke bg-lime px-3 text-footnote font-bold text-on-accent">
              {label} <Icon name="x" className="size-3" />
            </button>
          ))}
        </div>
      )}

      <div className="relative flex min-h-[24rem] flex-1 flex-col">
        {!area ? (
          <div className="grid flex-1 content-center"><AreaPrompt /></div>
        ) : !loaded ? (
          <Skeleton className="flex-1 rounded-[var(--radius-card)]" />
        ) : !top && total > 0 ? (
          <div className="grid flex-1 content-center">
            <Empty icon="filter" tint="butter" title={t('No one matches your filters')} action={{ label: t('Clear filters'), onClick: () => setFilter(emptyFilter) }} />
          </div>
        ) : !top ? (
          // 都看完了 / 这天还没人约：发个约球请求，或者扩大范围
          <div className="sticker grid flex-1 content-center justify-items-center gap-3 p-6 text-center">
            <IconTile icon="users" tint="sky" size="xl" className="-rotate-6" />
            <p className="text-title3">{date && !dayHadCards ? t('No one’s posted for this day yet') : t('You’ve seen everyone nearby')}</p>
            <div className="mt-1 flex flex-wrap justify-center gap-2">
              <Link to={date ? `/play/?date=${date}` : '/play/'} className="button">{t('Send a match request')}</Link>
              <button type="button" onClick={() => setRanging(true)} className="button button-quiet">{t('Widen search')}</button>
            </div>
          </div>
        ) : (
          <div className="flex flex-1 flex-col gap-3">
            {divider && (
              <div className="grid shrink-0 justify-items-center gap-0.5 rounded-[var(--radius-card)] border-2 border-dashed border-stroke bg-butter/40 px-4 py-3 text-center">
                <p className="text-headline">{t('That’s everyone for this day')}</p>
                <p className="text-footnote font-bold text-ink-secondary">{t('Next: players who often play nearby')}</p>
              </div>
            )}
            <div className="relative min-h-[22rem] flex-1">
              {second && (
                <div aria-hidden="true" inert className="pointer-events-none absolute inset-0 translate-y-2.5 scale-[0.96]">
                  <Card item={second} filter={filter} />
                </div>
              )}
              <div
                key={top.key}
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
                <Card item={top} filter={filter} hint={leaving ?? (drag.x > 40 ? 'right' : drag.x < -40 ? 'left' : undefined)} actions={actions} />
              </div>
            </div>
          </div>
        )}
      </div>

      {top && friend && (
        <div className="flex items-center justify-center gap-6 pt-1">
          <Round icon="x" label={t('Skip')} className="size-16 bg-surface text-ink" disabled={Boolean(leaving)} onClick={() => skip(top)} />
          <Round icon="heart" label={t('Invite')} className="size-[4.5rem] bg-lime text-on-accent" disabled={Boolean(leaving)} onClick={() => like(top)} />
          {/* 申请过了：看着是灰的，点了提示“已申请” */}
          <Round icon={friend.is_friend ? 'chat' : friend.friend_request === 'sent' ? 'check' : 'star'}
                 label={friend.is_friend ? t('Send a message') : friend.friend_request === 'sent' ? t('Requested') : friend.friend_request === 'received' ? t('Accept') : t('Add friend')}
                 className={`size-16 bg-butter text-on-accent ${friend.friend_request === 'sent' ? 'opacity-60' : ''}`}
                 disabled={Boolean(leaving) || befriending} onClick={() => void star(top)} />
        </div>
      )}

      {/* 筛选：哪天、项目、球馆、等级、时间、对方性别、只看没爽约过的 */}
      <dialog
        ref={dialog}
        aria-labelledby="filter-title"
        onClose={() => setEditing(false)}
        onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
        className="m-0 mt-auto max-h-[90dvh] w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet sm:m-auto sm:max-w-md sm:open:animate-pop"
      >
        {editing && (
          <FilterSheet initial={filter} date={date} days={days} cards={cards ?? []} nearby={nearby?.filter((c) => !dayPeople.has(c.user.id)) ?? []}
                       onDone={(next, day) => { setFilter(next); if (day !== date) onDate(day); setEditing(false); }} onCancel={() => setEditing(false)} />
        )}
      </dialog>

      {/* 约附近的人：项目、哪天、几点到几点、球馆 */}
      <InviteSheet open={Boolean(composing)} onClose={() => setComposing(undefined)}
                   other={composing?.card.user ?? ({} as InviteUser)} venues={composing?.card.venues} slot={composing?.slot} date={date}
                   onSent={({ remaining, label }) => composing && sent(composing.card, remaining, label)}
                   onError={(error) => composing && failed(composing.card, error)} />

      {/* 第一次约附近的人之前：先让附近的人能看到你；没有照片的提醒一次 */}
      <Sheet open={asking?.kind === 'visible'} onClose={() => setAsking((a) => (a?.kind === 'visible' ? undefined : a))} labelledBy="visible-title">
        <h2 id="visible-title" className="text-title3">{t('Let players nearby see you too')}</h2>
        <div className="grid grid-cols-[1fr_2fr] gap-3">
          <Button variant="quiet" onClick={() => setAsking(undefined)}>{t('No thanks')}</Button>
          <Button onClick={() => asking && void becomeVisible(asking)}>{t('Turn on')}</Button>
        </div>
      </Sheet>
      <Sheet open={asking?.kind === 'photo'} onClose={() => setAsking((a) => (a?.kind === 'photo' ? undefined : a))} labelledBy="photo-title">
        <h2 id="photo-title" className="text-title3">{t('Add a photo?')}</h2>
        <div className="sticker flex items-center gap-3 p-3">
          <Avatar id={profile.id} name={profile.nickname} photo={profile.avatar_path} size={44} />
          <p className="text-subhead font-bold">{t('This card is what others see when they find you.')}</p>
        </div>
        <label className="button button-lg w-full cursor-pointer">
          {t('Choose photo')}
          <input type="file" accept="image/*" className="sr-only"
                 onChange={(e) => { const file = e.target.files?.[0]; e.target.value = ''; if (file && asking) void pickPhoto(file, asking); }} />
        </label>
        <Button className="button-lg w-full" variant="quiet" onClick={() => { const c = asking; setAsking(undefined); if (c) setComposing(c); }}>{t('Add later')}</Button>
      </Sheet>
      {cropping && <AvatarCrop image={cropping.image} card onDone={uploadPhoto} onCancel={() => { cropping.image.close(); setCropping(undefined); }} />}
    </div>
  );
}

type FriendState = Pick<NearbyPlayer, 'is_friend' | 'friend_request'>;
type CardActions = { onSlot: (card: NearbyPlayer, slot: UsualTime) => void };

/** 一张铺满的卡片：这天的请求，或附近的人。actions：最上面那张才能点 */
function Card({ item, filter, hint, actions }: { item: Item; filter: DayFilter; hint?: 'left' | 'right'; actions?: CardActions }) {
  return item.kind === 'day' ? <DayRequestCard card={item.card} filter={filter} hint={hint} /> : <NearbyCard card={item.card} filter={filter} hint={hint} actions={actions} />;
}

/** 左滑右滑时盖在照片上的字 */
function Stamp({ hint, like }: { hint?: 'left' | 'right'; like: string }) {
  if (!hint) return null;
  return (
    <span aria-hidden="true" className={`absolute top-4 rounded-[12px] border-2 border-stroke px-3 py-1 text-headline font-black ${hint === 'right' ? 'left-4 -rotate-6 bg-lime text-on-accent' : 'right-4 rotate-6 bg-surface text-ink'}`}>
      {hint === 'right' ? like : t('Skip')}
    </span>
  );
}

/** 附近的人：左上角多远 · 常去哪家（选了球馆就是选的那家），下面偏好单打还是双打、空闲时间（点一个就约）。不显示具体位置 */
function NearbyCard({ card, filter, hint, actions }: { card: NearbyPlayer; filter: DayFilter; hint?: 'left' | 'right'; actions?: CardActions }) {
  const venue = inviteVenue(filter, card);
  const mode = card.user.preferred_mode;
  const where = venue ? [venue.km != null && distance(venue.km * 1000), t('Often plays at {venue}', { venue: venue.name })].filter(Boolean).join(' · ') : t('Plays nearby');
  return (
    <DayCard
      person={card.user as CardPerson}
      label={where}
      details={[mode && (mode === 'doubles' ? t('Doubles') : t('Singles'))]}
      reliable={(card.user.recent_no_shows ?? 0) === 0}
      profile
      footer={<UsualChips times={card.user.usual_times} onPick={(slot) => actions?.onSlot(card, slot)} />}
    >
      <Stamp hint={hint} like={t('Invite')} />
    </DayCard>
  );
}

/** 这天的请求：左上角星期几、时间、项目，下面是球馆（约在哪家的那家排第一） */
function DayRequestCard({ card, filter, hint }: { card: DayCandidate; filter: DayFilter; hint?: 'left' | 'right' }) {
  const event = eventLabel(card.mode, eventOf(card.play_with, card.mixed)) ?? (card.mode === 'doubles' ? t('Doubles') : t('Singles'));
  const first = inviteVenue(filter, card);
  const venues = first ? [first, ...(card.venues ?? []).filter((v) => v.id !== first.id)] : card.venues ?? [];
  const weekday = new Intl.DateTimeFormat(currentLocale(), { weekday: 'short' }).format(new Date(card.starts_at));
  return (
    <DayCard
      person={card.user}
      label={`${weekday} ${timeOf(card.starts_at)}–${timeOf(card.ends_at)} · ${event}`}
      details={venues.map((v) => v.name)}
      reliable={(card.user.recent_no_shows ?? 0) === 0}
      profile
    >
      <Stamp hint={hint} like={t('Invite')} />
    </DayCard>
  );
}

/** 卡片页上没有让人选时间，有些通用的错误说法会让人看不懂，换成这里的说法 */
function inviteProblem(error: { message: string }) {
  switch (error.message) {
    case 'overlapping': return t('You already have a game or a pending invite at this time.');
    case 'too_soon':
    case 'invalid_slot': return t('Their time is too soon to invite them now.');
    case 'too_many_requests': return t('You’ve sent a lot of invites today. Try again tomorrow.');
    case 'too_many_invites': return t('You’re already waiting on 3 replies for this day. Invite more once someone replies.');
    case 'too_many_rooms': return t('You already have 3 open games. Close one before inviting for doubles.');
    case 'invalid_event': return t('Add your gender in your profile to invite for mixed doubles.');
    default: return problem(error);
  }
}

type Places = { venues: DayCandidate['venues'] }[];
/** 筛选里能选的球馆：这天的请求和常在附近的人去的 */
const places = (cards: DayCandidate[] = [], nearby: NearbyPlayer[] = []): Places => [...cards, ...nearby];

/** 卡片里出现的球馆，按人数排 */
function venueCounts(cards: Places) {
  const counts = new Map<string, { id: string; name: string; count: number }>();
  for (const card of cards) for (const v of card.venues ?? []) counts.set(v.id, { id: v.id, name: v.name, count: (counts.get(v.id)?.count ?? 0) + 1 });
  return [...counts.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

/** 选了的条件：显示的字 + 去掉它 */
function chips(f: DayFilter, cards: Places): [string, (f: DayFilter) => DayFilter][] {
  const list: [string, (f: DayFilter) => DayFilter][] = [];
  if (f.event !== 'any') list.push([eventLabels()[f.event], (x) => ({ ...x, event: 'any' })]);
  if (f.venues.length) {
    const names = f.venues.map((id) => venueCounts(cards).find((v) => v.id === id)?.name ?? f.venueNames[id] ?? id);
    list.push([names.length === 1 ? names[0] : t('{n} courts', { n: f.venues.length }), (x) => ({ ...x, venues: [] })]);
  }
  if (f.minLevel > 1 || f.maxLevel < 9) list.push([`Lv.${f.minLevel}–${f.maxLevel}`, (x) => ({ ...x, minLevel: 1, maxLevel: 9 })]);
  if (f.times.length) list.push([f.times.map((x) => timeLabels()[x]).join(', '), (x) => ({ ...x, times: [] })]);
  if (f.gender) list.push([f.gender === 'male' ? t('Men') : t('Women'), (x) => ({ ...x, gender: null })]);
  if (f.reliableOnly) list.push([t('No missed games'), (x) => ({ ...x, reliableOnly: false })]);
  return list;
}

function FilterSheet({ initial, date, days, cards, nearby, onDone, onCancel }: {
  initial: DayFilter;
  date?: string;
  days: string[];
  cards: DayCandidate[];
  nearby: NearbyPlayer[];
  onDone: (f: DayFilter, date?: string) => void;
  onCancel: () => void;
}) {
  const [draft, setDraft] = useState(initial);
  const [day, setDay] = useState(date);
  const counts = useDayCounts();
  const set = (patch: Partial<DayFilter>) => setDraft((d) => ({ ...d, ...patch }));
  // 常在附近的人也算进去
  const count = cards.filter((c) => matches(draft, c)).length + nearby.filter((c) => matchesNearby(draft, c)).length;
  const all = places(cards, nearby);
  const toggle = <T,>(list: T[], value: T) => (list.includes(value) ? list.filter((x) => x !== value) : [...list, value]);
  const section = 'grid gap-2';
  const label = 'text-footnote font-bold text-ink-secondary';
  const chip = (on: boolean) => `toggle ${on ? '' : ''}`;
  return (
    <form method="dialog" onSubmit={(e) => { e.preventDefault(); onDone(draft, day); }}
          className="grid max-h-[90dvh] grid-rows-[auto_1fr_auto] rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas sm:rounded-[28px] sm:border-b-2 sm:shadow-card">
      <div className="flex items-center gap-3 px-5 pt-5">
        <h2 id="filter-title" className="flex-1 text-title3">{t('Filters')}</h2>
        <button type="button" className="link text-footnote font-bold" onClick={() => { setDraft(emptyFilter); setDay(undefined); }}>{t('Reset')}</button>
        <IconButton icon="x" label={t('Close')} onClick={onCancel} />
      </div>
      <div className="grid content-start gap-5 overflow-y-auto px-5 py-4">
        {/* 哪天：任何时间（附近的人），或者某一天在找人的；一周以后只列有人的天 */}
        <div className={section} role="group" aria-labelledby="f-date">
          <span id="f-date" className={label}>{t('Date')}</span>
          <div className="flex flex-wrap gap-2">
            <button type="button" className="toggle" aria-pressed={!day} onClick={() => setDay(undefined)}>{t('Any time')}</button>
            {days.map((d, i) => {
              const n = counts?.[d] ?? 0;
              if (i >= 7 && !n && d !== day) return null;
              const full = dateChip(d, i).full;
              return (
                <button key={d} type="button" className="toggle" aria-pressed={day === d} onClick={() => setDay(d)}
                        aria-label={counts ? full + t(', {n} available', { n }) : full}>
                  {dayLabel(d, i)}
                  {n > 0 && <span aria-hidden="true" className="tabular-nums opacity-70">{n}</span>}
                </button>
              );
            })}
          </div>
        </div>
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
          {[...venueCounts(all), ...initial.venues.filter((id) => !venueCounts(all).some((v) => v.id === id))
              .map((id) => ({ id, name: initial.venueNames[id] ?? id, count: 0 }))].map((v) => (
            <button key={v.id} type="button" aria-pressed={draft.venues.includes(v.id)}
                    onClick={() => set({ venues: toggle(draft.venues, v.id), venueNames: { ...draft.venueNames, [v.id]: v.name } })}
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
        {/* 换了日子要重新查，数不出有几个人 */}
        <Button className="w-full">{day === date ? t('Show {n} player|Show {n} players', { n: count }) : t('Done')}</Button>
      </div>
    </form>
  );
}

function Round({ icon, label, className, disabled, onClick }: { icon: IconName; label: string; className: string; disabled: boolean; onClick: () => void }) {
  return (
    <button type="button" aria-label={label} title={label} disabled={disabled} onClick={onClick}
            className={`press grid place-items-center rounded-full border-2 border-stroke shadow-low disabled:opacity-60 ${className}`}>
      <Icon name={icon} className="size-7" />
    </button>
  );
}

/** 日子的叫法：明天、一周以内写星期几（今天是“今天”），再往后写几月几号 */
function dayLabel(d: string, i: number) {
  return i === 1 ? capitalize(new Intl.RelativeTimeFormat(currentLocale(), { numeric: 'auto' }).format(1, 'day'))
    : i >= 0 && i < 7 ? dateChip(d, i).label
    : new Intl.DateTimeFormat(currentLocale(), { month: 'short', day: 'numeric', timeZone: 'UTC' }).format(new Date(`${d}T12:00:00Z`));
}

/** 接下来每天附近有几个人在找（和日期上的卡片同一套条件） */
function useDayCounts() {
  const area = useArea();
  const km = useNearbyKm();
  const [counts, setCounts] = useState<Record<string, number>>();
  useEffect(() => {
    if (!area) return;
    let stale = false;
    supabase!
      .rpc('pool_by_day', { p_lat: area.lat, p_lon: area.lon, p_radius_km: km, p_tz: Intl.DateTimeFormat().resolvedOptions().timeZone })
      .then(({ data }) => !stale && setCounts((data ?? {}) as Record<string, number>));
    return () => {
      stale = true;
    };
  }, [area?.lat, area?.lon, km]);
  return counts;
}

/** 左上角：小字“附近”，大字“10 公里内 ▾”。点开选 5 / 10 / 20 / 50 公里（和 iOS 设置里的附近范围一样） */
function RangePicker({ open, onOpen, onClose }: { open: boolean; onOpen: () => void; onClose: () => void }) {
  const km = useNearbyKm();
  const within = (n: number) => t('Within {distance}', { distance: distance(n * 1000) });
  return (
    <>
      <button type="button" aria-haspopup="dialog" onClick={onOpen} className="press grid min-w-0 flex-1 justify-items-start text-left">
        <span className="text-caption font-bold text-ink-secondary">{t('Nearby')}</span>
        <span className="flex max-w-full items-center gap-1 text-title3">
          <span className="truncate">{within(km)}</span>
          <Icon name="chevronDown" className="size-4 shrink-0" />
        </span>
      </button>
      <Sheet open={open} onClose={onClose} labelledBy="range-title">
        <div className="flex items-center gap-3">
          <h2 id="range-title" className="flex-1 text-title3">{t('Nearby range')}</h2>
          <IconButton icon="x" label={t('Close')} onClick={onClose} />
        </div>
        <div className="grid gap-2">
          {RANGES.map((n) => (
            <button key={n} type="button" aria-pressed={km === n} onClick={() => { if (n !== km) setNearbyKm(n); onClose(); }}
                    className={`press flex min-h-12 items-center rounded-[14px] border-2 border-stroke px-4 text-left text-headline ${km === n ? 'bg-lime text-on-accent' : 'bg-surface'}`}>
              {within(n)}
            </button>
          ))}
        </div>
      </Sheet>
    </>
  );
}

/** 卡片上面一排圆头像：这叠卡片里的人，正在看的那个是柠檬绿的圈。点别人就翻到 TA */
function People({ items, onPick }: { items: Item[]; onPick: (key: string) => void }) {
  return (
    <ul className="rail gap-3! py-0.5!" aria-label={t('Players nearby')}>
      {items.map((item, i) => {
        const user = item.card.user;
        return (
          <li key={item.key}>
            <button type="button" aria-current={i === 0 || undefined} aria-label={user.nickname} onClick={() => i > 0 && onPick(item.key)}
                    className="press grid w-16 justify-items-center gap-1">
              <span className={`grid size-16 place-items-center rounded-full border-2 border-stroke p-[3px] ${i === 0 ? 'bg-lime' : 'bg-surface'}`}>
                <Avatar id={user.id} name={user.nickname} photo={user.avatar} size={52} />
              </span>
              <span className="w-full truncate text-center text-caption font-bold">{user.nickname}</span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}
