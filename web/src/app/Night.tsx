// 当晚页（/night/<场次>/）：组织者和当晚的帮手用。顶部分段 排场 | 比赛 | 收款（帮手没有收款），三样共用同一份到场名单。
// 数据都在服务器上（night_state，10 秒刷新），每个操作完都重新拿一次；两台手机同时改时服务器以先到的为准
import { useState, type ReactNode, type SubmitEvent } from 'react';
import {
  clubProblem, money, QrSheet, sides, Stepper, Switch, teamName, UndoBar, Updated, useNow, useUpdatedAt,
  type Attendance, type NightPay, type NightPerson, type NightState,
} from './club';
import { t } from './i18n';
import { Icon } from './icons';
import { Divider, Empty, IconButton, Notice, ScreenHeader, Segmented, Tag } from './kit';
import { MatchLive } from './Match';
import { Sheet } from './Nearby';
import { Link, navigate } from './router';
import { supabase, useLive } from './supabase';
import { hours, timeOf } from './time';
import { Button, Field, Skeleton, toast } from './ui';

type Tab = 'courts' | 'match' | 'pay';
type Act = (fn: string, args: Record<string, unknown>, done?: string) => Promise<unknown>;

export function NightPage({ id }: { id: string }) {
  const { data: n, refresh } = useLive<NightState | null>('night_state', { args: { p_session: id }, every: 10_000 });
  const updated = useUpdatedAt(n);
  const [tab, setTab] = useState<Tab>(() => {
    const asked = new URLSearchParams(location.search).get('tab');
    return asked === 'pay' || asked === 'match' ? asked : 'courts';
  });
  const [settings, setSettings] = useState(false);

  async function act(fn: string, args: Record<string, unknown>, done?: string) {
    const { data, error } = await supabase!.rpc(fn, args);
    if (error) toast(clubProblem(error), 'error');
    else if (done) toast(done);
    await refresh();
    return error ? undefined : (data ?? true);
  }

  if (n === undefined) return <Skeleton className="mx-auto h-96 max-w-2xl" />;
  if (n === null) {
    return (
      <Empty icon="lock" tint="butter" title={t('Only for the organizer and helpers')} action={{ label: t('Groups'), to: '/groups/' }}>
        {t('Players can see the courts from the group page.')}
      </Empty>
    );
  }

  const organizer = n.role === 'organizer';
  // 帮手没有收款
  const current: Tab = !organizer && tab === 'pay' ? 'courts' : tab;
  const here = n.people.filter((p) => p.status === 'here').length;
  const options: { value: Tab; label: string }[] = [
    { value: 'courts', label: t('Rotation') },
    { value: 'match', label: t('Match') },
    ...(organizer ? [{ value: 'pay' as const, label: t('Payments') }] : []),
  ];

  return (
    <div className="mx-auto grid w-full max-w-2xl gap-4 pb-24">
      <div className="grid gap-1">
        <ScreenHeader title={t('Club night')} back={`/groups/${n.group_id}/`}>
          {n.open && <IconButton icon="gear" label={t('Court settings')} onClick={() => setSettings(true)} />}
        </ScreenHeader>
        <p className="text-center text-footnote font-bold text-ink-secondary lg:text-left">
          {n.group} · {hours(n.starts_at, n.ends_at, n.tz)} · {t('{n} here', { n: here })}
        </p>
      </div>
      <Segmented label={t('Club night')} options={options} value={current} onChange={(value) => {
        setTab(value);
        history.replaceState(null, '', `/night/${id}/${value === 'courts' ? '' : `?tab=${value}`}`);
      }} />

      {current === 'courts' && <Rotation n={n} act={act} onSettings={() => setSettings(true)} />}
      {current === 'match' && <NightMatch n={n} act={act} />}
      {current === 'pay' && <Payments n={n} />}
      {current === 'courts' && <Updated at={updated} />}

      {n.open && <SettingsSheet open={settings} onClose={() => setSettings(false)} n={n} act={act} />}
      {current === 'courts' && <UndoBar until={n.undo_until} onUndo={() => act('night_undo', { p_session: n.session_id })} />}
    </div>
  );
}

// MARK: 排场

