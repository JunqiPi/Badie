import { useState, type SubmitEvent } from 'react';
import { km } from './Courts';
import { t } from './i18n';
import { AreaPicker, type Centre } from './pickers';
import { Link, navigate } from './router';
import { supabase, useLive, problem, type RoomSummary, type RoomTag } from './supabase';
import { day, hours } from './time';
import { Button, EmptyState, Field, PageHeader, Skeleton } from './ui';

export const tagText = (tag: RoomTag) =>
  ({
    beginner_friendly: t('Beginner-friendly'),
    casual: t('Casual'),
    competitive: t('Competitive'),
    women_friendly: t('Women-friendly'),
    coaching: t('Coaching available'),
  })[tag];

/** 时间按球馆当地时间；私密局可以还没定 */
export const roomWhen = (r: RoomSummary) =>
  r.starts_at && r.ends_at ? `${day(r.starts_at, r.venue?.tz)} · ${hours(r.starts_at, r.ends_at, r.venue?.tz)}` : t('Time not set yet');

export function RoomChips({ room: r }: { room: RoomSummary }) {
  return (
    <span className="flex flex-wrap gap-2">
      <span className="chip bg-sky">{r.mode === 'doubles' ? t('Doubles') : t('Singles')} · {t('Level {min}–{max}', { min: r.level_min, max: r.level_max })}</span>
      {r.visibility === 'private' && <span className="chip bg-lavender">{t('Private room')}</span>}
      {r.tags.map((tag) => <span key={tag} className="chip bg-surface-muted text-ink">{tagText(tag)}</span>)}
    </span>
  );
}

function RoomCard({ room: r }: { room: RoomSummary }) {
  const open = r.capacity - r.going;
  return (
    <Link to={`/rooms/${r.id}/`} className="sticker lift grid gap-2 p-5">
      <span className="flex flex-wrap items-start justify-between gap-2">
        <span className="text-lg font-black">{roomWhen(r)}</span>
        {r.my_status === 'owner' ? <span className="chip bg-butter">{t('Hosting')}</span>
          : r.my_status === 'member' ? <span className="chip bg-mint">{t('Going')}</span>
          : r.my_status === 'waitlisted' ? <span className="chip bg-peach">{t('Waitlist')}</span>
          : r.my_status === 'invited' ? <span className="chip bg-pink">{t('Invited')}</span>
          : null}
      </span>
      <span className="text-ink-secondary">{r.venue ? `${r.venue.name}, ${r.venue.city}` : t('Court not set yet')}</span>
      <span className="font-bold tabular-nums">
        {open > 0 ? t('{n} spot left|{n} spots left', { n: open }) : r.waitlist > 0 ? t('Full · {n} waiting', { n: r.waitlist }) : t('Full')}
        <span className="font-semibold text-ink-tertiary"> · {t('hosted by {name}', { name: r.owner.nickname })}</span>
      </span>
      <RoomChips room={r} />
      {r.note && <span className="text-sm text-ink-secondary">{r.note}</span>}
    </Link>
  );
}

export function Rooms() {
  const { data: mine, refresh } = useLive<RoomSummary[]>('my_rooms', { every: 30_000 });
  const [centre, setCentre] = useState<Centre>();
  const [nearby, setNearby] = useState<RoomSummary[]>();
  const [code, setCode] = useState('');
  const [codeError, setCodeError] = useState<string>();
  const [joining, setJoining] = useState(false);

  async function pick(next: Centre) {
    setCentre(next);
    setNearby(undefined);
    const { data } = await supabase!.rpc('rooms_near', { lat: next.lat, lng: next.lon, radius_km: 30 });
    // 自己在里面的已经列在上面了
    setNearby(((data ?? []) as RoomSummary[]).filter((r) => !r.my_status));
  }

  // 房间码和群号在同一个框里：先找球局，找不到再找球群
  async function join(event: SubmitEvent) {
    event.preventDefault();
    setJoining(true);
    const { data, error } = await supabase!.rpc('join_room_code', { p_code: code });
    if (!error) return navigate(`/rooms/${data}/`);
    if (error.message === 'room_not_found') {
      const { data: group } = await supabase!.rpc('find_group', { p_code: code });
      if (group) return navigate(`/groups/${group}/`);
    }
    setJoining(false);
    setCodeError(problem(error));
    refresh();
  }

  return (
    <div>
      <PageHeader back="/games/" title={t('Nearby games')}>
        {t('Someone has a court and needs players. Join one at your level, or post your own when you’re short a player or two.')}
      </PageHeader>

      <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
        <div className="grid gap-10">
          {mine && mine.length > 0 && (
            <section aria-labelledby="mine" className="grid gap-3">
              <h2 id="mine" className="text-xl font-black">{t('Your open games')}</h2>
              {mine.map((r) => <RoomCard key={r.id} room={r} />)}
            </section>
          )}

          <section aria-labelledby="nearby" className="grid gap-3">
            <h2 id="nearby" className="text-xl font-black">{centre?.label ? t('Open games near {place}', { place: centre.label }) : t('Open games near you')}</h2>
            <div className="flex flex-wrap items-center gap-3"><AreaPicker onPick={pick} /></div>
            {centre && !nearby && <Skeleton className="h-32" />}
            {nearby?.length === 0 && (
              <EmptyState title={t('No open games within {distance} right now', { distance: km(30_000) })}>
                {t('Post one if you have a court, or ask us to find you a match.')}
              </EmptyState>
            )}
            {nearby?.map((r) => <RoomCard key={r.id} room={r} />)}
          </section>
        </div>

        <aside className="grid gap-4 lg:sticky lg:top-6">
          <div className="tile grid gap-3 bg-lavender p-5 text-on-accent">
            <p className="font-black">{t('Have a court, need players?')}</p>
            <p className="font-medium">{t('Post the time and level. Players nearby join in one tap, and you start the game when it’s full.')}</p>
            <Link to="/rooms/new/" className="button button-quiet justify-self-start">{t('Post a game')}</Link>
          </div>
          <form onSubmit={join} noValidate className="tile grid gap-3 bg-surface p-5">
            <Field label={t('Have a code?')} hint={t('A 6-character room code or group number from a friend.')} error={codeError}>
              {(props) => (
                <input {...props} value={code} maxLength={6} autoCapitalize="characters" autoComplete="off" spellCheck={false}
                       onChange={(e) => { setCode(e.target.value.toUpperCase()); setCodeError(undefined); }}
                       placeholder="ABC234" className="field font-mono tracking-[0.3em] uppercase" />
              )}
            </Field>
            <Button busy={joining} disabled={code.trim().length !== 6} className="justify-self-start">{t('Join')}</Button>
          </form>
        </aside>
      </div>
    </div>
  );
}
