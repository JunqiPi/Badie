import { useState } from 'react';
import { activityText, scheduleText } from './Groups';
import { t } from './i18n';
import { Icon } from './icons';
import { Avatar, Divider, Empty, IconButton, IconTile, LevelBadge, ScreenHeader, SectionTitle, Tag } from './kit';
import { Link } from './router';
import { problem, supabase, useLive, type GroupDetail, type GroupSession } from './supabase';
import { dayName, hours } from './time';
import { Button, Skeleton, toast } from './ui';

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
    return <Empty icon="group" tint="lavender" title={t('Group not found')} action={{ label: t('Groups'), to: '/groups/' }}>{t('It may have been removed.')}</Empty>;
  }
  const member = g.my_role === 'owner' || g.my_role === 'organizer' || g.my_role === 'member';
  const organizer = g.my_role === 'owner' || g.my_role === 'organizer';
  const tz = g.venue.tz;

  async function join() {
    const status = await act('join', 'join_group', { p_group: g!.id });
    if (status === 'pending') toast(t('Request sent. An organizer will review it.'));
    else if (status) toast(t('Welcome to {name}!', { name: g!.name }));
  }

  async function copyInvite() {
    const text = t('Join “{name}” on Badie: {times} at {court}. Level {min}–{max}. Open {link} and enter group number {code}.', {
      name: g!.name, times: g!.schedules.map(scheduleText).join(', '), court: g!.venue.name, min: g!.level_min, max: g!.level_max,
      link: `${location.origin}/join/`, code: g!.invite_code ?? '',
    });
    try {
      await navigator.clipboard.writeText(text);
      toast(t('Invite copied. Paste it into your chat.'));
    } catch {
      toast(t('Group number: {code}', { code: g!.invite_code ?? '' }));
    }
  }

  return (
    <div className="grid gap-6">
      <ScreenHeader title={g.name} back="/groups/">
        {member && <IconButton icon="share" label={t('Copy invite')} onClick={copyInvite} />}
      </ScreenHeader>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start lg:gap-8">
        <div className="grid min-w-0 gap-6">
          <section aria-label={g.venue.name} className="sticker grid gap-3 p-5">
            <div className="flex items-start gap-3">
              <IconTile icon="pin" tint="sky" size="lg" />
              <div className="min-w-0">
                <h2 className="text-headline">{g.venue.name}</h2>
                <p className="text-footnote text-ink-secondary">{g.venue.city}</p>
              </div>
            </div>
            {g.summary && <p className="text-subhead">{g.summary}</p>}
            <ul className="flex flex-wrap gap-1.5">
              <li><Tag icon="level" tint="lime">{t('Lv.{min}–{max}', { min: g.level_min, max: g.level_max })}</Tag></li>
              <li><Tag icon={g.join_policy === 'approval' ? 'lock' : 'userPlus'}>{g.join_policy === 'approval' ? t('Organizer approves') : t('Join directly')}</Tag></li>
              {g.schedules.map((sc) => <li key={`${sc.weekday}-${sc.start}`}><Tag icon="calendar" tint="butter">{scheduleText(sc)}{sc.fee ? ` · ${sc.fee}` : ''}</Tag></li>)}
              {member && g.invite_code && <li><Tag icon="hash">{t('Group ID {code}', { code: g.invite_code })}</Tag></li>}
            </ul>
            <p className="flex items-center gap-1.5 text-footnote text-ink-secondary"><Icon name="bolt" className="size-3.5" />{activityText(g.activity)}</p>
            {member && <Link to={`/messages/group/${g.id}/`} className="button button-quiet w-full"><Icon name="chats" className="size-5" />{t('Group chat')}</Link>}
          </section>

          <section aria-labelledby="sessions" className="grid gap-2">
            <SectionTitle id="sessions" title={t('Upcoming sessions')} detail={t('Leaving within 2 hours of start counts as a late cancellation')} />
            {g.sessions.length === 0 && <p className="text-footnote text-ink-secondary">{t('No sessions scheduled.')}</p>}
            {g.sessions.map((s) => (
              <Session key={s.id} session={s} tz={tz} member={member} organizer={organizer} busy={busy}
                       confirm={confirm} setConfirm={setConfirm} act={act} />
            ))}
          </section>

          {g.members && (
            <section aria-labelledby="members" className="grid gap-2">
              <SectionTitle id="members" title={t('Organizers & regulars')} detail={String(g.members.length)} />
              <ul className="sticker grid p-2">
                {g.members.map((m, i) => (
                  <li key={m.id}>
                    {i > 0 && <div className="mx-2"><Divider /></div>}
                    <div className="flex items-center gap-3 p-2">
                      <Link to={`/players/${m.id}/`} className="press flex min-w-0 flex-1 items-center gap-3">
                        <Avatar id={m.id} name={m.nickname} size={40} />
                        <span className="grid min-w-0 justify-items-start gap-0.5">
                          <span className="max-w-full truncate font-bold">{m.nickname}</span>
                          <span className="flex gap-1"><LevelBadge rating={m.rating} named={false} compact />{m.role !== 'member' && <Tag tint="butter">{t(roles[m.role])}</Tag>}</span>
                        </span>
                      </Link>
                      {organizer && m.role === 'member' && (confirm === `remove-${m.id}` ? (
                        <Button variant="danger" className="button-sm" busy={busy === `remove-${m.id}`}
                                onClick={() => act(`remove-${m.id}`, 'remove_member', { p_group: g.id, p_user: m.id }, t('Removed'))}>{t('Remove')}</Button>
                      ) : (
                        <button onClick={() => setConfirm(`remove-${m.id}`)} className="link text-footnote">{t('Remove')}</button>
                      ))}
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </div>

        {/* 还没加入时，“加入”在手机上放到最前面 */}
        <aside className={`grid gap-4 lg:sticky lg:top-24 ${member ? '' : 'order-first lg:order-none'}`} aria-label={t('Membership')}>
          <section className={`sticker grid gap-3 p-5 ${member ? '' : 'bg-lavender text-on-accent'}`}>
            {!g.my_role && (
              <>
                <p className="text-headline">{t('For levels {min}–{max}. Members sign up for sessions and share a group chat.', { min: g.level_min, max: g.level_max })}</p>
                <Button className="button-lg button-inverse" busy={busy === 'join'} onClick={join}>{g.join_policy === 'approval' ? t('Ask to join') : t('Join group')}</Button>
              </>
            )}
            {g.my_role === 'pending' && <p className="font-bold">{t('Request sent. An organizer will review it.')}</p>}
            {member && (
              <>
                <div>
                  <p className="text-footnote font-bold text-ink-secondary">{t('Group number')}</p>
                  <p className="mt-1 font-mono text-[1.75rem] font-black tracking-[0.3em]">{g.invite_code}</p>
                </div>
                <Button onClick={copyInvite}><Icon name="copy" className="size-4" />{t('Copy invite')}</Button>
                {g.my_role !== 'owner' && (confirm === 'leave' ? (
                  <Button variant="danger" busy={busy === 'leave'} onClick={() => act('leave', 'leave_group', { p_group: g.id }, t('You left the group'))}>
                    {t('Yes, leave group')}
                  </Button>
                ) : (
                  <button type="button" onClick={() => setConfirm('leave')} className="min-h-11 text-footnote font-bold text-danger hover:underline">{t('Leave group')}</button>
                ))}
              </>
            )}
          </section>

          {organizer && g.pending && g.pending.length > 0 && (
            <section aria-labelledby="requests" className="sticker grid gap-3 bg-butter p-5 text-on-accent">
              <h2 id="requests" className="text-headline">{t('Join requests')}</h2>
              {g.pending.map((p) => (
                <div key={p.id} className="flex flex-wrap items-center gap-2">
                  <Link to={`/players/${p.id}/`} className="flex min-w-0 flex-1 items-center gap-2 font-bold hover:underline">
                    <Avatar id={p.id} name={p.nickname} size={32} />
                    <span className="truncate">{p.nickname}</span>
                    <LevelBadge rating={p.rating} named={false} compact />
                  </Link>
                  <Button className="button-sm" busy={busy === `ok-${p.id}`} onClick={() => act(`ok-${p.id}`, 'respond_join_request', { p_group: g.id, p_user: p.id, p_accept: true }, t('Approved'))}>{t('Approve')}</Button>
                  <Button className="button-sm" variant="quiet" disabled={Boolean(busy)} onClick={() => act(`no-${p.id}`, 'respond_join_request', { p_group: g.id, p_user: p.id, p_accept: false })}>{t('Decline')}</Button>
                </div>
              ))}
            </section>
          )}
        </aside>
      </div>
    </div>
  );
}

const roles: Record<string, string> = { owner: 'Owner', organizer: 'Organizer' };

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
    if (status === 'confirmed') toast(t('You’re going!'));
    else if (status === 'waitlisted') toast(t('You’re on the waitlist. We’ll tell you if a spot opens.'));
  }

  return (
    <article className={`sticker grid gap-3 p-4 ${s.cancelled ? 'bg-surface-muted' : going ? 'bg-lime/45' : waiting ? 'bg-butter/50' : ''}`}>
      <div className="flex items-start gap-3">
        <div className="grid min-w-0 flex-1 gap-1">
          <h3 className="text-headline">{dayName(s.starts_at, tz)} · {hours(s.starts_at, s.ends_at, tz)}</h3>
          {s.cancelled ? (
            <p className="text-footnote font-bold text-ink-secondary">{t('Cancelled by the organizer')}</p>
          ) : (
            <>
              <p className="text-footnote font-bold text-ink-secondary tabular-nums">
                {[t('{n}/{total} signed up', { n: s.confirmed, total: s.capacity }), s.waitlist > 0 && t('{n} waiting', { n: s.waitlist })].filter(Boolean).join(' · ')}
              </p>
              <span className="block h-2.5 max-w-60 overflow-hidden rounded-full border-2 border-stroke bg-surface" aria-hidden="true">
                <span className="block h-full bg-lime" style={{ width: `${Math.min(100, (s.confirmed / s.capacity) * 100)}%` }} />
              </span>
            </>
          )}
        </div>
        {going && <Tag icon="check" tint="surface">{t('Signed up')}</Tag>}
        {waiting && <Tag tint="peach">{t('Waitlist #{n}', { n: s.my_status!.split(':')[1] })}</Tag>}
      </div>

      {member && s.players && s.players.length > 0 && (
        <details>
          <summary className="cursor-pointer text-footnote font-bold underline underline-offset-4">{t('Who’s going')}</summary>
          <p className="mt-2 text-footnote">
            {s.players.map((p, i) => (
              <span key={p.id}>{i > 0 && ', '}<Link to={`/players/${p.id}/`} className="hover:underline">{p.nickname}</Link>{p.waitlisted && ` ${t('(waiting)')}`}</span>
            ))}
          </p>
        </details>
      )}

      {member && !s.cancelled && !started && (
        <div className="flex flex-wrap gap-2">
          {going || waiting ? (
            confirm === `out-${s.id}` ? (
              <Button variant="danger" busy={busy === `out-${s.id}`} onClick={() => act(`out-${s.id}`, 'cancel_signup', { p_session: s.id }, t('Signed out'))}>
                {going && late ? t('Sign out (counts as late)') : t('Yes, sign out')}
              </Button>
            ) : (
              <Button className="button-sm" variant="quiet" onClick={() => setConfirm(`out-${s.id}`)}>{t('Can’t make it')}</Button>
            )
          ) : (
            <Button className="button-sm" busy={busy === `sign-${s.id}`} onClick={signUp}>{full ? t('Join waitlist') : t('Sign up')}</Button>
          )}
          {organizer && (confirm === `cancel-${s.id}` ? (
            <Button variant="danger" busy={busy === `cancel-${s.id}`} onClick={() => act(`cancel-${s.id}`, 'cancel_session', { p_session: s.id }, t('Session cancelled'))}>
              {t('Yes, cancel for everyone')}
            </Button>
          ) : (
            <button onClick={() => setConfirm(`cancel-${s.id}`)} className="link self-center text-footnote">{t('Cancel session')}</button>
          ))}
        </div>
      )}
    </article>
  );
}
