import { useState } from 'react';
import { tier } from './assessment';
import { activityText, scheduleText } from './Groups';
import { Link } from './router';
import { problem, supabase, useLive, type GroupDetail, type GroupSession } from './supabase';
import { day, hours } from './time';
import { Button, EmptyState, Skeleton, toast } from './ui';

export function GroupPage({ id }: { id: string }) {
  const { data: g, refresh } = useLive<GroupDetail | null>('group_page', { args: { p_group: id }, every: 30_000 });
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

  if (g === undefined) return <Skeleton className="h-96 max-w-3xl" />;
  if (g === null) {
    return <EmptyState title="Group not found" action={<Link to="/app/groups/" className="button">Groups</Link>}>It may have been removed.</EmptyState>;
  }
  const member = g.my_role === 'owner' || g.my_role === 'organizer' || g.my_role === 'member';
  const organizer = g.my_role === 'owner' || g.my_role === 'organizer';
  const tz = g.venue.tz;

  async function join() {
    const status = await act('join', 'join_group', { p_group: g!.id });
    if (status === 'pending') toast('Request sent. An organizer will review it.');
    else if (status) toast(`Welcome to ${g!.name}!`);
  }

  async function copyInvite() {
    const text = `Join “${g!.name}” on Badie: ${g!.schedules.map(scheduleText).join(', ')} at ${g!.venue.name}. Level ${g!.level_min}–${g!.level_max}. `
      + `Open ${location.origin}/app/groups/ and enter group number ${g!.invite_code}.`;
    try {
      await navigator.clipboard.writeText(text);
      toast('Invite copied. Paste it into your chat.');
    } catch {
      toast(`Group number: ${g!.invite_code}`);
    }
  }

  return (
    <div className="grid gap-6">
      <div>
        <Link to="/app/groups/" className="link text-sm">Groups</Link>
        <p className="eyebrow mt-6">{g.venue.name}, {g.venue.city}</p>
        <h1 className="display mt-2 text-[clamp(2.5rem,6vw,3.75rem)] break-words">{g.name}</h1>
        {g.summary && <p className="mt-3 max-w-prose text-lg text-ink-secondary">{g.summary}</p>}
        <div className="mt-4 flex flex-wrap gap-2">
          <span className="chip bg-sky">Level {g.level_min}–{g.level_max}</span>
          {g.join_policy === 'approval' && <span className="chip bg-lavender">Organizer approves</span>}
          {g.schedules.map((s) => <span key={`${s.weekday}-${s.start}`} className="chip bg-butter">{scheduleText(s)}{s.fee ? ` · ${s.fee}` : ''}</span>)}
        </div>
        <p className="mt-3 text-sm text-ink-tertiary">{activityText(g.activity)}</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
        <div className="grid gap-6">
          <section aria-labelledby="sessions" className="grid gap-3">
            <h2 id="sessions" className="text-xl font-black">Next two weeks</h2>
            {g.sessions.length === 0 && <p className="text-ink-secondary">No sessions scheduled.</p>}
            {g.sessions.map((s) => (
              <Session key={s.id} session={s} tz={tz} member={member} organizer={organizer} busy={busy}
                       confirm={confirm} setConfirm={setConfirm} act={act} />
            ))}
          </section>
        </div>

        {/* 还没加入时，“加入”在手机上放到最前面 */}
        <aside className={`grid gap-4 lg:sticky lg:top-6 ${member ? '' : 'order-first lg:order-none'}`}>
          <section aria-label="Membership" className="tile grid gap-3 bg-surface p-5">
            {!g.my_role && (
              <>
                <Button busy={busy === 'join'} onClick={join}>{g.join_policy === 'approval' ? 'Ask to join' : 'Join group'}</Button>
                <p className="text-sm text-ink-tertiary">For levels {g.level_min}–{g.level_max}. Members sign up for sessions and share a group chat.</p>
              </>
            )}
            {g.my_role === 'pending' && <p className="font-bold">Request sent. An organizer will review it.</p>}
            {member && (
              <>
                <Link to={`/app/messages/group/${g.id}/`} className="button">Group chat</Link>
                <div>
                  <p className="eyebrow">Group number</p>
                  <p className="mt-1 font-mono text-2xl font-black tracking-[0.3em]">{g.invite_code}</p>
                </div>
                <Button variant="quiet" onClick={copyInvite}>Copy invite</Button>
                {g.my_role !== 'owner' && (confirm === 'leave' ? (
                  <Button variant="danger" busy={busy === 'leave'} onClick={() => act('leave', 'leave_group', { p_group: g.id }, 'You left the group')}>
                    Yes, leave group
                  </Button>
                ) : (
                  <Button variant="quiet" onClick={() => setConfirm('leave')}>Leave group</Button>
                ))}
              </>
            )}
          </section>

          {organizer && g.pending && g.pending.length > 0 && (
            <section aria-labelledby="requests" className="tile grid gap-3 bg-surface p-5">
              <h2 id="requests" className="eyebrow">Join requests</h2>
              {g.pending.map((p) => (
                <div key={p.id} className="flex flex-wrap items-center gap-2">
                  <Link to={`/app/players/${p.id}/`} className="link min-w-0 flex-1 truncate">{p.nickname} · {tier(p.rating).label}</Link>
                  <Button busy={busy === `ok-${p.id}`} onClick={() => act(`ok-${p.id}`, 'respond_join_request', { p_group: g.id, p_user: p.id, p_accept: true }, 'Approved')}>Approve</Button>
                  <Button variant="quiet" disabled={Boolean(busy)} onClick={() => act(`no-${p.id}`, 'respond_join_request', { p_group: g.id, p_user: p.id, p_accept: false })}>Decline</Button>
                </div>
              ))}
            </section>
          )}

          {g.members && (
            <section aria-labelledby="members" className="tile grid gap-2 bg-surface p-5">
              <h2 id="members" className="eyebrow">Members</h2>
              <ul className="grid gap-2">
                {g.members.map((m) => (
                  <li key={m.id} className="flex items-center gap-2">
                    <Link to={`/app/players/${m.id}/`} className="min-w-0 flex-1 truncate font-bold hover:underline">
                      {m.nickname} <span className="font-semibold text-ink-tertiary">· {tier(m.rating).label}{m.role !== 'member' ? ` · ${m.role}` : ''}</span>
                    </Link>
                    {organizer && m.role === 'member' && (confirm === `remove-${m.id}` ? (
                      <Button variant="danger" className="min-h-9! px-3! text-sm" busy={busy === `remove-${m.id}`}
                              onClick={() => act(`remove-${m.id}`, 'remove_member', { p_group: g.id, p_user: m.id }, 'Removed')}>Remove</Button>
                    ) : (
                      <button onClick={() => setConfirm(`remove-${m.id}`)} className="link text-sm">Remove</button>
                    ))}
                  </li>
                ))}
              </ul>
            </section>
          )}
        </aside>
      </div>
    </div>
  );
}