const statusText = (status: Attendance) => ({ absent: t('Not here yet'), here: t('Here'), resting: t('Resting'), left: t('Gone') })[status];
const nextStatus: Record<Attendance, Attendance> = { absent: 'here', here: 'resting', resting: 'left', left: 'absent' };
const mark = (n: NightState, act: Act, ids: string[] | null, status: Attendance) =>
  act('night_mark', { p_session: n.session_id, p_signups: ids, p_status: status === 'absent' ? null : status });

function Rotation({ n, act, onSettings }: { n: NightState; act: Act; onSettings: () => void }) {
  const [adding, setAdding] = useState(false);
  const [qr, setQr] = useState(false);
  const [person, setPerson] = useState<NightPerson>();
  const [swap, setSwap] = useState<{ game: number; out: NightPerson }>();
  const [busy, setBusy] = useState<string>();
  const now = useNow(30_000);
  const names = new Map(n.people.map((p) => [p.id, p.name]));
  const byId = new Map(n.people.map((p) => [p.id, p]));
  // 按排人的顺序（queue）
  const waiting = n.people.filter((p) => p.status === 'here' && p.on_court === null)
    .sort((a, b) => (a.queue ?? Infinity) - (b.queue ?? Infinity));
  const resting = n.people.filter((p) => p.status === 'resting');

  async function run(key: string, fn: string, args: Record<string, unknown>) {
    setBusy(key);
    await act(fn, args);
    setBusy(undefined);
  }

  if (!n.open) return <Notice icon="clock" tint="butter">{t('This only works on the day of the session.')}</Notice>;

  const tools = (
    <div className="grid grid-cols-2 gap-3">
      {n.started && n.board_code
        ? <Button variant="quiet" className="button-lg" onClick={() => setQr(true)}><Icon name="share" className="size-5" />{t('QR code')}</Button>
        : <span />}
      <Button variant="quiet" className="button-lg" onClick={() => setAdding(true)}><Icon name="userPlus" className="size-5" />{t('Add people')}</Button>
    </div>
  );
  const sheets = (
    <>
      <AddSheet open={adding} onClose={() => setAdding(false)} n={n} act={act} />
      {n.board_code && <QrSheet open={qr} onClose={() => setQr(false)} code={n.board_code} title={t('Courts board')} />}
      <PersonSheet person={person} onClose={() => setPerson(undefined)} n={n} act={act} />
      <SwapSheet swap={swap} onClose={() => setSwap(undefined)} waiting={waiting} act={act} />
    </>
  );

  // 开始前：设置、点名、开始
  if (!n.started) {
    return (
      <>
        <button type="button" onClick={onSettings} className="sticker lift flex min-h-14 items-center gap-3 px-4 py-3 text-left">
          <Icon name="court" className="size-5" />
          <span className="flex-1 font-bold">
            {[t('{n} court|{n} courts', { n: n.courts }), n.doubles ? t('Doubles') : t('Singles'), n.balance && t('Teams balanced by level')].filter(Boolean).join(' · ')}
          </span>
          <span className="text-footnote font-bold text-ink-secondary">{t('Change')}</span>
        </button>
        <section aria-labelledby="roster" className="grid gap-3">
          <div className="flex items-center gap-2">
            <h2 id="roster" className="flex-1 text-title3">{t('Who’s here')}</h2>
            <Button variant="quiet" className="button-sm" busy={busy === 'all'} onClick={() => run('all', 'night_mark', { p_session: n.session_id, p_signups: null, p_status: 'here' })}>
              {t('Everyone’s here')}
            </Button>
          </div>
          <p className="text-footnote text-ink-secondary">{t('Tap a name to switch between here, resting, gone and not here yet.')}</p>
          <ul className="flex flex-wrap gap-2">
            {n.people.map((p) => (
              <li key={p.id}>
                <button type="button" aria-pressed={p.status === 'here'} disabled={busy === p.id}
                        aria-label={`${p.name}: ${statusText(p.status)}`}
                        onClick={() => run(p.id, 'night_mark', { p_session: n.session_id, p_signups: [p.id], p_status: nextStatus[p.status] === 'absent' ? null : nextStatus[p.status] })}
                        className={`toggle min-h-11 ${p.status === 'resting' ? 'bg-butter' : p.status === 'left' ? 'text-ink-tertiary line-through' : ''}`}>
                  {p.name}
                  {p.status !== 'here' && p.status !== 'absent' && <span className="text-caption no-underline">{statusText(p.status)}</span>}
                  {p.waitlisted && p.status === 'absent' && <span className="text-caption text-ink-secondary">{t('Waitlist')}</span>}
                </button>
              </li>
            ))}
          </ul>
        </section>
        {tools}
        <Button className="button-lg" busy={busy === 'start'} onClick={() => run('start', 'night_start', { p_session: n.session_id })}>{t('Start')}</Button>
        {sheets}
      </>
    );
  }

  // 开始后：每片场地一张卡（减场地时还在打的那片也显示，打完再收）
  const courts = [...new Set([...Array.from({ length: n.courts }, (_, i) => i + 1), ...n.games.map((g) => g.court)])].sort((a, b) => a - b);
  return (
    <>
      {n.match_live && (
        <Notice icon="trophy" tint="sky">{t('A match is using the courts. The rotation picks up again when it ends.')}</Notice>
      )}
      {!n.match_live && (
        <div className="grid gap-3">
          {courts.map((court) => {
            const game = n.games.find((g) => g.court === court);
            return (
              <article key={court} className="sticker flex items-center gap-3 py-3 pr-3 pl-4" aria-label={t('Court {n}', { n: court })}>
                <div className="grid min-w-0 flex-1 gap-1.5">
                  <div className="flex items-center gap-2">
                    <span className="chip bg-sky text-footnote font-black">{t('Court {n}', { n: court })}</span>
                    {game && <span className="text-footnote font-bold text-ink-secondary tabular-nums">{t('{n} min', { n: Math.max(0, Math.floor((now - new Date(game.started_at).getTime()) / 60_000)) })}</span>}
                  </div>
                  {game ? sides(game.players).map((team, i) => (
                    <p key={i} className="flex flex-wrap gap-x-1 text-headline">
                      {team.map((pid, j) => (
                        <span key={pid}>
                          {j > 0 && <span aria-hidden="true">· </span>}
                          <button type="button" className="press underline-offset-4 hover:underline" aria-label={t('Swap {name} out', { name: names.get(pid) ?? '' })}
                                  onClick={() => byId.get(pid) && setSwap({ game: game.id, out: byId.get(pid)! })}>
                            {names.get(pid) ?? '?'}
                          </button>
                        </span>
                      ))}
                    </p>
                  )) : <p className="text-headline text-ink-tertiary">{t('Waiting for players')}</p>}
                </div>
                {game && (
                  <Button className="button-lg h-[76px] w-24 shrink-0 rounded-[18px]" busy={busy === `done-${game.id}`}
                          onClick={() => run(`done-${game.id}`, 'night_finish', { p_game: game.id })}>
                    {t('Finish')}
                  </Button>
                )}
              </article>
            );
          })}
        </div>
      )}

      {!n.match_live && n.next.length > 0 && (
        <section aria-labelledby="up-next" className="tile grid gap-1.5 bg-surface px-4 py-3">
          <h2 id="up-next" className="text-footnote font-bold text-ink-secondary">{t('Up next')}</h2>
          {n.next.map((group, i) => {
            const [a, b] = sides(group);
            return (
              <p key={i} className="flex flex-wrap items-center gap-x-2 text-headline">
                <span>{teamName(a, names)}</span><span className="text-caption text-ink-secondary">{t('vs')}</span><span>{teamName(b, names)}</span>
              </p>
            );
          })}
        </section>
      )}

      <section aria-labelledby="waiting" className="grid gap-2">
        <h2 id="waiting" className="text-footnote font-bold text-ink-secondary">{t('Waiting · games tonight')}</h2>
        {waiting.length === 0 && <p className="text-footnote text-ink-secondary">{t('No one is waiting.')}</p>}
        <ul className="flex flex-wrap gap-2">
          {[...waiting, ...resting].map((p) => (
            <li key={p.id}>
              <button type="button" onClick={() => setPerson(p)} aria-label={`${p.name}, ${t('{n} game tonight|{n} games tonight', { n: p.games })}`}
                      className={`press flex h-10 items-center gap-2 rounded-full border-[1.5px] border-stroke pr-1 pl-3 ${p.status === 'resting' ? 'bg-surface-muted text-ink-secondary' : 'bg-surface'}`}>
                <span className="font-black">{p.name}</span>
                {p.next_up && <Tag tint="lime">{t('Next game')}</Tag>}
                {p.status === 'resting' && <span className="text-caption font-bold">{t('Resting')}</span>}
                <span className="grid size-7 place-items-center rounded-full bg-surface-muted text-footnote font-black tabular-nums">{p.games}</span>
              </button>
            </li>
          ))}
        </ul>
      </section>
      {tools}
      {sheets}
    </>
  );
}

