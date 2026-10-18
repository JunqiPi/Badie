import { useEffect, useRef, useState } from 'react';
import { currentLocale, t, useLocale } from './i18n';
import { Icon } from './icons';
import { AreaPicker, type Centre } from './pickers';
import { navigate } from './router';
import { signInFirst } from './Shell';
import { supabase, type NearbyVenue, type Venue } from './supabase';
import { Button, EmptyState, PageHeader, Skeleton, toast } from './ui';

export const km = (metres: number) =>
  metres < 1000
    ? new Intl.NumberFormat(currentLocale(), { style: 'unit', unit: 'meter', maximumFractionDigits: 0 }).format(metres)
    : new Intl.NumberFormat(currentLocale(), { style: 'unit', unit: 'kilometer', maximumFractionDigits: 1 }).format(metres / 1000);
export const money = (amount: number, country: string) =>
  amount === 0
    ? t('Free')
    : new Intl.NumberFormat(currentLocale(), { style: 'currency', currency: { US: 'USD', GB: 'GBP', HK: 'HKD', SG: 'SGD', MY: 'MYR', TW: 'TWD', JP: 'JPY' }[country] ?? 'USD', maximumFractionDigits: 0 }).format(amount);
export const address = (v: Venue) => [[v.street, v.unit].filter(Boolean).join(', '), v.city, [v.region, v.postal_code].filter(Boolean).join(' ')].filter(Boolean).join(', ');

