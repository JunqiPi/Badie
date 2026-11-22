import { useState, type SubmitEvent } from 'react';
import type { Gender } from './gender';
import { t } from './i18n';
import { CourtSearch, type Court } from './pickers';
import { Icon } from './icons';
import { guestLink } from './GuestSignup';
import { Empty, IconTile } from './kit';
import { AudienceField, audienceLevel } from './NewRoom';
import { navigate } from './router';
import { problem, supabase, useLive, type GroupDetail, type Profile, type Schedule } from './supabase';
import { clock, weekday } from './time';
import { Button, Field, PageHeader, Skeleton, toast } from './ui';

/** 每周最多 7 个场次（服务器也这样查） */
const MAX_SESSIONS = 7;
/** 一个球群最多 5 个球馆，第一个是主球馆（服务器也这样查） */
const MAX_COURTS = 5;

const blank = (): Schedule => ({ weekday: 4, start: 19 * 60 + 30, end: 22 * 60, capacity: 12, fee: '' });

/** 半点的选项：开始 0:00–23:30，结束 0:30–24:00（当天结束） */
const times = (from: number, to: number) =>
  Array.from({ length: (to - from) / 30 + 1 }, (_, i) => from + i * 30).map((minutes) => ({ minutes, label: minutes === 1440 ? t('Midnight') : clock(minutes) }));

export function NewGroup({ profile }: { profile: Profile }) {
  return <GroupForm profile={profile} />;
}

/** 群主编辑球群和场次：表单和建群一样，谁能来不能改（球馆可以加减） */
export function EditGroup({ id, profile }: { id: string; profile: Profile }) {
  const { data: group } = useLive<GroupDetail | null>('group_page', { args: { p_group: id }, every: 3_600_000 });
  if (group === undefined) return <Skeleton className="mx-auto h-96 max-w-2xl" />;
  if (group?.my_role !== 'owner') {
    return <Empty icon="group" tint="lavender" title={t('Group not found')} action={{ label: t('Groups'), to: '/groups/' }}>{t('It may have been removed.')}</Empty>;
  }
  return <GroupForm profile={profile} group={group} />;
}