function Session({ session: s, tz, member, organizer, busy, confirm, setConfirm, act }: {
  session: GroupSession;
  tz: string | null;
  member: boolean;
  organizer: boolean;
  busy?: string;
  /** 正在二次确认的操作（同一时间只有一个） */
  confirm?: string;
  setConfirm: (key?: string) => void;
  act: (name: string, fn: string, args: Record<string, unknown>, done?: string) => Promise<unknown>;
}) {
  const going = s.my_status === 'confirmed';
  const waiting = s.my_status?.startsWith('waitlisted');
  const started = new Date(s.starts_at).getTime() <= Date.now();
  const late = new Date(s.starts_at).getTime() - Date.now() < 2 * 3600000;
  const full = s.confirmed >= s.capacity;

  async function signUp() {
    const status = await act(`sign-${s.id}`, 'sign_up_session', { p_session: s.id });
    if (status === 'confirmed') toast('You’re going!');
    else if (status === 'waitlisted') toast('You’re on the waitlist. We’ll tell you if a spot opens.');
  }

  return (
    <article className={`tile grid gap-3 p-4 sm:p-5 ${s.cancelled ? 'bg-surface-muted' : 'bg-surface'}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="font-black">{day(s.starts_at, tz)} · {hours(s.starts_at, s.ends_at, tz)}</h3>
          <p className="text-sm text-ink-secondary tabular-nums">
            {s.cancelled ? 'Cancelled by the organizer' : `${s.confirmed} of ${s.capacity} going${s.waitlist ? ` · ${s.waitlist} waiting` : ''}`}
          </p>
        </div>
        {going && <span className="chip bg-mint">Going</span>}
        {waiting && <span className="chip bg-peach">Waitlist #{s.my_status!.split(':')[1]}</span>}
      </div>

      {member && s.players && s.players.length > 0 && (
        <details>
          <summary className="link cursor-pointer text-sm">Who’s going</summary>
          <p className="mt-2 text-sm">
            {s.players.map((p, i) => (
              <span key={p.id}>{i > 0 && ', '}<Link to={`/app/players/${p.id}/`} className="hover:underline">{p.nickname}</Link>{p.waitlisted && ' (waiting)'}</span>
            ))}
          </p>
        </details>
      )}

      {member && !s.cancelled && !started && (
        <div className="flex flex-wrap gap-2">
          {going || waiting ? (
            confirm === `out-${s.id}` ? (
              <Button variant="danger" busy={busy === `out-${s.id}`} onClick={() => act(`out-${s.id}`, 'cancel_signup', { p_session: s.id }, 'Signed out')}>
                {going && late ? 'Sign out (counts as late)' : 'Yes, sign out'}
              </Button>
            ) : (
              <Button variant="quiet" onClick={() => setConfirm(`out-${s.id}`)}>Can’t make it</Button>
            )
          ) : (
            <Button busy={busy === `sign-${s.id}`} onClick={signUp}>{full ? 'Join waitlist' : 'Sign up'}</Button>
          )}
          {organizer && (confirm === `cancel-${s.id}` ? (
            <Button variant="danger" busy={busy === `cancel-${s.id}`} onClick={() => act(`cancel-${s.id}`, 'cancel_session', { p_session: s.id }, 'Session cancelled')}>
              Yes, cancel for everyone
            </Button>
          ) : (
            <button onClick={() => setConfirm(`cancel-${s.id}`)} className="link self-center text-sm">Cancel session</button>
          ))}
        </div>
      )}
    </article>
  );
}