/** 点名字：改到场状态，或者放到下一场、跳过 */
function PersonSheet({ person: p, onClose, n, act }: { person?: NightPerson; onClose: () => void; n: NightState; act: Act }) {
  const [busy, setBusy] = useState<string>();
  async function run(key: string, call: () => Promise<unknown>) {
    setBusy(key);
    const ok = await call();
    setBusy(undefined);
    if (ok) onClose();
  }
  return (
    <Sheet open={Boolean(p)} onClose={onClose} labelledBy="person-title">
      {p && (
        <>
          <div>
            <h2 id="person-title" className="text-title3">{p.name}</h2>
            <p className="text-footnote font-bold text-ink-secondary">{t('{n} game tonight|{n} games tonight', { n: p.games })}</p>
          </div>
          <div className="grid grid-cols-2 gap-2">
            {(['here', 'resting', 'left', 'absent'] as const).map((status) => (
              <button key={status} type="button" aria-pressed={p.status === status} className="toggle min-h-12" disabled={Boolean(busy)}
                      onClick={() => run(status, () => mark(n, act, [p.id], status))}>
                {statusText(status)}
              </button>
            ))}
          </div>
          {p.status === 'here' && p.on_court === null && (
            <div className="grid grid-cols-2 gap-2">
              <Button variant="quiet" busy={busy === 'next'} onClick={() => run('next', () => act('night_bump', { p_signup: p.id, p_next: true }))}>{t('Put in next game')}</Button>
              <Button variant="quiet" busy={busy === 'skip'} onClick={() => run('skip', () => act('night_bump', { p_signup: p.id, p_next: false }))}>{t('Skip a turn')}</Button>
            </div>
          )}
        </>
      )}
    </Sheet>
  );
}