/** 球馆页上方“我附近的球馆”（静态页面里的 React 岛）：定位或搜城市，列表 + 详情，登录后可以收藏 */
export function Courts() {
  useLocale();
  const [userId, setUserId] = useState<string>();
  useEffect(() => {
    supabase?.auth.getSession().then(({ data }) => setUserId(data.session?.user.id));
  }, []);
  const [centre, setCentre] = useState<Centre>();
  const [radius, setRadius] = useState(15);
  const [results, setResults] = useState<NearbyVenue[]>();
  const [selected, setSelected] = useState<Venue>();
  const [favorites, setFavorites] = useState<Set<string>>(new Set());
  const detail = useRef<HTMLElement>(null);

  useEffect(() => {
    if (!userId) return;
    supabase!.from('favorite_venues').select('venue_id').then(({ data }) => setFavorites(new Set(data?.map((f) => f.venue_id))));
  }, [userId]);

  useEffect(() => {
    if (!centre) return;
    setResults(undefined);
    supabase!
      .rpc('venues_near', { lat: centre.lat, lng: centre.lon, radius_km: radius, max_results: 100 })
      .then(({ data, error }) => {
        if (error) toast(t('Couldn’t load courts. Check your connection.'), 'error');
        const list = ((data ?? []) as NearbyVenue[]).filter((r) => !r.venue.location_approximate);
        setResults(list);
        setSelected(list[0]?.venue);
      });
  }, [centre, radius]);

  function select(venue: Venue) {
    setSelected(venue);
    // 窄屏上详情在列表下面，点了要带用户过去
    if (!matchMedia('(min-width: 1024px)').matches) requestAnimationFrame(() => detail.current?.scrollIntoView({ block: 'start' }));
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
    const { data, error } = await supabase!.rpc('confirm_venue', { target: venue.id });
    if (error) return toast(t('Couldn’t confirm right now. Try again later.'), 'error');
    toast(t('Thanks! Your confirmation helps other players.'));
    setSelected(data as Venue);
  }

  return (
    <div>
      <PageHeader eyebrow={t('Courts')} title={centre?.label ? t('Courts near {place}', { place: centre.label }) : t('Courts near you')} />

      <div className="flex flex-wrap items-center gap-3">
        <AreaPicker onPick={setCentre} />
        {centre && (
          <div className="flex gap-2" role="group" aria-label={t('Distance')}>
            {[5, 15, 30].map((r) => (
              <button key={r} onClick={() => setRadius(r)} aria-pressed={radius === r} className="toggle">
                {km(r * 1000)}
              </button>
            ))}
          </div>
        )}
      </div>

      {!centre && (
        <div className="mt-8">
          <EmptyState title={t('Find courts around you')}>{t('Use your location, or search a city to see the courts nearby.')}</EmptyState>
        </div>
      )}

      {centre && (
        <div className="mt-8 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
          <ul className="grid content-start gap-3" aria-label={t('Courts')} aria-busy={results === undefined}>
            {results === undefined && [0, 1, 2, 3].map((i) => <li key={i}><Skeleton className="h-[4.75rem]" /></li>)}
            {results?.length === 0 && (
              <li><EmptyState title={t('No courts within {distance} yet', { distance: km(radius * 1000) })}>{t('Try a wider distance, or add a court you play at from the iPhone app.')}</EmptyState></li>
            )}
            {results?.map(({ venue, distance_m }) => (
              <li key={venue.id}>
                <button
                  onClick={() => select(venue)}
                  aria-current={selected?.id === venue.id}
                  className="sticker lift block w-full p-4 text-left aria-[current=true]:bg-butter aria-[current=true]:text-on-accent"
                >
                  <span className="flex justify-between gap-3">
                    <span className="font-black">{venue.name}</span>
                    <span className="shrink-0 text-sm font-extrabold tabular-nums opacity-75">{km(distance_m)}</span>
                  </span>
                  <span className="mt-1 block truncate text-sm opacity-80">{address(venue)}</span>
                </button>
              </li>
            ))}
          </ul>

          {selected && (
            <section ref={detail} key={selected.id} className="tile animate-enter h-fit scroll-mt-4 bg-surface p-6 lg:sticky lg:top-6" aria-label={selected.name}>
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <span className={`chip ${selected.status === 'unconfirmed' ? 'bg-surface-muted text-ink' : 'bg-mint'}`}>
                    {selected.status === 'verified' ? t('Verified') : selected.status === 'confirmed' ? t('Confirmed by players') : t('Not yet confirmed')}
                  </span>
                  <h2 className="mt-3 text-2xl font-black">{selected.name}</h2>
                  <p className="mt-1 text-ink-secondary">{address(selected)}</p>
                </div>
                <button
                  onClick={() => toggleFavorite(selected)}
                  aria-pressed={favorites.has(selected.id)}
                  aria-label={t('Add to my courts')}
                  title={favorites.has(selected.id) ? t('In my courts') : t('Add to my courts')}
                  className="toggle size-11 shrink-0 p-0"
                >
                  <Icon name="star" />
                </button>
              </div>
              <div className="mt-5 flex flex-wrap gap-2">
                {selected.kind && selected.kind !== 'dedicated' && <span className="chip bg-lavender">{t(kindLabel[selected.kind])}</span>}
                {selected.court_count && <span className="chip bg-sky">{t('{n} court|{n} courts', { n: selected.court_count })}</span>}
                {selected.pricing?.perPerson !== undefined && <span className="chip bg-butter">{t('Drop-in {price}', { price: money(selected.pricing.perPerson, selected.country_code) })}</span>}
                {selected.pricing?.perCourtHour && <span className="chip bg-peach">{t('Court {price}/h', { price: money(selected.pricing.perCourtHour, selected.country_code) })}</span>}
              </div>
              {selected.play_times && (
                <div className="mt-5">
                  <p className="eyebrow">{t('Badminton hours')}</p>
                  <p className="mt-1 font-bold">{selected.play_times}</p>
                </div>
              )}
              <div className="mt-6 flex flex-wrap gap-2">
                <a className="button" href={`https://maps.apple.com/?q=${encodeURIComponent(selected.name)}&ll=${selected.lat},${selected.lon}`}>{t('Directions')}</a>
                {selected.website && <a className="button button-quiet" href={selected.website} rel="noopener nofollow">{t('Website')}</a>}
                {selected.status !== 'verified' && (
                  <Button variant="quiet" onClick={() => confirm(selected)}>{t('I’ve played here')}</Button>
                )}
              </div>
              {selected.attribution && <p className="mt-6 text-xs text-ink-tertiary">{selected.attribution}</p>}
            </section>
          )}
        </div>
      )}
    </div>
  );
}

const kindLabel: Record<NonNullable<Venue['kind']>, string> = {
  dedicated: 'Badminton center',
  multi_sport: 'Multi-sport center',
  rec_center: 'Community center',
  school: 'School gym',
  community_hall: 'Community hall',
};
