import { useEffect, useRef, useState } from 'react';
import { Icon } from './icons';
import { supabase, type NearbyVenue, type Venue } from './supabase';

type Centre = { lat: number; lon: number; label: string };
type Area = { k: 'city' | 'court'; n: string; s: string; c?: [number, number] };

const km = (metres: number) => (metres < 1000 ? `${Math.round(metres)} m` : `${(metres / 1000).toFixed(1)} km`);
const money = (amount: number, country: string) =>
  new Intl.NumberFormat('en', { style: 'currency', currency: { US: 'USD', GB: 'GBP', HK: 'HKD', SG: 'SGD', MY: 'MYR', TW: 'TWD', JP: 'JPY' }[country] ?? 'USD', maximumFractionDigits: 0 }).format(amount);
const address = (v: Venue) => [[v.street, v.unit].filter(Boolean).join(', '), v.city, [v.region, v.postal_code].filter(Boolean).join(' ')].filter(Boolean).join(', ');

export function Courts({ userId }: { userId: string }) {
  const [centre, setCentre] = useState<Centre>();
  const [radius, setRadius] = useState(15);
  const [results, setResults] = useState<NearbyVenue[]>();
  const [selected, setSelected] = useState<Venue>();
  const [favorites, setFavorites] = useState<Set<string>>(new Set());
  const [notice, setNotice] = useState<string>();
  const detail = useRef<HTMLElement>(null);

  function select(venue: Venue) {
    setSelected(venue);
    // 窄屏上详情在列表下面，点了要带用户过去
    if (!matchMedia('(min-width: 1024px)').matches) requestAnimationFrame(() => detail.current?.scrollIntoView({ behavior: 'smooth' }));
  }

  useEffect(() => {
    supabase!.from('favorite_venues').select('venue_id').then(({ data }) => setFavorites(new Set(data?.map((f) => f.venue_id))));
  }, []);

  useEffect(() => {
    if (!centre) return;
    setResults(undefined);
    supabase!
      .rpc('venues_near', { lat: centre.lat, lng: centre.lon, radius_km: radius, max_results: 100 })
      .then(({ data, error }) => {
        if (error) setNotice(error.message);
        const list = ((data ?? []) as NearbyVenue[]).filter((r) => !r.venue.location_approximate);
        setResults(list);
        setSelected(list[0]?.venue);
      });
  }, [centre, radius]);

  function locate() {
    setNotice(undefined);
    navigator.geolocation.getCurrentPosition(
      (p) => setCentre({ lat: p.coords.latitude, lon: p.coords.longitude, label: 'your location' }),
      () => setNotice('Location is off. Search an area instead.'),
      { timeout: 10000 },
    );
  }

  async function toggleFavorite(venue: Venue) {
    const next = new Set(favorites);
    if (favorites.has(venue.id)) {
      await supabase!.from('favorite_venues').delete().eq('venue_id', venue.id);
      next.delete(venue.id);
    } else {
      await supabase!.from('favorite_venues').insert({ user_id: userId, venue_id: venue.id });
      next.add(venue.id);
    }
    setFavorites(next);
  }

  async function confirm(venue: Venue) {
    const { data, error } = await supabase!.rpc('confirm_venue', { target: venue.id });
    if (error) return setNotice(error.message);
    setNotice('Thanks! Your confirmation helps other players.');
    setSelected(data as Venue);
  }

  return (
    <div>
      <p className="eyebrow">Courts</p>
      <h1 className="display mt-2 text-5xl">Courts near {centre?.label ?? 'you'}</h1>

      <div className="mt-6 flex flex-wrap items-center gap-3">
        <button onClick={locate} className="button">
          <Icon name="pin" /> Use my location
        </button>
        <AreaSearch onPick={(area) => area.c && setCentre({ lat: area.c[0], lon: area.c[1], label: area.n })} />
        {centre && (
          <div className="flex gap-2" role="group" aria-label="Distance">
            {[5, 15, 30].map((r) => (
              <button
                key={r}
                onClick={() => setRadius(r)}
                aria-pressed={radius === r}
                className="chip h-9 bg-surface px-3 text-ink aria-pressed:bg-butter aria-pressed:text-on-accent"
              >
                {r} km
              </button>
            ))}
          </div>
        )}
      </div>
      {notice && <p role="status" className="mt-4 font-bold text-ink-secondary">{notice}</p>}

      {centre && (
        <div className="mt-8 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
          <ul className="grid content-start gap-3" aria-label="Courts">
            {results === undefined && <li className="font-bold text-ink-tertiary">Loading…</li>}
            {results?.length === 0 && (
              <li className="tile bg-surface p-5 font-bold">No courts listed within {radius} km yet. Try a wider distance.</li>
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
                    <span className="shrink-0 text-sm font-extrabold opacity-70">{km(distance_m)}</span>
                  </span>
                  <span className="mt-1 block truncate text-sm opacity-75">{address(venue)}</span>
                </button>
              </li>
            ))}
          </ul>

          {selected && (
            <section ref={detail} className="tile h-fit scroll-mt-4 bg-surface p-6 lg:sticky lg:top-6" aria-label={selected.name}>
              <div className="flex items-start justify-between gap-4">
                <div>
                  <span className={`chip ${selected.status === 'unconfirmed' ? 'bg-surface-muted text-ink' : 'bg-mint'}`}>
                    {selected.status === 'verified' ? 'Verified' : selected.status === 'confirmed' ? 'Confirmed by players' : 'Not yet confirmed'}
                  </span>
                  <h2 className="mt-3 text-2xl font-black">{selected.name}</h2>
                  <p className="mt-1 text-ink-secondary">{address(selected)}</p>
                </div>
                <button
                  onClick={() => toggleFavorite(selected)}
                  aria-pressed={favorites.has(selected.id)}
                  aria-label="Add to my courts"
                  className="tile grid size-11 shrink-0 place-items-center bg-surface aria-pressed:bg-butter aria-pressed:text-on-accent"
                >
                  <Icon name="star" />
                </button>
              </div>
              <div className="mt-5 flex flex-wrap gap-2">
                {selected.court_count && <span className="chip bg-sky">{selected.court_count} courts</span>}
                {selected.pricing?.perPerson && <span className="chip bg-butter">Drop-in {money(selected.pricing.perPerson, selected.country_code)}</span>}
                {selected.pricing?.perCourtHour && <span className="chip bg-peach">Court {money(selected.pricing.perCourtHour, selected.country_code)}/h</span>}
              </div>
              <div className="mt-6 flex flex-wrap gap-2">
                <a className="button" href={`https://maps.apple.com/?q=${encodeURIComponent(selected.name)}&ll=${selected.lat},${selected.lon}`}>Directions</a>
                {selected.status !== 'verified' && (
                  <button onClick={() => confirm(selected)} className="button button-quiet">I’ve played here</button>
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

let areas: Promise<Area[]> | undefined;

function AreaSearch({ onPick }: { onPick: (area: Area) => void }) {
  const [query, setQuery] = useState('');
  const [hits, setHits] = useState<Area[]>([]);

  useEffect(() => {
    const q = query.trim().toLowerCase();
    if (q.length < 2) return setHits([]);
    areas ??= fetch('/search.json').then((r) => r.json());
    areas.then((all) => setHits(all.filter((a) => a.k === 'city' && a.n.toLowerCase().includes(q)).slice(0, 6)));
  }, [query]);

  return (
    <div className="relative">
      <input
        type="search"
        aria-label="Search an area"
        placeholder="Search an area"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        className="tile h-11 w-60 bg-surface px-4 font-bold outline-none placeholder:text-ink-tertiary focus:border-lavender"
      />
      {hits.length > 0 && (
        <ul className="sticker absolute top-full z-10 mt-2 w-72 p-2">
          {hits.map((area) => (
            <li key={area.n}>
              <button
                onClick={() => { onPick(area); setQuery(''); }}
                className="block w-full rounded-xl px-3 py-2 text-left hover:bg-surface-muted"
              >
                <span className="block font-extrabold">{area.n}</span>
                <span className="block text-sm text-ink-secondary">{area.s}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