function GroupForm({ profile, group }: { profile: Profile; group?: GroupDetail }) {
  const [audience, setAudience] = useState<Gender | null>(null);
  const level = audienceLevel(profile, audience);
  const [name, setName] = useState(group?.name ?? '');
  const [courts, setCourts] = useState<Court[]>(() => (group?.venues ?? (group ? [group.venue] : [])).map((c) => ({ id: c.id, name: c.name, city: c.city, time_zone_id: c.tz })));
  const [summary, setSummary] = useState(group?.summary ?? '');
  const [min, setMin] = useState(group?.level_min ?? Math.max(1, level - 1));
  const [max, setMax] = useState(group?.level_max ?? Math.min(9, level + 1));
  const [approval, setApproval] = useState(group?.join_policy === 'approval');
  // 教练带课：每场 1–40 人，水平范围只作提示
  const [coached, setCoached] = useState(group?.coached ?? false);
  const minSpots = coached ? 1 : 4;
  const [schedules, setSchedules] = useState<Schedule[]>(() => (group?.schedules.length ? group.schedules.map((s) => ({ ...s, fee: s.fee ?? '' })) : [blank()]));
  // 访客报名：只有编辑时有（链接在第一次打开、保存后才生成）；limit 为 null 是每场名额的一半
  const [guests, setGuests] = useState<Guests>({ on: group?.guests_allowed ?? false, limit: group?.guest_limit ?? null });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const update = (i: number, patch: Partial<Schedule>) => setSchedules(schedules.map((s, n) => (n === i ? { ...s, ...patch } : s)));
  // 再加一个：照着最后一个，换到下一天
  const add = () => {
    const last = schedules.at(-1) ?? blank();
    setSchedules([...schedules, { ...last, weekday: (last.weekday + 1) % 7, fee: '' }]);
  };
  // 每一场在哪个球馆：没选或选的球馆删掉了，就是主球馆
  const courtOf = (s: Schedule) => (courts.some((c) => c.id === s.venue) ? s.venue! : courts[0]?.id);
  const issue =
    name.trim().length < 2 ? t('Give the group a name.')
    : courts.length === 0 ? t('Pick the court you play at.')
    : min > max ? t('The lowest level can’t be above the highest.')
    : schedules.some((s) => s.end - s.start > 720) ? t('Each session can be up to 12 hours')
    : schedules.some((s) => s.end - s.start < 60) ? t('Each session needs at least 1 hour')
    : schedules.some((s) => !(s.capacity >= minSpots && s.capacity <= 40)) ? (coached ? t('Each session needs 1 to 40 spots.') : t('Each session needs 4 to 40 spots.'))
    : schedules.some((s) => s.price != null && !(s.price >= 0 && s.price <= 1000)) ? t('Enter an amount like 12 or 12.50.')
    : undefined;

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (issue) return setError(issue);
    setBusy(true);
    setError(undefined);
    const sessions = schedules.map((s) => ({ ...s, price: s.price ?? null, venue: courts.length > 1 ? courtOf(s) : null }));
    const common = {
      p_name: name.trim(), p_summary: summary.trim(), p_level_min: min, p_level_max: max, p_policy: approval ? 'approval' : 'open',
      p_schedules: sessions, p_coached: coached, p_venues: courts.map((c) => c.id),
    };
    const { data, error } = group
      ? await supabase!.rpc('update_group', { p_group: group.id, ...common })
      : await supabase!.rpc('create_group', { ...common, p_venue: courts[0].id, p_gender: audience });
    const guestsChanged = group && (guests.on !== Boolean(group.guests_allowed) || guests.limit !== (group.guest_limit ?? null));
    const { error: guestError } = !error && guestsChanged
      ? await supabase!.rpc('set_guest_signup', { p_group: group.id, p_allowed: guests.on, p_limit: guests.limit })
      : { error: null };
    setBusy(false);
    if (error || guestError) return setError(problem((error ?? guestError)!));
    if (group) toast(t('Saved'));
    navigate(`/groups/${group?.id ?? data}/`, true);
  }

  const levels = Array.from({ length: 9 }, (_, i) => i + 1);
  const starts = times(0, 1410);
  const ends = times(30, 1440);
  return (
    <div className="mx-auto max-w-2xl">
      {group ? (
        <PageHeader back={`/groups/${group.id}/`} eyebrow={group.venue.name} title={t('Edit group')} />
      ) : (
        <PageHeader back="/groups/" title={t('Start a group')}>
          {t('For a session that happens every week at the same court. Members sign up in one tap and get a group chat.')}
        </PageHeader>
      )}

      <form onSubmit={submit} noValidate className="grid gap-6">
        <Field label={t('Name')} hint={t('2–20 characters, like “Thursday doubles”.')}>
          {(props) => <input {...props} value={name} maxLength={20} onChange={(e) => setName(e.target.value)} className="field" />}
        </Field>

        {/* 球馆：1–5 个，第一个是主球馆 */}
        <fieldset className="grid grid-cols-1 gap-2">
          <legend className="mb-2 text-headline">{t('Court')}</legend>
          {courts.map((court, i) => (
            <div key={court.id} className="sticker flex items-center gap-3 p-3">
              <IconTile icon="pin" tint={i === 0 ? 'sky' : 'surface'} size="sm" />
              <span className="min-w-0 flex-1">
                <span className="block truncate font-bold">{court.name}</span>
                <span className="block truncate text-footnote text-ink-secondary">{i === 0 && courts.length > 1 ? `${court.city} · ${t('Main court')}` : court.city}</span>
              </span>
              <button type="button" onClick={() => setCourts(courts.filter((c) => c.id !== court.id))} aria-label={i === 0 ? t('Change court: {name}', { name: court.name }) : t('Remove {name}', { name: court.name })}
                      className="press grid size-11 place-items-center rounded-full text-ink-tertiary hover:bg-surface-muted hover:text-ink">
                <Icon name="xCircle" className="size-5" />
              </button>
            </div>
          ))}
          {courts.length < MAX_COURTS && (
            <CourtSearch label={courts.length ? t('Add another court') : t('Choose venue')}
                         onPick={(court) => !courts.some((c) => c.id === court.id) && setCourts([...courts, court])} />
          )}
        </fieldset>

        <Field label={t('About (optional)')} hint={t('Pace, who it suits, how fees work. No phone numbers or links.')}>
          {(props) => <textarea {...props} rows={2} maxLength={120} value={summary} onChange={(e) => setSummary(e.target.value)} className="field" />}
        </Field>

        <div className="grid gap-2">
          <button type="button" onClick={() => setCoached(!coached)} aria-pressed={coached} className="toggle justify-self-start">{t('Coach-led')}</button>
          {coached && <p className="text-footnote text-ink-secondary">{t('Sessions can have as few as 1 spot. Levels are only a guide.')}</p>}
        </div>

        {!group && (
          <AudienceField profile={profile} value={audience} onChange={(value) => {
            const own = audienceLevel(profile, value);
            setAudience(value);
            setMin(Math.max(1, own - 1));
            setMax(Math.min(9, own + 1));
          }} />
        )}

        <fieldset className="grid gap-2">
          <legend className="mb-2 text-headline">{t('Levels')}</legend>
          <div className="flex items-center gap-3">
            <select aria-label={t('Lowest level')} value={min} onChange={(e) => setMin(Number(e.target.value))} className="field w-24">
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
            <span aria-hidden="true" className="shrink-0">{t('to')}</span>
            <select aria-label={t('Highest level')} value={max} onChange={(e) => setMax(Number(e.target.value))} className="field w-24">
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </div>
        </fieldset>

        <fieldset className="grid gap-2">
          <legend className="mb-2 text-headline">{t('Who can join')}</legend>
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => setApproval(false)} aria-pressed={!approval} className="toggle">{coached ? t('Anyone') : t('Anyone at these levels')}</button>
            <button type="button" onClick={() => setApproval(true)} aria-pressed={approval} className="toggle">{t('Organizer approves')}</button>
          </div>
        </fieldset>

        <fieldset className="grid gap-4">
          <legend className="mb-2 text-headline">{t('Weekly sessions')} <span className="text-footnote font-bold text-ink-secondary">{t('(up to {n})', { n: MAX_SESSIONS })}</span></legend>
          {schedules.map((s, i) => (
            <div key={i} className="sticker grid gap-3 bg-butter/40 p-4 sm:grid-cols-2">
              <label className="grid gap-1.5">
                <span className="text-footnote font-bold text-ink-secondary">{t('Day of the week')}</span>
                <select value={s.weekday} onChange={(e) => update(i, { weekday: Number(e.target.value) })} className="field">
                  {[0, 1, 2, 3, 4, 5, 6].map((n) => <option key={n} value={n}>{weekday(n)}</option>)}
                </select>
              </label>
              <label className="grid gap-1.5">
                <span className="text-footnote font-bold text-ink-secondary">{t('Spots')}</span>
                <input type="number" inputMode="numeric" min={minSpots} max={40} value={s.capacity}
                       onChange={(e) => update(i, { capacity: Number(e.target.value) })} className="field" />
              </label>
              <label className="grid gap-1.5">
                <span className="text-footnote font-bold text-ink-secondary">{t('From')}</span>
                <select value={s.start} onChange={(e) => update(i, { start: Number(e.target.value) })} className="field">
                  {starts.map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
                </select>
              </label>
              <label className="grid gap-1.5">
                <span className="text-footnote font-bold text-ink-secondary">{t('Until')}</span>
                <select value={s.end} onChange={(e) => update(i, { end: Number(e.target.value) })} className="field">
                  {ends.map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
                </select>
              </label>
              {courts.length > 1 && (
                <label className="grid gap-1.5 sm:col-span-2">
                  <span className="text-footnote font-bold text-ink-secondary">{t('Court')}</span>
                  <select value={courtOf(s)} onChange={(e) => update(i, { venue: e.target.value })} className="field">
                    {courts.map((c, n) => <option key={c.id} value={c.id}>{n === 0 ? `${c.name} · ${t('Main court')}` : c.name}</option>)}
                  </select>
                </label>
              )}
              {/* 价格：空 = 不写，0 = 免费。报名前就能看到，开场后按这个收 */}
              <label className="grid gap-1.5 sm:col-span-2">
                <span className="text-footnote font-bold text-ink-secondary">{t('Price per person')} {t('(optional)')}</span>
                <span className="relative">
                  <span aria-hidden="true" className="pointer-events-none absolute inset-y-0 left-4 grid place-items-center font-black">$</span>
                  <input type="number" inputMode="decimal" min="0" max="1000" step="0.01" placeholder={t('0 = free')}
                         value={s.price ?? ''} className="field pl-8 tabular-nums"
                         onChange={(e) => update(i, { price: e.target.value === '' ? null : Number(e.target.value) })} />
                </span>
              </label>
              <label className="grid gap-1.5 sm:col-span-2">
                <span className="text-footnote font-bold text-ink-secondary">{t('Fee note')} {t('(optional)')}</span>
                <input value={s.fee ?? ''} maxLength={120} placeholder={t('Shuttles included. Pay at the desk.')} onChange={(e) => update(i, { fee: e.target.value })} className="field" />
              </label>
              {schedules.length > 1 && (
                <button type="button" onClick={() => setSchedules(schedules.filter((_, n) => n !== i))} className="link justify-self-start text-sm">
                  {t('Remove this session')}
                </button>
              )}
            </div>
          ))}
          {schedules.length < MAX_SESSIONS && (
            <Button type="button" variant="quiet" className="justify-self-start" onClick={add}>
              <Icon name="plus" className="size-4" />{t('Add another session')}
            </Button>
          )}
        </fieldset>

        {group && (
          <GuestSignupField group={group} value={guests} onChange={setGuests}
                            maxSpots={Math.min(40, Math.max(1, ...schedules.map((s) => s.capacity || 1)))} />
        )}

        {error && <p role="alert" className="font-bold text-danger">{error}</p>}
        <Button busy={busy} className="button-lg w-full">
          {group ? <><Icon name="check" className="size-5" />{t('Save')}</> : <><Icon name="group" className="size-5" />{t('Create group')}</>}
        </Button>
      </form>
    </div>
  );
}

