import { useState, type SubmitEvent } from 'react';
import { km } from './Courts';
import { t } from './i18n';
import { AreaPicker, type Centre } from './pickers';
import { Link, navigate } from './router';
import { supabase, useLive, type GroupSummary, type MyGroups, type Schedule } from './supabase';
import { clock, day, hours, weekday } from './time';
import { Button, EmptyState, Field, PageHeader, Skeleton } from './ui';

export const scheduleText = (s: Schedule) => `${t('Every {day}', { day: weekday(s.weekday) })} · ${clock(s.start)} – ${clock(s.end)}`;

export const activityText = (a: GroupSummary['activity']) =>
  a.sessions === 0
    ? t('No sessions in the last 30 days')
    : `${t('{n} session in the last 30 days|{n} sessions in the last 30 days', { n: a.sessions })} · ${t('about {n} player each|about {n} players each', { n: Math.round(a.average) })}`;

export function GroupCard({ group: g }: { group: GroupSummary }) {
  return (
    <Link to={`/groups/${g.id}/`} className="sticker lift grid gap-2 p-5">
      <span className="flex flex-wrap items-start justify-between gap-2">
        <span className="text-lg font-black">{g.name}</span>
        {g.my_role === 'pending' ? <span className="chip bg-peach">{t('Requested')}</span> : g.my_role && <span className="chip bg-mint">{t('Joined')}</span>}
      </span>
      <span className="text-ink-secondary">{g.venue.name}, {g.venue.city}</span>
      <span className="font-bold">{g.schedules.map(scheduleText).join(' · ')}</span>
      <span className="flex flex-wrap gap-2">
        <span className="chip bg-sky">{t('Level {min}–{max}', { min: g.level_min, max: g.level_max })}</span>
        {g.join_policy === 'approval' && <span className="chip bg-lavender">{t('Organizer approves')}</span>}
      </span>
      <span className="text-sm text-ink-tertiary">{activityText(g.activity)}</span>
    </Link>
  );
}

export function Groups() {
  const { data: mine } = useLive<MyGroups>('my_groups', { every: 60_000 });
  const [centre, setCentre] = useState<Centre>();
  const [nearby, setNearby] = useState<GroupSummary[]>();
  const [code, setCode] = useState('');
  const [codeError, setCodeError] = useState<string>();

  async function pick(next: Centre) {
    setCentre(next);
    setNearby(undefined);
    const { data } = await supabase!.rpc('groups_near', { lat: next.lat, lng: next.lon, radius_km: 30 });
    setNearby((data ?? []) as GroupSummary[]);
  }

  async function find(event: SubmitEvent) {
    event.preventDefault();
    const { data } = await supabase!.rpc('find_group', { p_code: code });
    if (data) navigate(`/groups/${data}/`);
    else setCodeError(t('No group with that number. Check the 6 characters.'));
  }

  return (
    <div>
      <PageHeader back="/games/" title={t('Groups')}>
        {t('Regular weekly sessions at one court. Sign up in one tap; if it’s full you’re on the waitlist and move up automatically.')}
      </PageHeader>

      <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
        <div className="grid gap-10">
          {mine && mine.sessions.length > 0 && (
            <section aria-labelledby="next" className="grid gap-3">
              <h2 id="next" className="text-xl font-black">{t('Your next sessions')}</h2>
              {mine.sessions.map((s) => (
                <Link key={s.id} to={`/groups/${s.group_id}/`} className="sticker lift flex flex-wrap items-center justify-between gap-3 p-4">
                  <span className="min-w-0">
                    <span className="block font-black">{day(s.starts_at, s.tz)} · {hours(s.starts_at, s.ends_at, s.tz)}</span>
                    <span className="block truncate text-sm text-ink-secondary">{t('{group} at {venue}', { group: s.group, venue: s.venue })}</span>
                  </span>
                  <span className={`chip ${s.waitlisted ? 'bg-peach' : 'bg-mint'}`}>{s.waitlisted ? t('Waitlist') : t('Going')}</span>
                </Link>
              ))}
            </section>
          )}

          <section aria-labelledby="mine" className="grid gap-3">
            <h2 id="mine" className="text-xl font-black">{t('Your groups')}</h2>
            {!mine && <Skeleton className="h-32" />}
            {mine && mine.groups.length === 0 && (
              <EmptyState title={t('No groups yet')}>{t('Find one nearby, enter a group number someone shared, or start your own.')}</EmptyState>
            )}
            {mine?.groups.map((g) => <GroupCard key={g.id} group={g} />)}
          </section>

          <section aria-labelledby="nearby" className="grid gap-3">
            <h2 id="nearby" className="text-xl font-black">{centre?.label ? t('Groups near {place}', { place: centre.label }) : t('Groups near you')}</h2>
            <div className="flex flex-wrap items-center gap-3"><AreaPicker onPick={pick} /></div>
            {centre && !nearby && <Skeleton className="h-32" />}
            {nearby?.length === 0 && <EmptyState title={t('No groups within {distance} yet', { distance: km(30_000) })}>{t('Start one at the court you play at.')}</EmptyState>}
            {nearby?.map((g) => <GroupCard key={g.id} group={g} />)}
          </section>
        </div>

        <aside className="grid gap-4 lg:sticky lg:top-6">
          <form onSubmit={find} noValidate className="tile grid gap-3 bg-surface p-5">
            <Field label={t('Have a group number?')} error={codeError}>
              {(props) => (
                <input {...props} value={code} maxLength={6} autoCapitalize="characters" autoComplete="off" spellCheck={false}
                       onChange={(e) => { setCode(e.target.value.toUpperCase()); setCodeError(undefined); }}
                       placeholder="ABC234" className="field font-mono tracking-[0.3em] uppercase" />
              )}
            </Field>
            <Button disabled={code.trim().length !== 6} className="justify-self-start">{t('Find group')}</Button>
          </form>
          <div className="tile grid gap-3 bg-lavender p-5 text-on-accent">
            <p className="font-black">{t('Run a regular session?')}</p>
            <p className="font-medium">{t('Bring sign-ups and the waitlist out of the group chat.')}</p>
            <Link to="/groups/new/" className="button button-quiet justify-self-start">{t('Start a group')}</Link>
          </div>
        </aside>
      </div>
    </div>
  );
}
