import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react';
import { setArea, useArea } from './area';
import { currentLocale, t, useLocale } from './i18n';
import { Icon } from './icons';
import { Divider, Empty, IconTile, Tag } from './kit';
import { AreaPicker } from './pickers';
import { navigate } from './router';
import { signInFirst } from './Shell';
import { supabase, type NearbyVenue, type Venue } from './supabase';
import { Button, Skeleton, toast } from './ui';

export const km = (metres: number) =>
  metres < 1000
    ? new Intl.NumberFormat(currentLocale(), { style: 'unit', unit: 'meter', maximumFractionDigits: 0 }).format(metres)
    : new Intl.NumberFormat(currentLocale(), { style: 'unit', unit: 'kilometer', maximumFractionDigits: 1 }).format(metres / 1000);
export const money = (amount: number, country: string) =>
  amount === 0
    ? t('Free')
    : new Intl.NumberFormat(currentLocale(), { style: 'currency', currency: { US: 'USD', GB: 'GBP', HK: 'HKD', SG: 'SGD', MY: 'MYR', TW: 'TWD', JP: 'JPY' }[country] ?? 'USD', maximumFractionDigits: 0 }).format(amount);
export const address = (v: Venue) => [[v.street, v.unit].filter(Boolean).join(', '), v.city, [v.region, v.postal_code].filter(Boolean).join(' ')].filter(Boolean).join(', ');

const CourtMap = lazy(() => import('./CourtMap'));