type Guests = { on: boolean; limit: number | null };

/** 允许不注册的人报名：每场最多几个访客（没改过是名额的一半）、报名链接（可以重置，旧的马上失效） */
function GuestSignupField({ group, value, onChange, maxSpots }: {
  group: GroupDetail;
  value: Guests;
  onChange: (value: Guests) => void;
  /** 名额最多的那一场有几个名额 */
  maxSpots: number;
}) {
  const [code, setCode] = useState(group.guest_code ?? null);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const shown = Math.min(maxSpots, value.limit ?? Math.max(1, Math.floor(maxSpots / 2)));
  const setLimit = (n: number) => onChange({ ...value, limit: Math.min(maxSpots, Math.max(1, n)) });

  async function copy() {
    try {
      await navigator.clipboard.writeText(guestLink(code!));
      toast(t('Sign-up link copied.'));
    } catch {
      toast(guestLink(code!));
    }
  }

  async function reset() {
    setBusy(true);
    const { data, error } = await supabase!.rpc('reset_guest_link', { p_group: group.id });
    setBusy(false);
    setConfirming(false);
    if (error) return toast(problem(error), 'error');
    setCode(data as string);
    toast(t('New link ready. The old one no longer works.'));
  }

  return (
    <fieldset className="grid gap-2">
      <legend className="mb-2 text-headline">{t('Guest sign-up')}</legend>
      <button type="button" onClick={() => onChange({ ...value, on: !value.on })} aria-pressed={value.on} className="toggle justify-self-start">
        {t('Let people sign up without an account')}
      </button>
      {value.on && (
        <div className="sticker grid gap-3 p-4">
          <div className="flex items-center justify-between gap-3">
            <span id="guest-limit" className="font-bold">{t('Guests per session, up to')}</span>
            <div role="group" aria-labelledby="guest-limit" className="flex items-center">
              <button type="button" aria-label={t('Fewer guests')} disabled={shown <= 1} onClick={() => setLimit(shown - 1)}
                      className="press grid size-11 place-items-center rounded-full hover:bg-surface-muted disabled:opacity-40">
                <Icon name="minus" className="size-5" />
              </button>
              <span className="min-w-10 text-center text-headline tabular-nums" aria-live="polite">{shown}</span>
              <button type="button" aria-label={t('More guests')} disabled={shown >= maxSpots} onClick={() => setLimit(shown + 1)}
                      className="press grid size-11 place-items-center rounded-full hover:bg-surface-muted disabled:opacity-40">
                <Icon name="plus" className="size-5" />
              </button>
            </div>
          </div>
          {code && group.guests_allowed ? (
            <>
              <p className="flex min-w-0 items-center gap-2 font-bold">
                <IconTile icon="link" tint="sky" size="sm" />
                <span className="truncate">{guestLink(code).replace(/^https?:\/\//, '')}</span>
              </p>
              <div className="flex flex-wrap gap-2">
                <Button type="button" onClick={copy}><Icon name="copy" className="size-4" />{t('Copy sign-up link')}</Button>
                {confirming ? (
                  <Button type="button" variant="danger" busy={busy} onClick={reset}>{t('Yes, reset link')}</Button>
                ) : (
                  <Button type="button" variant="quiet" onClick={() => setConfirming(true)}>{t('Reset link')}</Button>
                )}
              </div>
            </>
          ) : (
            <p className="text-footnote text-ink-secondary">{t('Save to get the sign-up link.')}</p>
          )}
        </div>
      )}
      <p className="text-footnote text-ink-secondary">{t('Turning this off stops the link from working.')}</p>
    </fieldset>
  );
}
