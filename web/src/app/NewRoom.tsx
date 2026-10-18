import { useState, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { t } from './i18n';
import { CourtSearch, type Court } from './pickers';
import { Link, navigate } from './router';
import { problem, supabase, type Mode, type Profile, type RoomTag } from './supabase';
import { halfHours, today, zoned } from './time';
import { tagText } from './Rooms';
import { Button, Field, PageHeader } from './ui';

export type Slot = { court?: Court; date: string; from: number; to: number };

const zone = (court?: Court) => court?.time_zone_id ?? Intl.DateTimeFormat().resolvedOptions().timeZone;

/** 和数据库一样的检查：1–8 小时、还没开始、两周内 */
export function slotTimes(slot: Slot) {
  const tz = zone(slot.court);
  const startsAt = zoned(slot.date, slot.from, tz);
  const endsAt = zoned(slot.date, slot.to, tz);
  const length = (endsAt.getTime() - startsAt.getTime()) / 3600000;
  const issue = !slot.court
    ? t('Pick the court you booked.')
    : length < 1 || length > 8
      ? t('Pick a time window between 1 and 8 hours.')
      : startsAt.getTime() <= Date.now()
        ? t('Pick a start time that hasn’t passed.')
        : undefined;
  return { startsAt, endsAt, issue };
}

/** 球馆 + 日期 + 时间段 */
export function SlotFields({ slot, onChange }: { slot: Slot; onChange: (slot: Slot) => void }) {
  const tz = zone(slot.court);
  const times = halfHours();
  return (
    <>
      <div className="grid gap-2">
        <p className="font-extrabold">{t('Court')}</p>
        {slot.court ? (
          <button type="button" onClick={() => onChange({ ...slot, court: undefined })} aria-pressed="true"
                  aria-label={t('Change court: {name}', { name: slot.court.name })} className="toggle justify-self-start">
            {slot.court.name} <span aria-hidden="true">×</span>
          </button>
        ) : (
          <CourtSearch onPick={(court) => onChange({ ...slot, court })} label={t('Court')} />
        )}
      </div>
      <Field label={t('Day')}>
        {(props) => <input {...props} type="date" value={slot.date} min={today(tz)} max={today(tz, 13)} onChange={(e) => onChange({ ...slot, date: e.target.value })} className="field" />}
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label={t('From')}>
          {(props) => (
            <select {...props} value={slot.from} onChange={(e) => onChange({ ...slot, from: Number(e.target.value) })} className="field">
              {times.slice(0, -2).map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
        <Field label={t('Until')}>
          {(props) => (
            <select {...props} value={slot.to} onChange={(e) => onChange({ ...slot, to: Number(e.target.value) })} className="field">
              {times.slice(2).map((h) => <option key={h.minutes} value={h.minutes}>{h.label}</option>)}
            </select>
          )}
        </Field>
      </div>
    </>
  );
}

const tags: RoomTag[] = ['beginner_friendly', 'casual', 'competitive', 'women_friendly', 'coaching'];

export function NewRoom({ profile }: { profile: Profile }) {
  const level = tier(profile.rating).level;
  const [mode, setMode] = useState<Mode>('doubles');
  const [isPublic, setPublic] = useState(true);
  const [slot, setSlot] = useState<Slot>(() => ({ date: today(zone(), 1), from: 19 * 60, to: 21 * 60 }));
  const [min, setMin] = useState(Math.max(1, level - 1));
  const [max, setMax] = useState(Math.min(9, level + 1));
  const [picked, setPicked] = useState<RoomTag[]>([]);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const { startsAt, endsAt, issue: slotIssue } = slotTimes(slot);
  const issue = slotIssue ?? (min > max ? t('The lowest level can’t be above the highest.') : undefined);

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (issue) return setError(issue);
    setBusy(true);
    setError(undefined);
    const { data, error } = await supabase!.rpc('create_room', {
      p_mode: mode, p_visibility: isPublic ? 'public' : 'private', p_venue: slot.court!.id,
      p_starts_at: startsAt.toISOString(), p_ends_at: endsAt.toISOString(),
      p_level_min: min, p_level_max: max, p_tags: picked, p_note: note.trim(),
    });
    setBusy(false);
    if (error) return setError(problem(error));
    navigate(`/app/rooms/${data}/`, true);
  }

  const levels = Array.from({ length: 9 }, (_, i) => i + 1);
  return (
    <div className="max-w-2xl">
      <p className="mb-6"><Link to="/app/rooms/" className="link text-sm">{t('Open games')}</Link></p>
      <PageHeader eyebrow={t('Play')} title={t('Post a game')}>
        {t('You have the court; we’ll help fill it. You’re counted as one of the players.')}
      </PageHeader>

      <form onSubmit={submit} noValidate className="sticker grid gap-6 p-5 sm:p-8">
        <fieldset className="grid gap-2">
          <legend className="mb-2 font-extrabold">{t('Game')}</legend>
          <div className="flex gap-2">
            {(['doubles', 'singles'] as const).map((m) => (
              <button type="button" key={m} onClick={() => setMode(m)} aria-pressed={mode === m} className="toggle flex-1">
                {m === 'doubles' ? t('Doubles · 4 players') : t('Singles · 2 players')}
              </button>
            ))}
          </div>
        </fieldset>

        <SlotFields slot={slot} onChange={setSlot} />

        <fieldset className="grid gap-2">
          <legend className="mb-2 font-extrabold">{t('Levels')}</legend>
          <div className="flex items-center gap-3">
            <select aria-label={t('Lowest level')} value={min} onChange={(e) => setMin(Number(e.target.value))} className="field w-24">
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
            <span aria-hidden="true">{t('to')}</span>
            <select aria-label={t('Highest level')} value={max} onChange={(e) => setMax(Number(e.target.value))} className="field w-24">
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </div>
          <p className="text-sm text-ink-tertiary">{t('Your own level ({level}) is always included. Friends you invite can join whatever their level.', { level })}</p>
        </fieldset>

        <fieldset className="grid gap-2">
          <legend className="mb-2 font-extrabold">{t('Who can find it')}</legend>
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => setPublic(true)} aria-pressed={isPublic} className="toggle">{t('Players nearby')}</button>
            <button type="button" onClick={() => setPublic(false)} aria-pressed={!isPublic} className="toggle">{t('Only people with the code')}</button>
          </div>
          <p className="text-sm text-ink-tertiary">
            {isPublic ? t('When it’s full, up to 4 people can wait in line and move up if someone drops out.') : t('Share the room code or invite friends. It won’t show up nearby.')}
          </p>
        </fieldset>

        <fieldset className="grid gap-2">
          <legend className="mb-2 font-extrabold">{t('Vibe')} <span className="font-semibold text-ink-tertiary">{t('(optional)')}</span></legend>
          <div className="flex flex-wrap gap-2">
            {tags.map((tag) => (
              <button type="button" key={tag} aria-pressed={picked.includes(tag)} className="toggle"
                      onClick={() => setPicked(picked.includes(tag) ? picked.filter((p) => p !== tag) : [...picked, tag])}>
                {tagText(tag)}
              </button>
            ))}
          </div>
        </fieldset>

        <Field label={t('Note (optional)')} hint={t('Like “court 3, bring a shuttle”. No phone numbers or links.')}>
          {(props) => <input {...props} value={note} maxLength={80} onChange={(e) => setNote(e.target.value)} className="field" />}
        </Field>

        {error && <p role="alert" className="font-bold text-danger">{error}</p>}
        <Button busy={busy} className="justify-self-start">{t('Post game')}</Button>
      </form>
    </div>
  );
}