/** 点场上的名字：从等着的人里选一个换上 */
function SwapSheet({ swap, onClose, waiting, act }: { swap?: { game: number; out: NightPerson }; onClose: () => void; waiting: NightPerson[]; act: Act }) {
  const [busy, setBusy] = useState<string>();
  return (
    <Sheet open={Boolean(swap)} onClose={onClose} labelledBy="swap-title">
      {swap && (
        <>
          <h2 id="swap-title" className="text-title3">{t('Swap {name} out', { name: swap.out.name })}</h2>
          {waiting.length === 0 ? <p className="text-subhead text-ink-secondary">{t('No one is waiting.')}</p> : (
            <ul className="grid gap-2">
              {waiting.map((p) => (
                <li key={p.id}>
                  <Button variant="quiet" className="w-full justify-between" busy={busy === p.id} onClick={async () => {
                    setBusy(p.id);
                    const ok = await act('night_swap', { p_game: swap.game, p_out: swap.out.id, p_in: p.id });
                    setBusy(undefined);
                    if (ok) onClose();
                  }}>
                    <span>{p.name}</span>
                    <span className="text-footnote text-ink-secondary">{t('{n} game tonight|{n} games tonight', { n: p.games })}</span>
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </Sheet>
  );
}

/** 加人：报了名还没到的、候补的排在前面，点一下就标到了；名单上没有的输名字 */
function AddSheet({ open, onClose, n, act }: { open: boolean; onClose: () => void; n: NightState; act: Act }) {
  const [name, setName] = useState('');
  const [busy, setBusy] = useState<string>();
  const missing = n.people.filter((p) => p.status !== 'here').sort((a, b) => Number(b.waitlisted) - Number(a.waitlisted));
  const clean = name.trim().replace(/\s+/g, ' ');
  // 同一晚名字不能重复：服务器会加数字（“Tony 2”），这里先说一句
  const same = clean && n.people.some((p) => p.name.toLowerCase().replace(/ \d+$/, '') === clean.toLowerCase());

  async function add(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!clean) return;
    setBusy('add');
    const ok = await act('night_add', { p_session: n.session_id, p_name: clean }, t('{name} added', { name: clean }));
    setBusy(undefined);
    if (ok) setName('');
  }

  return (
    <Sheet open={open} onClose={onClose} labelledBy="add-title">
      <h2 id="add-title" className="text-title3">{t('Add people')}</h2>
      {missing.length > 0 && (
        <ul className="flex flex-wrap gap-2" aria-label={t('Signed up, not here yet')}>
          {missing.map((p) => (
            <li key={p.id}>
              <button type="button" className="toggle min-h-11" disabled={busy === p.id} onClick={async () => {
                setBusy(p.id);
                await mark(n, act, [p.id], 'here');
                setBusy(undefined);
              }}>
                <Icon name="plus" className="size-3.5" />{p.name}
                {p.waitlisted && <span className="text-caption text-ink-secondary">{t('Waitlist')}</span>}
                {p.status !== 'absent' && <span className="text-caption text-ink-secondary">{statusText(p.status)}</span>}
              </button>
            </li>
          ))}
        </ul>
      )}
      <form onSubmit={add} className="grid gap-2">
        <Field label={t('Name')} hint={same ? t('Someone with this name is already here. The new one shows with a number, like “{name} 2”.', { name: clean }) : undefined}>
          {(props) => <input {...props} className="field" value={name} maxLength={20} autoComplete="off" onChange={(e) => setName(e.target.value)} />}
        </Field>
        <Button type="submit" variant="quiet" busy={busy === 'add'} disabled={!clean}>{t('Add')}</Button>
      </form>
    </Sheet>
  );
}

/** 右上角设置：场地数、单双打、按实力分队、帮手（只有组织者） */
function SettingsSheet({ open, onClose, n, act }: { open: boolean; onClose: () => void; n: NightState; act: Act }) {
  const [draft, setDraft] = useState<{ courts: number; doubles: boolean; balance: boolean; helpers: string[] }>();
  const [busy, setBusy] = useState(false);
  const current = { courts: n.courts, doubles: n.doubles, balance: n.balance, helpers: n.helpers.map((h) => h.id) };
  const d = draft ?? current;
  // 帮手只能从到场的注册用户里选
  const candidates = n.people.filter((p) => p.user_id && p.status === 'here');
  const close = () => {
    setDraft(undefined);
    onClose();
  };

  async function save() {
    setBusy(true);
    let ok = await act('night_settings', { p_session: n.session_id, p_courts: d.courts, p_doubles: d.doubles, p_balance: d.balance });
    if (ok && n.role === 'organizer' && [...d.helpers].sort().join() !== [...current.helpers].sort().join()) {
      ok = await act('night_helpers', { p_session: n.session_id, p_users: d.helpers });
    }
    setBusy(false);
    if (ok) {
      toast(t('Saved'));
      close();
    }
  }

  return (
    <Sheet open={open} onClose={close} labelledBy="settings-title">
      <h2 id="settings-title" className="text-title3">{t('Court settings')}</h2>
      <div className="sticker grid px-4">
        <Stepper label={t('Number of courts')} value={d.courts} min={1} max={12} text={String(d.courts)} onChange={(courts) => setDraft({ ...d, courts })} />
        <Divider />
        <div className="py-3">
          <Segmented label={t('Singles or doubles')} value={d.doubles ? 'doubles' : 'singles'} onChange={(v) => setDraft({ ...d, doubles: v === 'doubles' })}
                     options={[{ value: 'doubles', label: t('Doubles') }, { value: 'singles', label: t('Singles') }]} />
        </div>
        <Divider />
        <Switch checked={d.balance} onChange={(balance) => setDraft({ ...d, balance })} title={t('Balance teams by level')}
                text={t('Guests without a level count as the middle of the room.')} />
      </div>
      {n.role === 'organizer' && (
        <section aria-labelledby="helpers-title" className="grid gap-2">
          <h3 id="helpers-title" className="text-headline">{t('Helpers')}</h3>
          <p className="text-footnote text-ink-secondary">{t('Up to 3 players who are here. They can run the courts and enter scores tonight.')}</p>
          {candidates.length === 0 ? <p className="text-footnote font-bold">{t('Mark players as here first.')}</p> : (
            <ul className="flex flex-wrap gap-2">
              {candidates.map((p) => {
                const on = d.helpers.includes(p.user_id!);
                return (
                  <li key={p.id}>
                    <button type="button" className="toggle" aria-pressed={on} disabled={!on && d.helpers.length >= 3}
                            onClick={() => setDraft({ ...d, helpers: on ? d.helpers.filter((x) => x !== p.user_id) : [...d.helpers, p.user_id!] })}>
                      {p.name}
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </section>
      )}
      <Button busy={busy} onClick={save}>{t('Save')}</Button>
    </Sheet>
  );
}

// MARK: 比赛

function NightMatch({ n, act }: { n: NightState; act: Act }) {
  const [busy, setBusy] = useState(false);
  if (n.match_id && n.match_live) return <MatchLive id={n.match_id} embedded />;
  if (n.match_id) {
    return (
      <section className="sticker grid gap-3 p-5">
        <p className="text-headline">{t('The match is over.')}</p>
        <Link to={`/matches/${n.match_id}/`} className="button button-quiet"><Icon name="trophy" className="size-4" />{t('Final standings')}</Link>
        {n.open && (
          <Button className="button-lg" busy={busy} onClick={async () => {
            setBusy(true);
            await act('night_resume', { p_session: n.session_id });
            setBusy(false);
          }}>{t('Back to the rotation')}</Button>
        )}
      </section>
    );
  }
  return (
    <section className="sticker grid justify-items-center gap-3 p-6 text-center">
      <p className="text-headline">{t('Play a round robin with tonight’s players.')}</p>
      <p className="text-subhead text-ink-secondary">{t('The rotation pauses until the match ends.')}</p>
      <Button className="button-lg w-full" disabled={!n.open} onClick={() => navigate(`/matches/new/?session=${n.session_id}`)}>
        {t('Start a match with tonight’s list')}
      </Button>
    </section>
  );
}

// MARK: 收款（只有组织者）

/** 收款记录里点进某一场也用这个 */
export function Payments({ n }: { n: Pick<NightState, 'session_id' | 'tz' | 'starts_at'> }) {
  const { data: pay, refresh } = useLive<NightPay>('night_pay', { args: { p_session: n.session_id }, every: 30_000 });
  const [amount, setAmount] = useState<string>();
  const [busy, setBusy] = useState<string>();

  async function run(key: string, fn: string, args: Record<string, unknown>) {
    setBusy(key);
    const { data, error } = await supabase!.rpc(fn, args);
    setBusy(undefined);
    if (error) toast(clubProblem(error), 'error');
    await refresh();
    return error ? undefined : (data ?? true);
  }

  if (pay === undefined) return <Skeleton className="h-72" />;
  const owing = pay.people.filter((p) => p.owes || p.paid);
  const paid = pay.people.filter((p) => p.paid);
  const unpaid = pay.people.filter((p) => p.owes && !p.paid);
  const notPaying = pay.people.filter((p) => !p.owes && !p.paid);
  const value = amount ?? (pay.amount === null ? '' : String(pay.amount));
  const remindedLately = pay.reminded_at && Date.now() - new Date(pay.reminded_at).getTime() < 12 * 3600_000;
  const why = unpaid.length === 0 ? t('Everyone has paid.')
    : pay.can_remind ? undefined
    : remindedLately ? t('You sent a reminder at {time}. You can send another 12 hours later.', { time: timeOf(pay.reminded_at!, n.tz) })
    : Date.now() < new Date(n.starts_at).getTime() ? t('You can send reminders once the session starts.')
    : t('Reminders close 7 days after the session.');

  async function saveAmount(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    const clean = value.trim() === '' ? null : Number(value);
    if (clean !== null && !(clean >= 0 && clean <= 1000)) return toast(t('Enter an amount like 12 or 12.50.'), 'error');
    if (await run('amount', 'set_session_fee', { p_session: n.session_id, p_amount: clean })) {
      setAmount(undefined);
      toast(t('Saved'));
    }
  }

  async function remind() {
    const count = await run('remind', 'remind_unpaid', { p_session: n.session_id });
    if (typeof count === 'number') {
      toast(count ? t('Reminded {n} person|Reminded {n} people', { n: count }) : t('No one to remind. Guests without an email need to hear it from you.'));
    }
  }

  const row = (p: NightPay['people'][number], action: ReactNode) => (
    <li key={p.id} className="flex min-h-14 items-center gap-3 py-2">
      <span className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
        <span className="font-bold">{p.name}</span>
        {p.guest && <Tag tint="mint">{t('Guest')}</Tag>}
        {p.guest && !p.email && !p.paid && <span className="text-caption font-bold text-ink-secondary">{t('No email')}</span>}
        {p.paid && p.paid_self && <span className="text-caption font-bold text-ink-secondary">{t('Marked by them')}</span>}
        {!p.owes && !p.paid && p.status !== 'here' && <span className="text-caption font-bold text-ink-secondary">{statusText(p.status)}</span>}
      </span>
      {action}
    </li>
  );

  return (
    <>
      <form onSubmit={saveAmount} className="sticker flex items-end gap-3 p-4">
        <div className="flex-1">
          <Field label={t('Each person pays')} hint={!pay.amount_set && pay.amount !== null && amount === undefined ? t('Same as last time.') : undefined}>
            {(props) => (
              <div className="relative">
                <span aria-hidden="true" className="pointer-events-none absolute inset-y-0 left-4 grid place-items-center font-black">$</span>
                <input {...props} className="field pl-8 tabular-nums" inputMode="decimal" type="number" min="0" step="0.01" max="1000" placeholder="12"
                       value={value} onChange={(e) => setAmount(e.target.value)} />
              </div>
            )}
          </Field>
        </div>
        <Button type="submit" variant="quiet" busy={busy === 'amount'}>{t('Save')}</Button>
      </form>

      <section className="tile flex items-center gap-3 bg-mint p-4 text-on-accent">
        <div className="flex-1">
          <p className="text-footnote font-bold">{t('Paid')}</p>
          <p className="text-[2rem] leading-tight font-black tabular-nums">{paid.length}<span className="text-headline">/{owing.length}</span></p>
        </div>
        {pay.amount !== null && <p className="text-headline">{t('{amount} each', { amount: money(pay.amount) })}</p>}
      </section>

      {pay.payee_is_me && !pay.has_handles && (
        <Notice icon="coins" tint="butter" action={{ label: t('Add payment methods'), to: '/settings/#payment' }}>{t('Add how people can pay you.')}</Notice>
      )}
      {!pay.payee_is_me && pay.payee && <p className="text-footnote font-bold text-ink-secondary">{t('Payments go to {name}.', { name: pay.payee })}</p>}

      <section aria-labelledby="unpaid" className="grid gap-2">
        <h2 id="unpaid" className="text-title3">{t('Unpaid {n}', { n: unpaid.length })}</h2>
        {unpaid.length > 0 && (
          <ul className="sticker grid divide-y-[1.5px] divide-divider px-4">
            {unpaid.map((p) => row(p, (
              <>
                <button type="button" className="link text-caption" disabled={Boolean(busy)} onClick={() => run(p.id, 'set_signup_owes', { p_signup: p.id, p_owes: false })}>
                  {t('Doesn’t need to pay')}
                </button>
                <button type="button" aria-label={t('Mark {name} as paid', { name: p.name })} disabled={busy === p.id}
                        onClick={() => run(p.id, 'mark_signup_paid', { p_signup: p.id, p_paid: true })}
                        className="press grid size-11 shrink-0 place-items-center rounded-full">
                  <span className="size-7 rounded-full border-2 border-stroke bg-surface" />
                </button>
              </>
            )))}
          </ul>
        )}
      </section>

      {paid.length > 0 && (
        <details className="tile bg-surface-muted px-4 py-3">
          <summary className="cursor-pointer font-black">{t('Paid {n}', { n: paid.length })}</summary>
          <ul className="mt-2 grid divide-y-[1.5px] divide-divider">
            {paid.map((p) => row(p, (
              <button type="button" className="link text-caption" disabled={busy === p.id} onClick={() => run(p.id, 'mark_signup_paid', { p_signup: p.id, p_paid: false })}>
                {t('Mark unpaid')}
              </button>
            )))}
          </ul>
        </details>
      )}

      {notPaying.length > 0 && (
        <details className="tile bg-surface-muted px-4 py-3">
          <summary className="cursor-pointer font-black">{t('Not paying {n}', { n: notPaying.length })}</summary>
          <ul className="mt-2 grid divide-y-[1.5px] divide-divider">
            {notPaying.map((p) => row(p, (
              <button type="button" className="link text-caption" disabled={busy === p.id} onClick={() => run(p.id, 'set_signup_owes', { p_signup: p.id, p_owes: true })}>
                {t('Add back')}
              </button>
            )))}
          </ul>
        </details>
      )}

      <div className="grid gap-1.5">
        <Button className="button-lg" busy={busy === 'remind'} disabled={Boolean(why)} onClick={remind}><Icon name="bell" className="size-5" />{t('Remind unpaid')}</Button>
        {why && <p className="text-center text-footnote font-bold text-ink-secondary">{why}</p>}
      </div>
    </>
  );
}
