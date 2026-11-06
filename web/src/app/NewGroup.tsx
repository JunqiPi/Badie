import { useState, type SubmitEvent } from 'react';
import type { Gender } from './gender';
import { t } from './i18n';
import { CourtSearch, type Court } from './pickers';
import { Icon } from './icons';
import { Empty, IconTile } from './kit';
import { AudienceField, audienceLevel } from './NewRoom';
import { navigate } from './router';
import { problem, supabase, useLive, type GroupDetail, type Profile, type Schedule } from './supabase';
import { clock, weekday } from './time';
import { Button, Field, PageHeader, Skeleton, toast } from './ui';

/** 每周最多 7 个场次（服务器也这样查） */
const MAX_SESSIONS = 7;

const blank = (): Schedule => ({ weekday: 4, start: 19 * 60 + 30, end: 22 * 60, capacity: 12, fee: '' });

/** 半点的选项：开始 0:00–23:30，结束 0:30–24:00（当天结束） */
const times = (from: number, to: number) =>
  Array.from({ length: (to - from) / 30 + 1 }, (_, i) => from + i * 30).map((minutes) => ({ minutes, label: minutes === 1440 ? t('Midnight') : clock(minutes) }));

export function NewGroup({ profile }: { profile: Profile }) {
  return <GroupForm profile={profile} />;
}

/** 群主编辑球群和场次：表单和建群一样，球馆和谁能来不能改 */
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
  const [court, setCourt] = useState<Court>();
  const [summary, setSummary] = useState(group?.summary ?? '');
  const [min, setMin] = useState(group?.level_min ?? Math.max(1, level - 1));
  const [max, setMax] = useState(group?.level_max ?? Math.min(9, level + 1));
  const [approval, setApproval] = useState(group?.join_policy === 'approval');
  const [schedules, setSchedules] = useState<Schedule[]>(() => (group?.schedules.length ? group.schedules.map((s) => ({ ...s, fee: s.fee ?? '' })) : [blank()]));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const update = (i: number, patch: Partial<Schedule>) => setSchedules(schedules.map((s, n) => (n === i ? { ...s, ...patch } : s)));
  // 再加一个：照着最后一个，换到下一天
  const add = () => {
    const last = schedules.at(-1) ?? blank();
    setSchedules([...schedules, { ...last, weekday: (last.weekday + 1) % 7, fee: '' }]);
  };
  const issue =
    name.trim().length < 2 ? t('Give the group a name.')
    : !group && !court ? t('Pick the court you play at.')
    : min > max ? t('The lowest level can’t be above the highest.')
    : schedules.some((s) => s.end - s.start > 720) ? t('Each session can be up to 12 hours')
    : schedules.some((s) => s.end - s.start < 60) ? t('Each session needs at least 1 hour')
    : schedules.some((s) => !(s.capacity >= 4 && s.capacity <= 40)) ? t('Each session needs 4 to 40 spots.')
    : undefined;

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (issue) return setError(issue);
    setBusy(true);
    setError(undefined);
    const common = { p_name: name.trim(), p_summary: summary.trim(), p_level_min: min, p_level_max: max, p_policy: approval ? 'approval' : 'open', p_schedules: schedules };
    const { data, error } = group
      ? await supabase!.rpc('update_group', { p_group: group.id, ...common })
      : await supabase!.rpc('create_group', { ...common, p_venue: court!.id, p_gender: audience });
    setBusy(false);
    if (error) return setError(problem(error));
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

        {!group && (
          <fieldset className="grid grid-cols-1 gap-2">
            <legend className="mb-2 text-headline">{t('Court')}</legend>
            {court ? (
              <div className="sticker flex items-center gap-3 p-3">
                <IconTile icon="pin" tint="sky" size="sm" />
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-bold">{court.name}</span>
                  <span className="block truncate text-footnote text-ink-secondary">{court.city}</span>
                </span>
                <button type="button" onClick={() => setCourt(undefined)} aria-label={t('Change court: {name}', { name: court.name })}
                        className="press grid size-11 place-items-center rounded-full text-ink-tertiary hover:bg-surface-muted hover:text-ink">
                  <Icon name="xCircle" className="size-5" />
                </button>
              </div>
            ) : (
              <CourtSearch onPick={setCourt} label={t('Choose venue')} />
            )}
          </fieldset>
        )}

        <Field label={t('About (optional)')} hint={t('Pace, who it suits, how fees work. No phone numbers or links.')}>
          {(props) => <textarea {...props} rows={2} maxLength={120} value={summary} onChange={(e) => setSummary(e.target.value)} className="field" />}
        </Field>

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
            <button type="button" onClick={() => setApproval(false)} aria-pressed={!approval} className="toggle">{t('Anyone at these levels')}</button>
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
                <input type="number" inputMode="numeric" min={4} max={40} value={s.capacity}
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
              <label className="grid gap-1.5 sm:col-span-2">
                <span className="text-footnote font-bold text-ink-secondary">{t('Fee note')} {t('(optional)')}</span>
                <input value={s.fee ?? ''} maxLength={40} placeholder={t('$12 each, pay at the desk')} onChange={(e) => update(i, { fee: e.target.value })} className="field" />
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

        {error && <p role="alert" className="font-bold text-danger">{error}</p>}
        <Button busy={busy} className="button-lg w-full">
          {group ? <><Icon name="check" className="size-5" />{t('Save')}</> : <><Icon name="group" className="size-5" />{t('Create group')}</>}
        </Button>
      </form>
    </div>
  );
}
