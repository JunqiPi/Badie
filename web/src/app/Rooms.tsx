import { useEffect, useState } from 'react';
import { useArea } from './area';
import { RoomCard } from './cards';
import { km } from './Courts';
import { AreaPrompt } from './Home';
import { t } from './i18n';
import { Icon } from './icons';
import { Empty, IconButton, IconTile, ScreenHeader, SectionTitle, Tag } from './kit';
import { Link } from './router';
import { supabase, useLive, type RoomSummary, type RoomTag } from './supabase';
import { day, hours } from './time';
import { Skeleton } from './ui';

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
    <span className="flex flex-wrap gap-1.5">
      <Tag icon={r.mode === 'doubles' ? 'users' : 'user'} tint="lavender">{r.mode === 'doubles' ? t('Doubles') : t('Singles')}</Tag>
      <Tag icon="level" tint="lime">{t('Lv.{min}–{max}', { min: r.level_min, max: r.level_max })}</Tag>
      {r.visibility === 'private' && <Tag icon="lock" tint="butter">{t('Private room')}</Tag>}
      {r.tags.map((tag) => <Tag key={tag} tint="mint">{tagText(tag)}</Tag>)}
    </span>
  );
}

/** 附近的公开球局（有场地缺人）+ 我的房间 */
export function Rooms() {
  const { data: mine } = useLive<RoomSummary[]>('my_rooms', { every: 30_000 });
  const area = useArea();
  const [nearby, setNearby] = useState<RoomSummary[]>();

  useEffect(() => {
    if (!area) return;
    setNearby(undefined);
    supabase!.rpc('rooms_near', { lat: area.lat, lng: area.lon, radius_km: 30 })
      // 自己在里面的已经列在上面了
      .then(({ data }) => setNearby(((data ?? []) as RoomSummary[]).filter((r) => !r.my_status)));
  }, [area?.lat, area?.lon]);

  return (
    <div className="grid gap-6">
      <ScreenHeader title={t('Nearby games')} back="/games/">
        <IconButton icon="plus" label={t('Start a game')} to="/rooms/new/" />
      </ScreenHeader>

      <Link to="/rooms/new/" className="sticker lift flex items-center gap-3 bg-peach p-4 text-on-accent">
        <IconTile icon="court" tint="surface" />
        <span className="min-w-0 flex-1">
          <span className="block text-headline">{t('Have a court, need players?')}</span>
          <span className="block text-footnote">{t('Post the time and level. Players nearby join in one tap, and you start the game when it’s full.')}</span>
        </span>
        <Icon name="chevronRight" className="size-4" />
      </Link>

      {mine && mine.length > 0 && (
        <section aria-labelledby="mine" className="grid gap-2">
          <SectionTitle id="mine" title={t('My rooms')} detail={t('{n} active', { n: mine.length })} />
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{mine.map((r) => <RoomCard key={r.id} room={r} wide />)}</div>
        </section>
      )}

      <section aria-labelledby="nearby" className="grid gap-2">
        <SectionTitle id="nearby" title={area?.label ? t('Open games near {place}', { place: area.label }) : t('Open games near you')} detail={nearby ? String(nearby.length) : undefined} />
        {!area && <AreaPrompt tint="peach" />}
        {area && !nearby && <Skeleton className="h-44" />}
        {nearby?.length === 0 && (
          <Empty icon="court" tint="peach" title={t('No open games within {distance} right now', { distance: km(30_000) })} action={{ label: t('Start a game'), to: '/rooms/new/' }}>
            {t('Post one if you have a court, or ask us to find you a match.')}
          </Empty>
        )}
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{nearby?.map((r) => <RoomCard key={r.id} room={r} wide />)}</div>
      </section>
    </div>
  );
}