/** 球馆页上方“我附近的球馆”（静态页面里的 React 岛，iOS 的 CourtsView）：地图 + 列表 + 详情，登录后可以收藏 */
export function Courts() {
  useLocale();
  const area = useArea();
  const [userId, setUserId] = useState<string>();
  const [radius, setRadius] = useState(15);
  const [results, setResults] = useState<NearbyVenue[]>();
  const [selected, setSelected] = useState<Venue>();
  const [favorites, setFavorites] = useState<Set<string>>(new Set());
  const detail = useRef<HTMLElement>(null);

  useEffect(() => {
    supabase?.auth.getSession().then(({ data }) => setUserId(data.session?.user.id));
  }, []);

  useEffect(() => {
    if (!userId) return;
    supabase!.from('favorite_venues').select('venue_id').then(({ data }) => setFavorites(new Set(data?.map((f) => f.venue_id))));
  }, [userId]);

  useEffect(() => {
    if (!area) return;
    setResults(undefined);
    supabase!
      .rpc('venues_near', { lat: area.lat, lng: area.lon, radius_km: radius, max_results: 100 })
      .then(({ data, error }) => {
        if (error) toast(t('Couldn’t load courts. Check your connection.'), 'error');
        const list = ((data ?? []) as NearbyVenue[]).filter((r) => !r.venue.location_approximate);
        setResults(list);
        const asked = new URLSearchParams(location.search).get('venue');
        setSelected(list.find((r) => r.venue.id === asked)?.venue ?? list[0]?.venue);
      });
  }, [area?.lat, area?.lon, radius]);

  const pins = useMemo(() => (results ?? []).map(({ venue }) => ({ id: venue.id, name: venue.name, lat: venue.lat, lon: venue.lon })), [results]);

  function select(venue: Venue, scroll = true) {
    setSelected(venue);
    // 窄屏上详情在列表下面，点了要带用户过去
    if (scroll && !matchMedia('(min-width: 1024px)').matches) requestAnimationFrame(() => detail.current?.scrollIntoView({ block: 'start' }));
  }

  // 先改界面再请求，失败了改回来
  async function toggleFavorite(venue: Venue) {
    if (!userId) return navigate(signInFirst('/courts/'));
    const was = favorites.has(venue.id);
    const next = new Set(favorites);
    if (was) next.delete(venue.id);
    else next.add(venue.id);
    setFavorites(next);
    const { error } = was
      ? await supabase!.from('favorite_venues').delete().eq('venue_id', venue.id)
      : await supabase!.from('favorite_venues').insert({ user_id: userId, venue_id: venue.id });
    if (error) {
      setFavorites(favorites);
      toast(t('Couldn’t update your courts. Try again.'), 'error');
    }
  }

  async function confirm(venue: Venue) {
    if (!userId) return navigate(signInFirst('/courts/'));
    const { data, error } = await supabase!.rpc('confirm_venue', { target: venue.id });
    if (error) return toast(t('Couldn’t confirm right now. Try again later.'), 'error');
    toast(t('Thanks! Your confirmation helps other players.'));
    setSelected(data as Venue);
  }

  return (
    <section aria-labelledby="near" className="grid grid-cols-1 gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="near" className="text-title2">{area?.label ? t('Courts near {place}', { place: area.label }) : t('Courts near you')}</h2>
        {area && (
          <div className="flex gap-1.5" role="group" aria-label={t('Distance')}>
            {[5, 15, 30].map((r) => (
              <button key={r} type="button" onClick={() => setRadius(r)} aria-pressed={radius === r} className="toggle">{km(r * 1000)}</button>
            ))}
          </div>
        )}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <AreaPicker onPick={setArea} />
      </div>

      {!area ? (
        <Empty icon="map" tint="sky" title={t('Find courts around you')}>{t('Use your location, or search a city to see the courts nearby.')}</Empty>
      ) : (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
          <div className="grid grid-cols-1 gap-4">
            <div className="sticker h-64 overflow-hidden p-0 sm:h-80 lg:h-[26rem]">
              <Suspense fallback={<div className="skeleton h-full rounded-none!" />}>
                <CourtMap centre={area} pins={pins} selected={selected?.id} onSelect={(id) => { const v = results?.find((r) => r.venue.id === id)?.venue; if (v) select(v); }} />
              </Suspense>
            </div>
            {selected && (
              <VenueDetail ref={detail} venue={selected} favorite={favorites.has(selected.id)} onFavorite={() => toggleFavorite(selected)} onConfirm={() => confirm(selected)} />
            )}
          </div>

          <div className="grid grid-cols-1 gap-2">
            <p className="text-headline">
              {results ? t('{n} venues', { n: results.length }) : ' '}
              <span className="ml-2 text-footnote font-bold text-ink-secondary">{t('within {distance}', { distance: km(radius * 1000) })}</span>
            </p>
            <ul className="sticker grid grid-cols-1 p-2" aria-label={t('Courts')} aria-busy={results === undefined}>
              {results === undefined && [0, 1, 2, 3].map((i) => <li key={i}><Skeleton className="m-2 h-14" /></li>)}
              {results?.length === 0 && (
                <li className="p-3 text-footnote text-ink-secondary">{t('Try a wider distance, or add a court you play at from the iPhone app.')}</li>
              )}
              {results?.map(({ venue, distance_m }, i) => (
                <li key={venue.id}>
                  {i > 0 && <div className="mx-2"><Divider /></div>}
                  <button
                    type="button"
                    onClick={() => select(venue)}
                    aria-current={selected?.id === venue.id}
                    className="press flex w-full items-center gap-3 rounded-[14px] p-2.5 text-left hover:bg-surface-muted/70 aria-[current=true]:bg-lime/35"
                  >
                    <IconTile icon="pin" tint="sky" />
                    <span className="min-w-0 flex-1">
                      <span className="flex items-baseline gap-2">
                        <span className="min-w-0 flex-1 truncate font-bold">{venue.name}</span>
                        {favorites.has(venue.id) && <Icon name="heart" className="size-3.5 text-danger" />}
                        <span className="shrink-0 text-footnote font-bold text-ink-secondary tabular-nums">{km(distance_m)}</span>
                      </span>
                      <span className="block truncate text-footnote text-ink-secondary">{address(venue)}</span>
                      {venue.status !== 'unconfirmed' && <span className="mt-1 inline-flex"><Tag icon="verified" tint="mint">{venue.status === 'verified' ? t('Verified') : t('Confirmed by players')}</Tag></span>}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </section>
  );
}

/** 选中的球馆：类型、场地数、价格、开放时间、导航、收藏 */
function VenueDetail({ ref, venue, favorite, onFavorite, onConfirm }: {
  ref: React.Ref<HTMLElement>;
  venue: Venue;
  favorite: boolean;
  onFavorite: () => void;
  onConfirm: () => void;
}) {
  return (
    <section ref={ref} key={venue.id} className="sticker animate-enter grid scroll-mt-20 gap-4 p-5" aria-label={venue.name}>
      <div className="flex items-start gap-3">
        <IconTile icon="pin" tint="sky" size="lg" />
        <div className="min-w-0 flex-1">
          <h3 className="text-title3">{venue.name}</h3>
          <p className="text-footnote text-ink-secondary">{address(venue)}</p>
        </div>
        <button type="button" onClick={onFavorite} aria-pressed={favorite} aria-label={favorite ? t('In my courts') : t('Add to my courts')}
                className="press grid size-11 shrink-0 place-items-center rounded-[14px] border-2 border-stroke bg-surface shadow-low aria-pressed:bg-pink aria-pressed:text-on-accent">
          <Icon name={favorite ? 'heart' : 'heartOutline'} className="size-5" />
        </button>
      </div>
      <ul className="flex flex-wrap gap-2">
        <li><Tag icon="verified" tint={venue.status === 'unconfirmed' ? 'muted' : 'mint'}>{venue.status === 'verified' ? t('Verified') : venue.status === 'confirmed' ? t('Confirmed by players') : t('Not yet confirmed')}</Tag></li>
        {venue.kind && venue.kind !== 'dedicated' && <li><Tag tint="lavender">{t(kindLabel[venue.kind])}</Tag></li>}
        {venue.court_count && <li><Tag tint="sky">{t('{n} court|{n} courts', { n: venue.court_count })}</Tag></li>}
        {venue.pricing?.perPerson !== undefined && <li><Tag tint="butter">{t('Drop-in {price}', { price: money(venue.pricing.perPerson, venue.country_code) })}</Tag></li>}
        {venue.pricing?.perCourtHour && <li><Tag tint="peach">{t('Court {price}/h', { price: money(venue.pricing.perCourtHour, venue.country_code) })}</Tag></li>}
      </ul>
      {venue.play_times && (
        <p className="flex items-start gap-2 text-subhead font-bold"><Icon name="clock" className="mt-0.5 size-4" />{venue.play_times}</p>
      )}
      <div className="flex flex-wrap gap-2">
        <a className="button" href={`https://maps.apple.com/?q=${encodeURIComponent(venue.name)}&ll=${venue.lat},${venue.lon}`}><Icon name="locate" className="size-4" />{t('Directions')}</a>
        {venue.website && <a className="button button-quiet" href={venue.website} rel="noopener nofollow"><Icon name="globe" className="size-4" />{t('Website')}</a>}
        {venue.status !== 'verified' && <Button variant="quiet" onClick={onConfirm}>{t('I’ve played here')}</Button>}
      </div>
      {venue.attribution && <p className="text-caption text-ink-tertiary">{venue.attribution}</p>}
    </section>
  );
}

const kindLabel: Record<NonNullable<Venue['kind']>, string> = {
  dedicated: 'Badminton center',
  multi_sport: 'Multi-sport center',
  rec_center: 'Community center',
  school: 'School gym',
  community_hall: 'Community hall',
};
