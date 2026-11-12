import { useState, type SubmitEvent } from 'react';
import { audienceLabel, EventField, eventOptions, WOMEN_OFFSET, type Gender, type PlayEvent } from './gender';
import { t } from './i18n';
import { CourtSearch, type Court } from './pickers';
import { Icon } from './icons';
import { IconTile, Notice } from './kit';
import { DayPicker, FormatPicker, TimeRange } from './Play';
import { navigate } from './router';
import { problem, supabase, useLive, type Mode, type PlayerCard, type Profile, type RoomTag } from './supabase';
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
  const days = nextDays(30);
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

/** 球局按项目算：混双、女单女双按自己的等级（混双里男生和男生比、女生和女生比），其余同上 */
const eventLevel = (profile: Profile, event: PlayEvent) =>
  event === 'mixed' ? Math.min(9, Math.max(1, Math.round(profile.rating))) : audienceLevel(profile, event === 'any' ? null : event);

/** 球群：谁能来，不限或只限和自己同性别的人 */
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

/** 地址里带的：?mode=doubles&invite=<球友 id>&gender=female&name=…（首页按天看人时右滑双打）。
 *  “你们都想一起打”里约这个时间时还带球馆和时间：&venue=<id>&venue_name=…&starts=<ISO>&ends=<ISO> */
function asked() {
  const q = new URLSearchParams(location.search);
  const id = q.get('invite')?.match(/^[0-9a-f-]{36}$/)?.[0];
  const gender = q.get('gender');
  const venue = q.get('venue')?.match(/^[0-9a-f-]{36}$/)?.[0];
  const court: Court | undefined = venue ? { id: venue, name: q.get('venue_name') ?? '', city: '', time_zone_id: null } : undefined;
  const starts = new Date(q.get('starts') ?? '');
  const ends = new Date(q.get('ends') ?? '');
  const minutes = (d: Date) => d.getHours() * 60 + d.getMinutes();
  const timed = !isNaN(starts.getTime()) && !isNaN(ends.getTime()) && ends > starts;
  return {
    mode: (q.get('mode') === 'singles' ? 'singles' : 'doubles') as Mode,
    invitee: id ? { id, name: q.get('name') ?? '', gender: (gender === 'male' || gender === 'female' ? gender : null) as Gender | null } : undefined,
    slot: timed
      ? { court, date: new Intl.DateTimeFormat('en-CA').format(starts), from: minutes(starts), to: starts.toDateString() === ends.toDateString() ? minutes(ends) : 24 * 60 - 30 }
      : court ? { court, date: today(zone(), 1), from: 19 * 60, to: 21 * 60 } : undefined,
  };
}

export function NewRoom({ profile }: { profile: Profile }) {
  const [start] = useState(asked);
  const invitee = start.invitee;
  // 约的人的性别和是不是好友：以资料卡为准，看不到资料卡时用地址里带的
  const { data: card } = useLive<PlayerCard | null>(invitee ? 'player_card' : '', { args: { p_user: invitee?.id }, every: 600_000 });
  const partner = card?.gender ?? invitee?.gender ?? null;
  const [mode, setMode] = useState<Mode>(start.mode);
  const [chosen, setChosen] = useState<PlayEvent>('any');
  // 能选的项目跟着模式和两人的性别变：选的不在里面时用第一个（单打同性就是男单 / 女单）
  const options = eventOptions(mode, profile.gender, invitee ? partner : null);
  const playEvent = options.includes(chosen) ? chosen : options[0];
  const level = eventLevel(profile, playEvent);
  const [isPublic, setPublic] = useState(true);
  const [slot, setSlot] = useState<Slot>(() => start.slot ?? { date: today(zone(), 1), from: 19 * 60, to: 21 * 60 });
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
      p_gender: playEvent === 'male' || playEvent === 'female' ? playEvent : null, p_mixed: playEvent === 'mixed',
    });
    if (error) {
      setBusy(false);
      return setError(problem(error));
    }
    // 只有好友会收到邀请（服务器会跳过不是好友的人）
    if (invitee) await supabase!.rpc('invite_to_room', { p_room: data, p_users: [invitee.id] });
    setBusy(false);
    navigate(`/rooms/${data}/`, true);
  }

  const levels = Array.from({ length: 9 }, (_, i) => i + 1);
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader back="/games/" title={t('Start a game')}>
        {t('You have the court; Badie helps fill it. You count as one of the players.')}
      </PageHeader>

      <form onSubmit={submit} noValidate className="grid gap-6">
        {/* 好友收到邀请；不是好友的，公开到附近时也能看到、报名 */}
        {invitee && (card?.relationship === 'friend' || isPublic) && (
          <Notice icon="userPlus" tint="lavender">
            {card?.relationship === 'friend'
              ? t('{name} gets an invite once it’s posted.', { name: card.nickname })
              : t('Players nearby can join once it’s posted, {name} included.', { name: card?.nickname ?? invitee.name })}
          </Notice>
        )}

        <FormatPicker value={mode} onChange={setMode} />

        <SlotFields slot={slot} onChange={setSlot} />

        <EventField mode={mode} gender={profile.gender} partner={invitee ? partner : null} value={playEvent} onChange={(value) => {
          // 换了项目，自己的等级可能跟着换算：范围重新围着自己
          const own = eventLevel(profile, value);
          setChosen(value);
          setMin(Math.max(1, own - 1));
          setMax(Math.min(9, own + 1));
        }} />

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
