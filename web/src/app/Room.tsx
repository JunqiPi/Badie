import { useState } from 'react';
import { tier } from './assessment';
import { t } from './i18n';
import { SlotFields, slotTimes, type Slot } from './NewRoom';
import { Link } from './router';
import { RoomChips, roomWhen } from './Rooms';
import { problem, supabase, useLive, type Friend, type RoomDetail } from './supabase';
import { today, wallClock } from './time';
import { Button, EmptyState, Skeleton, toast } from './ui';

const closedText = (reason: NonNullable<RoomDetail['closed_reason']>) =>
  ({
    owner_closed: t('The host cancelled this game.'),
    start_time_passed: t('It didn’t fill up before the start time.'),
    expired: t('It closed after 30 minutes without activity.'),
  })[reason];

export function RoomPage({ id }: { id: string }) {
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
      <EmptyState title={t('Game not found')} action={<Link to="/app/rooms/" className="button">{t('Open games')}</Link>}>
        {t('It may be private, or the host closed it.')}
      </EmptyState>
    );
  }

  const inside = r.my_status === 'owner' || r.my_status === 'member';
  const open = r.status === 'open';
  const going = r.members?.filter((m) => !m.waitlisted) ?? [];
  const waiting = r.members?.filter((m) => m.waitlisted) ?? [];
  const full = r.going >= r.capacity;
  const room = { p_room: r.id };

  async function join() {
    const status = await act('join', 'join_room', room);
    if (status === 'waitlisted') toast(t('You’re on the waitlist. We’ll tell you if a spot opens.'));
    else if (status) toast(t('You’re in! The host starts the game when every spot is filled.'));
  }

  async function copyInvite() {
    const text = t('Join my badminton game on Badie: {when} at {court}. Open {link} and enter code {code}.', {
      when: roomWhen(r!), court: r!.venue?.name ?? '', link: `${location.origin}/app/rooms/`, code: r!.code ?? '',
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
      <div>
        <Link to="/app/rooms/" className="link text-sm">{t('Open games')}</Link>
        <p className="eyebrow mt-6">{r.venue ? `${r.venue.name}, ${r.venue.city}` : t('Court not set yet')}</p>
        <h1 className="display mt-2 text-[clamp(2.25rem,6vw,3.5rem)] break-words">{roomWhen(r)}</h1>
        <div className="mt-4"><RoomChips room={r} /></div>
        {r.note && <p className="mt-3 max-w-prose text-lg text-ink-secondary">{r.note}</p>}
        <p className="mt-3 text-sm text-ink-tertiary">
          {t('Hosted by {name}', { name: r.owner.nickname })} · {t('Level {level}', { level: tier(r.owner.rating).label })}
        </p>
      </div>

      {r.status === 'started' && (
        <div className="tile flex flex-wrap items-center justify-between gap-3 bg-mint p-5 text-on-accent">
          <p className="font-black">{t('Game on! Everyone’s in.')}</p>
          {inside && r.game_id && <Link to={`/app/games/${r.game_id}/`} className="button button-quiet">{t('View game')}</Link>}
        </div>
      )}
      {r.status === 'closed' && r.closed_reason && (
        <div className="tile bg-surface-muted p-5">
          <p className="font-black">{t('This game is closed')}</p>
          <p className="text-ink-secondary">{closedText(r.closed_reason)}</p>
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
        <section aria-labelledby="players" className="tile grid gap-3 bg-surface p-5">
          <h2 id="players" className="flex items-baseline justify-between gap-2 text-xl font-black">
            {t('Players')} <span className="text-base font-bold text-ink-tertiary tabular-nums">{t('{n} of {total}', { n: r.going, total: r.capacity })}</span>
          </h2>
          {r.members ? (
            <ul className="grid gap-2">
              {going.map((m) => (
                <li key={m.id} className="flex min-h-11 items-center gap-2">
                  {m.me ? <span className="min-w-0 flex-1 truncate font-black">{t('You')}</span> : (
                    <Link to={`/app/players/${m.id}/`} className="min-w-0 flex-1 truncate font-bold hover:underline">{m.nickname}</Link>
                  )}
                  <span className="text-sm font-semibold text-ink-tertiary">
                    {tier(m.rating).label}{m.id === r.owner.id ? ` · ${t('Host')}` : ''}
                  </span>
                  {r.my_status === 'owner' && open && m.id !== r.owner.id && (confirm === `remove-${m.id}` ? (
                    <Button variant="danger" className="min-h-9! px-3! text-sm" busy={busy === `remove-${m.id}`}
                            onClick={() => act(`remove-${m.id}`, 'remove_room_member', { ...room, p_user: m.id }, t('Removed'))}>{t('Remove')}</Button>
                  ) : (
                    <button onClick={() => setConfirm(`remove-${m.id}`)} className="link text-sm">{t('Remove')}</button>
                  ))}
                </li>
              ))}
              {open && Array.from({ length: Math.max(0, r.capacity - going.length) }, (_, i) => (
                <li key={`open-${i}`} className="flex min-h-11 items-center rounded-[var(--r-control)] border-2 border-dashed border-stroke/30 px-3 text-sm font-bold text-ink-tertiary">
                  {t('Open spot')}
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-ink-secondary">{t('Join to see who’s playing.')}</p>
          )}
          {waiting.length > 0 && (
            <p className="text-sm text-ink-secondary">
              <span className="font-extrabold">{t('Waitlist')}:</span> {waiting.map((m) => (m.me ? t('You') : m.nickname)).join(', ')}
            </p>
          )}
          {!r.members && r.waitlist > 0 && <p className="text-sm text-ink-secondary">{t('{n} waiting', { n: r.waitlist })}</p>}
        </section>

        {open && (
          <aside className={`grid gap-4 lg:sticky lg:top-6 ${inside ? '' : 'order-first lg:order-none'}`}>
            <section aria-label={t('Your spot')} className="tile grid gap-3 bg-surface p-5">
              {(r.my_status === null || r.my_status === 'invited') && (
                <>
                  {r.my_status === 'invited' && <p className="font-bold">{t('{name} invited you to play.', { name: r.owner.nickname })}</p>}
                  <Button busy={busy === 'join'} onClick={join}>{full ? t('Join waitlist') : t('Join game')}</Button>
                  {r.my_status === null && <p className="text-sm text-ink-tertiary">{t('For levels {min}–{max}. You can leave any time before it starts.', { min: r.level_min, max: r.level_max })}</p>}
                </>
              )}
              {r.my_status === 'member' && <p className="font-bold">{t('You’re in. The host starts the game when every spot is filled.')}</p>}
              {r.my_status === 'waitlisted' && <p className="font-bold">{t('You’re on the waitlist. We’ll tell you if a spot opens.')}</p>}

              {r.my_status === 'owner' && (
                full && r.starts_at && r.venue ? (
                  <Button busy={busy === 'start'} onClick={() => act('start', 'start_room', room, t('Game on! Everyone’s been told.'))}>{t('Start game')}</Button>
                ) : (
                  <p className="font-bold">
                    {!r.starts_at || !r.venue ? t('Set the time and court, then start when it’s full.') : t('Start when all {n} spots are filled.', { n: r.capacity })}
                  </p>
                )
              )}

              {r.code && (
                <div>
                  <p className="eyebrow">{t('Room code')}</p>
                  <p className="mt-1 font-mono text-2xl font-black tracking-[0.3em]">{r.code}</p>
                </div>
              )}
              {inside && <Button variant="quiet" onClick={copyInvite}>{t('Copy invite')}</Button>}

              {r.my_status && r.my_status !== 'invited' && (confirm === 'leave' ? (
                <Button variant="danger" busy={busy === 'leave'}
                        onClick={() => act('leave', 'leave_room', room, r.my_status === 'owner' ? t('Game cancelled. Everyone’s been told.') : t('You left the game'))}>
                  {r.my_status === 'owner' ? t('Yes, cancel for everyone') : t('Yes, leave')}
                </Button>
              ) : (
                <Button variant="quiet" onClick={() => setConfirm('leave')}>{r.my_status === 'owner' ? t('Cancel game') : t('Leave game')}</Button>
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
    <details onToggle={(e) => load(e.currentTarget.open)} className="tile bg-surface p-5">
      <summary className="cursor-pointer font-extrabold">{t('Invite friends')}</summary>
      <div className="mt-3 grid gap-2">
        {!friends && <Skeleton className="h-16" />}
        {friends?.length === 0 && <p className="text-sm text-ink-secondary">{t('No friends to invite yet. Players become friends after a game together.')}</p>}
        {friends?.map((f) => (
          <label key={f.id} className="flex min-h-11 items-center gap-3">
            <input type="checkbox" checked={picked.includes(f.id)} className="size-5 accent-[var(--color-lime)]"
                   onChange={(e) => setPicked(e.target.checked ? [...picked, f.id].slice(0, 10) : picked.filter((p) => p !== f.id))} />
            <span className="min-w-0 flex-1 truncate font-bold">{f.nickname}</span>
            <span className="text-sm font-semibold text-ink-tertiary">{tier(f.rating).label}</span>
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
    <details open={!room.starts_at} className="tile bg-surface p-5">
      <summary className="cursor-pointer font-extrabold">{room.starts_at ? t('Change time or court') : t('Set the time and court')}</summary>
      <div className="mt-4 grid gap-4">
        <SlotFields slot={slot} onChange={setSlot} />
        {error && <p role="alert" className="font-bold text-danger">{error}</p>}
        <Button busy={busy} onClick={save} className="justify-self-start">{t('Save')}</Button>
      </div>
    </details>
  );
}
