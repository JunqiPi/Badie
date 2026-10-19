import { useEffect, useState } from 'react';
import { useArea } from './area';
import { km } from './Courts';
import { AreaPrompt } from './Home';
import { t } from './i18n';
import { Icon } from './icons';
import { Empty, IconButton, IconTile, Notice, ScreenHeader, SectionTitle, Tag } from './kit';
import { Link } from './router';
import { supabase, useLive, type GroupSummary, type MyGroups, type Schedule } from './supabase';
import { clock, dayName, hours, weekday } from './time';
import { Skeleton } from './ui';

export const scheduleText = (s: Schedule) => `${t('Every {day}', { day: weekday(s.weekday) })} · ${clock(s.start)} – ${clock(s.end)}`;

export const activityText = (a: GroupSummary['activity']) =>
  a.sessions === 0
    ? t('No sessions in the last 30 days')
    : `${t('{n} session in the last 30 days|{n} sessions in the last 30 days', { n: a.sessions })} · ${t('about {n} player each|about {n} players each', { n: Math.round(a.average) })}`;

/** 球群卡片（iOS 的 GroupCard）：图标、群名、球馆、每周时间、水平、最近活跃度 */
export function GroupCard({ group: g }: { group: GroupSummary }) {
  return (
    <Link to={`/groups/${g.id}/`} className="sticker lift grid content-start gap-3 p-4">
      <span className="flex items-start gap-3">
        <IconTile icon="group" tint="lavender" size="lg" />
        <span className="min-w-0 flex-1">
          <span className="block text-headline">{g.name}</span>
          <span className="block truncate text-footnote text-ink-secondary">{g.venue.name}, {g.venue.city}</span>
        </span>
        {g.my_role === 'pending' ? <Tag tint="peach">{t('Requested')}</Tag> : g.my_role && <Tag icon="check" tint="mint">{t('Joined')}</Tag>}
      </span>
      <span className="flex flex-wrap gap-1.5">
        {g.schedules.map((sc, i) => <Tag key={i} icon="calendar">{scheduleText(sc)}</Tag>)}
        <Tag icon="level" tint="lime">{t('Lv.{min}–{max}', { min: g.level_min, max: g.level_max })}</Tag>
        {g.join_policy === 'approval' && <Tag icon="lock" tint="lavender">{t('Organizer approves')}</Tag>}
      </span>
      <span className="flex items-center gap-1.5 text-footnote text-ink-secondary"><Icon name="bolt" className="size-3.5" />{activityText(g.activity)}</span>
    </Link>
  );
}

/** 球群 · 固定局（iOS 的 GroupsView）：我加入的、我报名的场次、附近的球群 */
export function Groups() {
  const { data: mine } = useLive<MyGroups>('my_groups', { every: 60_000 });
  const area = useArea();
  const [nearby, setNearby] = useState<GroupSummary[]>();

  useEffect(() => {
    if (!area) return;
    setNearby(undefined);
    supabase!.rpc('groups_near', { lat: area.lat, lng: area.lon, radius_km: 30 }).then(({ data }) => setNearby((data ?? []) as GroupSummary[]));
  }, [area?.lat, area?.lon]);

  const joined = new Set(mine?.groups.map((g) => g.id));
  const others = nearby?.filter((g) => !joined.has(g.id));

  return (
    <div className="grid gap-6">
      <ScreenHeader title={t('Regular games · Groups')} back="/games/">
        <IconButton icon="plus" label={t('Start a group')} to="/groups/new/" />
      </ScreenHeader>

      <Notice icon="calendarCheck" tint="sky" action={{ label: t('Have a code?'), to: '/join/' }}>
        {t('Same time and venue every week. Sign up in one tap; join the waitlist automatically when full')}
      </Notice>

      {mine && mine.sessions.length > 0 && (
        <section aria-labelledby="next" className="grid gap-2">
          <SectionTitle id="next" title={t('Your next sessions')} detail={t('Leaving within 2 hours of start counts as a late cancellation')} />
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {mine.sessions.map((s) => (
              <Link key={s.id} to={`/groups/${s.group_id}/`} className={`sticker lift grid gap-1 p-4 ${s.waitlisted ? 'bg-butter/60' : 'bg-lime/45'}`}>
                <span className="flex items-center gap-1.5 text-footnote font-bold text-ink-secondary"><Icon name="group" className="size-4" />{s.group}</span>
                <span className="text-headline">{dayName(s.starts_at, s.tz)} · {hours(s.starts_at, s.ends_at, s.tz)}</span>
                <span className="text-footnote font-bold">{s.waitlisted ? t('On the waitlist') : t('Signed up ✓')} · {s.venue}</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      <section aria-labelledby="mine" className="grid gap-2">
        <SectionTitle id="mine" title={t('Groups I’m in')} detail={mine ? String(mine.groups.length) : undefined} />
        {!mine && <Skeleton className="h-32" />}
        {mine && mine.groups.length === 0 && (
          <Empty icon="group" tint="lavender" title={t('No groups yet')} action={{ label: t('Start a group'), to: '/groups/new/' }}>
            {t('Find one nearby, enter a group number someone shared, or start your own.')}
          </Empty>
        )}
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{mine?.groups.map((g) => <GroupCard key={g.id} group={g} />)}</div>
      </section>

      <section aria-labelledby="nearby" className="grid gap-2">
        <SectionTitle id="nearby" title={area?.label ? t('Groups near {place}', { place: area.label }) : t('Nearby groups')} detail={others ? String(others.length) : undefined} />
        {!area && <AreaPrompt tint="lavender" />}
        {area && !others && <Skeleton className="h-32" />}
        {others?.length === 0 && (
          <Empty icon="group" tint="sky" title={t('No groups within {distance} yet', { distance: km(30_000) })} action={{ label: t('Start a group'), to: '/groups/new/' }}>
            {t('Start one at the court you play at.')}
          </Empty>
        )}
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{others?.map((g) => <GroupCard key={g.id} group={g} />)}</div>
      </section>
    </div>
  );
}
