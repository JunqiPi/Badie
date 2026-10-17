import { useState, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { CourtSearch, type Court } from './pickers';
import { Link, navigate } from './router';
import { problem, supabase, type Profile, type Schedule } from './supabase';
import { halfHours, weekdays } from './time';
import { Button, Field, PageHeader } from './ui';

const blank = (): Schedule => ({ weekday: 4, start: 19 * 60 + 30, end: 22 * 60, capacity: 12, fee: '' });

export function NewGroup({ profile }: { profile: Profile }) {
  const level = tier(profile.rating).level;
  const [name, setName] = useState('');
  const [court, setCourt] = useState<Court>();
  const [summary, setSummary] = useState('');
  const [min, setMin] = useState(Math.max(1, level - 1));
  const [max, setMax] = useState(Math.min(9, level + 1));
  const [approval, setApproval] = useState(false);
  const [schedules, setSchedules] = useState<Schedule[]>([blank()]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const update = (i: number, patch: Partial<Schedule>) => setSchedules(schedules.map((s, n) => (n === i ? { ...s, ...patch } : s)));
  const issue =
    name.trim().length < 2 ? 'Give the group a name.'
    : !court ? 'Pick the court you play at.'
    : min > max ? 'The lowest level can’t be above the highest.'
    : schedules.some((s) => s.end - s.start < 60 || s.end - s.start > 480) ? 'Each session should be 1 to 8 hours.'
    : schedules.some((s) => !(s.capacity >= 4 && s.capacity <= 40)) ? 'Each session needs 4 to 40 spots.'
    : undefined;

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (issue) return setError(issue);
    setBusy(true);
    const { data, error } = await supabase!.rpc('create_group', {
      p_name: name.trim(), p_venue: court!.id, p_summary: summary.trim(), p_level_min: min, p_level_max: max,
      p_policy: approval ? 'approval' : 'open', p_schedules: schedules,
    });
    setBusy(false);
    if (error) return setError(problem(error));
    navigate(`/app/groups/${data}/`, true);
  }

  const levels = Array.from({ length: 9 }, (_, i) => i + 1);
  return (
    <div className="max-w-2xl">
      <p className="mb-6"><Link to="/app/groups/" className="link text-sm">Groups</Link></p>
      <PageHeader eyebrow="Play" title="Start a group">
        For a session that happens every week at the same court. Members sign up in one tap and get a group chat.
      </PageHeader>

      <form onSubmit={submit} noValidate className="sticker grid gap-6 p-5 sm:p-8">
        <Field label="Name" hint="2–20 characters, like “Thursday doubles”.">
          {(props) => <input {...props} value={name} maxLength={20} onChange={(e) => setName(e.target.value)} className="field" />}
        </Field>

        <div className="grid gap-2">
          <p className="font-extrabold">Court</p>
          {court ? (
            <button type="button" onClick={() => setCourt(undefined)} aria-pressed="true" aria-label={`Change court: ${court.name}`} className="toggle justify-self-start">
              {court.name} <span aria-hidden="true">×</span>
            </button>
          ) : (
            <CourtSearch onPick={setCourt} label="Court" />
          )}
        </div>

        <Field label="About (optional)" hint="Pace, who it suits, how fees work. No phone numbers or links.">
          {(props) => <textarea {...props} rows={2} maxLength={120} value={summary} onChange={(e) => setSummary(e.target.value)} className="field" />}
        </Field>

        <fieldset className="grid gap-2">
          <legend className="mb-2 font-extrabold">Levels</legend>
          <div className="flex items-center gap-3">
            <select aria-label="Lowest level" value={min} onChange={(e) => setMin(Number(e.target.value))} className="field w-24">
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
            <span aria-hidden="true">to</span>
            <select aria-label="Highest level" value={max} onChange={(e) => setMax(Number(e.target.value))} className="field w-24">
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </div>
        </fieldset>

        <fieldset className="grid gap-2">
          <legend className="mb-2 font-extrabold">Who can join</legend>
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => setApproval(false)} aria-pressed={!approval} className="toggle">Anyone at these levels</button>
            <button type="button" onClick={() => setApproval(true)} aria-pressed={approval} className="toggle">Organizer approves</button>
          </div>
        </fieldset>

        <fieldset className="grid gap-4">
          <legend className="mb-2 font-extrabold">Weekly sessions <span className="font-semibold text-ink-tertiary">(up to 3)</span></legend>
          {schedules.map((s, i) => (
            <div key={i} className="tile grid gap-3 p-4 sm:grid-cols-2">
              <label className="grid gap-1.5">
                <span className="text-sm font-extrabold">Day</span>
                <select value={s.weekday} onChange={(e) => update(i, { weekday: Number(e.target.value) })} className="field">
                  {weekdays.map((d, n) => <option key={d} value={n}>{d}</option>)}
                </select>
              </label>
              <label className="grid gap-1.5">
                <span className="text-sm font-extrabold">Spots</span>
                <input type="number" inputMode="numeric" min={4} max={40} value={s.capacity}
                       onChange={(e) => update(i, { capacity: Number(e.target.value) })} className="field" />
              </label>
              <label className="grid gap-1.5">
                <span className="text-sm font-extrabold">From</span>
                <select value={s.start} onChange={(e) => update(i, { start: Number(e.target.value) })} className="field">
                  {halfHours.map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
                </select>
              </label>
              <label className="grid gap-1.5">
                <span className="text-sm font-extrabold">Until</span>
                <select value={s.end} onChange={(e) => update(i, { end: Number(e.target.value) })} className="field">
                  {halfHours.map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
                </select>
              </label>
              <label className="grid gap-1.5 sm:col-span-2">
                <span className="text-sm font-extrabold">Fee note <span className="font-semibold text-ink-tertiary">(optional)</span></span>
                <input value={s.fee ?? ''} maxLength={40} placeholder="$12 each, pay at the desk" onChange={(e) => update(i, { fee: e.target.value })} className="field" />
              </label>
              {schedules.length > 1 && (
                <button type="button" onClick={() => setSchedules(schedules.filter((_, n) => n !== i))} className="link justify-self-start text-sm">
                  Remove this session
                </button>
              )}
            </div>
          ))}
          {schedules.length < 3 && (
            <Button type="button" variant="quiet" className="justify-self-start" onClick={() => setSchedules([...schedules, blank()])}>
              Add another day
            </Button>
          )}
        </fieldset>

        {error && <p role="alert" className="font-bold text-danger">{error}</p>}
        <Button busy={busy} className="justify-self-start">Create group</Button>
      </form>
    </div>
  );
}
