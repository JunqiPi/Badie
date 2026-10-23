import { useState, type SubmitEvent } from 'react';
import { eventLabel, eventOf, type Gender } from './gender';
import { t } from './i18n';
import { SlotFields, slotTimes, type Slot } from './NewRoom';
import { Icon } from './icons';
import { Avatar, Divider, Empty, IconButton, IconTile, LevelBadge, Notice, Row, ScreenHeader, Tag } from './kit';
import { Link, navigate } from './router';
import { roomWhen, tagText } from './Rooms';
import { problem, supabase, useLive, type Friend, type RoomDetail } from './supabase';
import { today, wallClock } from './time';
import { Button, Skeleton, toast } from './ui';

const closedText = (reason: NonNullable<RoomDetail['closed_reason']>) =>
  ({
    owner_closed: t('The host cancelled this game.'),
    start_time_passed: t('It didn’t fill up before the start time.'),
    expired: t('It closed after 30 minutes without activity.'),
  })[reason];

/** gender：看的人自己的性别，混双局用来判断自己这边满没满 */
export function RoomPage({ id, gender }: { id: string; gender: Gender | null }) {
  const { data: r, refresh } = useLive<RoomDetail | null>('room_page', { args: { p_room: id }, every: 15_000 });
  const [busy, setBusy] = useState<string>();
  const [confirm, setConfirm] = useState<string>();

  async function act(name: string, fn: string, args: Record<string, unknown>, done?: string) {
    setBusy(name);
    const { data, error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    setConfirm(undefined);
    if (error) toast(problem(error), 'error');
    else if (done) toast(done);
    refresh();
    return error ? undefined : data;
  }

  if (r === undefined) return <Skeleton className="h-96 max-w-3xl" />;
  if (r === null) {
    return (
      <Empty icon="court" tint="peach" title={t('Game not found')} action={{ label: t('Nearby games'), to: '/rooms/' }}>
        {t('It may be private, or the host closed it.')}
      </Empty>
    );
  }

  const inside = r.my_status === 'owner' || r.my_status === 'member';
  const open = r.status === 'open';
  const going = r.members?.filter((m) => !m.waitlisted) ?? [];
  const waiting = r.members?.filter((m) => m.waitlisted) ?? [];
  // 混双男女各两个位子：自己这边满了也只能候补
  const full = r.going >= r.capacity || (r.mixed && !!gender && (r.mixed_going?.[gender] ?? 0) >= 2);
  const room = { p_room: r.id };

  async function join() {
    const status = await act('join', 'join_room', room);
    if (status === 'waitlisted') toast(t('You’re on the waitlist. You’ll get a notification if a spot opens.'));
    else if (status) toast(t('Joined. The host starts the game when every spot is filled.'));
  }

  async function copyInvite() {
    const text = t('Join my badminton game on Badie: {when} at {court}. Open {link} and enter code {code}.', {
      when: roomWhen(r!), court: r!.venue?.name ?? '', link: `${location.origin}/join/?code=${r!.code ?? ''}`, code: r!.code ?? '',
    });
    try {
      await navigator.clipboard.writeText(text);
      toast(t('Invite copied. Paste it into your chat.'));
    } catch {
      toast(t('Room code: {code}', { code: r!.code ?? '' }));
    }
  }

  return (
    <div className="grid gap-6">
      <ScreenHeader title={r.visibility === 'private' ? t('Private room') : t('Public game')} back="/rooms/">
        {inside && <IconButton icon="share" label={t('Copy invite')} onClick={copyInvite} />}
      </ScreenHeader>

      {r.status === 'started' && (
        <Notice icon="checkCircle" tint="mint" action={inside && r.game_id ? { label: t('View game'), to: `/games/${r.game_id}/` } : undefined}>
          {t('Game confirmed. Everyone’s in.')}
        </Notice>
      )}
      {r.status === 'closed' && r.closed_reason && (
        <Notice icon="xCircle" tint="muted">{t('This game is closed')} · {closedText(r.closed_reason)}</Notice>
      )}

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start lg:gap-8">
        <div className="grid min-w-0 gap-6">
          {r.code && (
            <section aria-labelledby="code" className="sticker grid gap-3 bg-lavender p-5 text-on-accent">
              <div className="flex items-center justify-between">
                <h2 id="code" className="kicker">{t('Room code')}</h2>
                <Tag>{r.mode === 'doubles' ? t('Doubles') : t('Singles')} · {r.going}/{r.capacity}</Tag>
              </div>
              <p className="grid grid-cols-6 gap-2" aria-label={r.code}>
                {[...r.code].map((ch, i) => (
                  <span key={i} aria-hidden="true" className="grid aspect-square place-items-center rounded-[12px] border-2 border-[#17140f] bg-white font-mono text-[1.75rem] font-black text-[#17140f]">{ch}</span>
                ))}
              </p>
              {inside && <Button className="button-inverse" onClick={copyInvite}><Icon name="copy" className="size-4" />{t('Copy invite')}</Button>}
            </section>
          )}

          <section aria-label={t('Details')} className="sticker grid px-4 py-1">
            <Row icon="clock" tint="peach" title={roomWhen(r)} subtitle={t('Hosted by {name}', { name: r.owner.nickname })} />
            <Divider />
            <Row icon="pin" tint="sky" title={r.venue ? r.venue.name : t('Court not set yet')} subtitle={r.venue ? [r.venue.street, r.venue.city].filter(Boolean).join(', ') : undefined} />
            <Divider />
            <Row icon="level" tint="lavender" title={t('Lv.{min}–{max}', { min: r.level_min, max: r.level_max })}
                 subtitle={[eventLabel(r.mode, eventOf(r.gender, r.mixed)), ...r.tags.map(tagText)].filter(Boolean).join(' · ') || undefined} />
            {r.note && (
              <>
                <Divider />
                <Row icon="chat" tint="mint" title={r.note} />
              </>
            )}
          </section>

          <section aria-labelledby="players" className="sticker grid gap-3 p-5">
            <h2 id="players" className="flex items-baseline justify-between gap-2 text-headline">
              {t('Players')} <span className="text-footnote font-bold text-ink-secondary tabular-nums">
                {r.mixed_going ? t('Men {men}/2 · Women {women}/2', { men: r.mixed_going.male, women: r.mixed_going.female }) : t('{n} of {total}', { n: r.going, total: r.capacity })}
              </span>
            </h2>
            {r.members ? (
              <ul className="grid gap-2">
                {going.map((m) => (
                  <li key={m.id} className="flex min-h-12 items-center gap-3">
                    <Link to={m.me ? '/me/' : `/players/${m.id}/`} className="press flex min-w-0 flex-1 items-center gap-3">
                      <Avatar id={m.id} name={m.nickname} size={40} />
                      <span className="grid min-w-0 justify-items-start gap-0.5">
                        <span className="max-w-full truncate font-bold">{m.me ? t('You') : m.nickname}</span>
                        <span className="flex gap-1"><LevelBadge rating={m.rating} named={false} compact />{m.id === r.owner.id && <Tag tint="butter">{t('Host')}</Tag>}</span>
                      </span>
                    </Link>
                    {r.my_status === 'owner' && open && m.id !== r.owner.id && (confirm === `remove-${m.id}` ? (
                      <Button variant="danger" className="button-sm" busy={busy === `remove-${m.id}`}
                              onClick={() => act(`remove-${m.id}`, 'remove_room_member', { ...room, p_user: m.id }, t('Removed'))}>{t('Remove')}</Button>
                    ) : (
                      <button onClick={() => setConfirm(`remove-${m.id}`)} className="link text-footnote">{t('Remove')}</button>
                    ))}
                  </li>
                ))}
                {open && Array.from({ length: Math.max(0, r.capacity - going.length) }, (_, i) => (
                  <li key={`open-${i}`} className="flex min-h-12 items-center gap-3 text-footnote font-bold text-ink-secondary">
                    <span aria-hidden="true" className="size-10 rounded-full border-2 border-dashed border-stroke bg-surface" />
                    {t('Open spot')}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-footnote text-ink-secondary">{t('Join to see who’s playing.')}</p>
            )}
            {waiting.length > 0 && (
              <p className="text-footnote text-ink-secondary">
                <span className="font-bold">{t('Waitlist')}:</span> {waiting.map((m) => (m.me ? t('You') : m.nickname)).join(', ')}
              </p>
            )}
            {!r.members && r.waitlist > 0 && <p className="text-footnote text-ink-secondary">{t('{n} waiting', { n: r.waitlist })}</p>}
          </section>
        </div>

        {open && (
          <aside className={`grid gap-4 lg:sticky lg:top-24 ${inside ? '' : 'order-first lg:order-none'}`} aria-label={t('Your spot')}>
            <section className={`sticker grid gap-3 p-5 ${r.my_status === 'member' || r.my_status === 'owner' ? 'bg-lime/45' : ''}`}>
              {(r.my_status === null || r.my_status === 'invited') && (
                <>
                  {r.my_status === 'invited' && <p className="font-bold">{t('{name} invited you to play.', { name: r.owner.nickname })}</p>}
                  <Button className="button-lg" busy={busy === 'join'} onClick={join}>{full ? t('Join waitlist') : t('Join game')}</Button>
                  {r.my_status === null && <p className="text-footnote text-ink-secondary">{t('For levels {min}–{max}. You can leave any time before it starts.', { min: r.level_min, max: r.level_max })}</p>}
                </>
              )}
              {r.my_status === 'member' && <p className="flex items-center gap-2 font-bold"><Icon name="checkCircle" className="size-5" />{t('You’re in. The host starts the game when every spot is filled.')}</p>}
              {r.my_status === 'waitlisted' && <p className="font-bold">{t('You’re on the waitlist. You’ll get a notification if a spot opens.')}</p>}

              {r.my_status === 'owner' && (
                full && r.starts_at && r.venue ? (
                  <Button className="button-lg" busy={busy === 'start'} onClick={() => act('start', 'start_room', room, t('Game confirmed. Everyone’s been told.'))}>{t('Start game')}</Button>
                ) : (
                  <p className="font-bold">
                    {!r.starts_at || !r.venue ? t('Set the time and court, then start when it’s full.') : t('Start when all {n} spots are filled.', { n: r.capacity })}
                  </p>
                )
              )}

              {r.my_status && r.my_status !== 'invited' && (confirm === 'leave' ? (
                <Button variant="danger" busy={busy === 'leave'}
                        onClick={() => act('leave', 'leave_room', room, r.my_status === 'owner' ? t('Game cancelled. Everyone’s been told.') : t('You left the game'))}>
                  {r.my_status === 'owner' ? t('Yes, cancel for everyone') : t('Yes, leave')}
                </Button>
              ) : (
                <button type="button" onClick={() => setConfirm('leave')} className="min-h-11 text-footnote font-bold text-danger hover:underline">
                  {r.my_status === 'owner' ? t('Cancel game') : t('Leave game')}
                </button>
              ))}
            </section>

            {inside && <InviteFriends room={r} onSent={refresh} />}
            {r.my_status === 'owner' && <EditSlot room={r} onSaved={refresh} />}
          </aside>
        )}
      </div>
    </div>
  );
}

/** 邀请球友：受邀的人不受水平范围限制 */
function InviteFriends({ room, onSent }: { room: RoomDetail; onSent: () => void }) {
  const [friends, setFriends] = useState<Friend[]>();
  const [picked, setPicked] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const inRoom = new Set(room.members?.map((m) => m.id));

  async function load(open: boolean) {
    if (!open || friends) return;
    const { data } = await supabase!.rpc('my_friends');
    setFriends(((data as { friends: Friend[] } | null)?.friends ?? []).filter((f) => !inRoom.has(f.id)));
  }

  async function send() {
    setBusy(true);
    const { data, error } = await supabase!.rpc('invite_to_room', { p_room: room.id, p_users: picked });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    toast(t('Invited {n} friend|Invited {n} friends', { n: data as number }));
    setFriends(friends?.filter((f) => !picked.includes(f.id)));
    setPicked([]);
    onSent();
  }

  return (
    <details onToggle={(e) => load(e.currentTarget.open)} className="sticker p-5">
      <summary className="flex cursor-pointer items-center gap-3 font-bold"><IconTile icon="userPlus" tint="mint" size="sm" />{t('Invite friends')}</summary>
      <div className="mt-3 grid gap-2">
        {!friends && <Skeleton className="h-16" />}
        {friends?.length === 0 && <p className="text-sm text-ink-secondary">{t('No friends to invite yet. Players become friends after a game together.')}</p>}
        {friends?.map((f) => (
          <label key={f.id} className="flex min-h-11 items-center gap-3">
            <input type="checkbox" checked={picked.includes(f.id)} className="size-5 accent-[var(--color-lime)]"
                   onChange={(e) => setPicked(e.target.checked ? [...picked, f.id].slice(0, 10) : picked.filter((p) => p !== f.id))} />
            <span className="min-w-0 flex-1 truncate font-bold">{f.nickname}</span>
            <LevelBadge rating={f.rating} named={false} compact />
          </label>
        ))}
        {friends && friends.length > 0 && (
          <Button busy={busy} disabled={picked.length === 0} onClick={send} className="justify-self-start">{t('Send invites')}</Button>
        )}
      </div>
    </details>
  );
}

/** 房主改时间或球馆，房间里的人会收到通知 */
function EditSlot({ room, onSaved }: { room: RoomDetail; onSaved: () => void }) {
  const tz = room.venue?.tz ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [slot, setSlot] = useState<Slot>(() => {
    const court = room.venue ? { id: room.venue.id, name: room.venue.name, city: room.venue.city, time_zone_id: room.venue.tz } : undefined;
    if (!room.starts_at || !room.ends_at) return { court, date: today(tz, 1), from: 19 * 60, to: 21 * 60 };
    const start = wallClock(room.starts_at, tz);
    return { court, date: start.date, from: start.minutes, to: wallClock(room.ends_at, tz).minutes };
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const { startsAt, endsAt, issue } = slotTimes(slot);

  async function save() {
    if (issue) return setError(issue);
    setBusy(true);
    setError(undefined);
    const { error } = await supabase!.rpc('update_room', {
      p_room: room.id, p_venue: slot.court!.id, p_starts_at: startsAt.toISOString(), p_ends_at: endsAt.toISOString(),
    });
    setBusy(false);
    if (error) return setError(problem(error));
    toast(t('Saved. Players have been told.'));
    onSaved();
  }

  return (
    <details open={!room.starts_at} className="sticker p-5">
      <summary className="flex cursor-pointer items-center gap-3 font-bold"><IconTile icon="pencil" tint="butter" size="sm" />{room.starts_at ? t('Change time or court') : t('Set the time and court')}</summary>
      <div className="mt-4 grid gap-4">
        <SlotFields slot={slot} onChange={setSlot} />
        {error && <p role="alert" className="font-bold text-danger">{error}</p>}
        <Button busy={busy} onClick={save} className="justify-self-start">{t('Save')}</Button>
      </div>
    </details>
  );
}

/** 输入房间码 / 群号（iOS 的 JoinRoomView）：先找球局，找不到再找球群 */
export function JoinRoom() {
  const [code, setCode] = useState(() => (new URLSearchParams(location.search).get('code') ?? '').toUpperCase().slice(0, 6));
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);

  async function join(event: SubmitEvent) {
    event.preventDefault();
    setBusy(true);
    const { data, error } = await supabase!.rpc('join_room_code', { p_code: code });
    if (!error) return navigate(`/rooms/${data}/`);
    if (error.message === 'room_not_found') {
      const { data: group } = await supabase!.rpc('find_group', { p_code: code });
      if (group) return navigate(`/groups/${group}/`);
    }
    setBusy(false);
    setError(problem(error));
  }

  return (
    <div className="mx-auto grid max-w-lg gap-5">
      <ScreenHeader title={t('Enter a room or group code')} back="/games/" />
      <form onSubmit={join} noValidate className="sticker grid gap-4 bg-lavender p-6 text-on-accent">
        <IconTile icon="hash" tint="surface" size="xl" className="-rotate-6" />
        <div>
          <h2 className="text-title2">{t('Have a code?')}</h2>
          <p className="text-subhead">{t('6-character room or group code from a friend')}</p>
        </div>
        <label htmlFor="code" className="sr-only">{t('Code')}</label>
        <input
          id="code"
          value={code}
          maxLength={6}
          autoFocus
          autoCapitalize="characters"
          autoComplete="off"
          spellCheck={false}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? 'code-error' : undefined}
          onChange={(e) => { setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '')); setError(undefined); }}
          placeholder="ABC234"
          className="field h-16 bg-white text-center font-mono text-[1.75rem] font-black tracking-[0.4em] text-[#17140f] uppercase placeholder:text-[#17140f]/30"
        />
        {error && <p id="code-error" role="alert" className="font-bold">{error}</p>}
        <Button busy={busy} disabled={code.length !== 6} className="button-lg button-inverse">{t('Join')}</Button>
      </form>
    </div>
  );
}
