import { useState, type SubmitEvent } from 'react';
import { audienceLabel, WOMEN_OFFSET, type Gender } from './gender';
import { t } from './i18n';
import { CourtSearch, type Court } from './pickers';
import { Icon } from './icons';
import { IconTile } from './kit';
import { DayPicker, FormatPicker, TimeRange } from './Play';
import { navigate } from './router';
import { problem, supabase, type Mode, type Profile, type RoomTag } from './supabase';
import { nextDays, today, zoned } from './time';
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
  const days = nextDays(14);
  return (
    <>
      <fieldset className="grid grid-cols-1 gap-2">
        <legend className="mb-2 text-headline">{t('Court')}</legend>
        {slot.court ? (
          <div className="sticker flex items-center gap-3 p-3">
            <IconTile icon="pin" tint="sky" size="sm" />
            <span className="min-w-0 flex-1">
              <span className="block truncate font-bold">{slot.court.name}</span>
              <span className="block truncate text-footnote text-ink-secondary">{slot.court.city}</span>
            </span>
            <button type="button" onClick={() => onChange({ ...slot, court: undefined })} aria-label={t('Change court: {name}', { name: slot.court.name })}
                    className="press grid size-11 place-items-center rounded-full text-ink-tertiary hover:bg-surface-muted hover:text-ink">
              <Icon name="xCircle" className="size-5" />
            </button>
          </div>
        ) : (
          <CourtSearch onPick={(court) => onChange({ ...slot, court })} label={t('Choose venue')} />
        )}
      </fieldset>
      <DayPicker days={days} value={days.includes(slot.date) ? slot.date : days[0]} onChange={(date) => onChange({ ...slot, date })} />
      <TimeRange from={slot.from} to={slot.to} onChange={(from, to) => onChange({ ...slot, from, to })} />
    </>
  );
}

const tags: RoomTag[] = ['beginner_friendly', 'casual', 'competitive', 'women_friendly', 'coaching'];

/** 球局、球群的等级按参加的人算：只限女生用女子等级，男女都能来时女子等级按低 1.5 级换算 */
export const audienceLevel = (profile: Profile, audience: Gender | null) =>
  Math.min(9, Math.max(1, Math.round(profile.gender === 'female' && audience !== 'female' ? profile.rating - WOMEN_OFFSET : profile.rating)));

/** 谁能来：不限，或只限和自己同性别的人 */
export function AudienceField({ profile, value, onChange }: { profile: Profile; value: Gender | null; onChange: (value: Gender | null) => void }) {
  return (
    <fieldset className="grid gap-2">
      <legend className="mb-2 text-headline">{t('Who can join')}</legend>
      <div className="flex flex-wrap gap-2">
        <button type="button" onClick={() => onChange(null)} aria-pressed={value === null} className="toggle">{t('Anyone')}</button>
        {profile.gender && (
          <button type="button" onClick={() => onChange(profile.gender)} aria-pressed={value === profile.gender} className="toggle">
            {audienceLabel(profile.gender)}
          </button>
        )}
      </div>
      <p className="text-footnote text-ink-secondary">
        {value ? t('Only they can see and join it.') : t('When men and women play together, a women’s level counts about 1.5 levels lower, so the game stays even.')}
      </p>
    </fieldset>
  );
}

export function NewRoom({ profile }: { profile: Profile }) {
  const [audience, setAudience] = useState<Gender | null>(null);
  const level = audienceLevel(profile, audience);
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
      p_level_min: min, p_level_max: max, p_tags: picked, p_note: note.trim(), p_gender: audience,
    });
    setBusy(false);
    if (error) return setError(problem(error));
    navigate(`/rooms/${data}/`, true);
  }

  const levels = Array.from({ length: 9 }, (_, i) => i + 1);
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader back="/games/" title={t('Start a game')}>
        {t('You have the court; we’ll help fill it. You’re counted as one of the players.')}
      </PageHeader>

      <form onSubmit={submit} noValidate className="grid gap-6">
        <FormatPicker value={mode} onChange={setMode} />

        <SlotFields slot={slot} onChange={setSlot} />

        <AudienceField profile={profile} value={audience} onChange={(value) => {
          // 换了谁能来，自己的等级可能跟着换算：范围重新围着自己
          const own = audienceLevel(profile, value);
          setAudience(value);
          setMin(Math.max(1, own - 1));
          setMax(Math.min(9, own + 1));
        }} />

        <fieldset className="grid gap-2">
          <legend className="mb-2 text-headline">{t('Levels')}</legend>
          <div className="flex items-center gap-3">
            <select aria-label={t('Lowest level')} value={min} onChange={(e) => setMin(Number(e.target.value))} className="field w-24">
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
            <span aria-hidden="true">{t('to')}</span>
            <select aria-label={t('Highest level')} value={max} onChange={(e) => setMax(Number(e.target.value))} className="field w-24">
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </div>
          <p className="text-footnote text-ink-secondary">{t('Your own level ({level}) is always included. Friends you invite can join whatever their level.', { level })}</p>
        </fieldset>

        <fieldset className="grid gap-2">
          <legend className="mb-2 text-headline">{t('Who can find it')}</legend>
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => setPublic(true)} aria-pressed={isPublic} className="toggle">{t('Players nearby')}</button>
            <button type="button" onClick={() => setPublic(false)} aria-pressed={!isPublic} className="toggle">{t('Only people with the code')}</button>
          </div>
          <p className="text-footnote text-ink-secondary">
            {isPublic ? t('When it’s full, up to 4 people can wait in line and move up if someone drops out.') : t('Share the room code or invite friends. It won’t show up nearby.')}
          </p>
        </fieldset>

        <fieldset className="grid gap-2">
          <legend className="mb-2 text-headline">{t('Vibe')} <span className="text-footnote font-bold text-ink-secondary">{t('(optional)')}</span></legend>
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
        <Button busy={busy} className="button-lg w-full"><Icon name="court" className="size-5" />{t('Post game')}</Button>
      </form>
    </div>
  );
}
