import type { APIRoute } from 'astro';
import { allVenues, cityName, countries, englishName, type Venue } from '../lib/venues';

const round = (n: number) => Math.round(n * 1e4) / 1e4;
const centre = (venues: Venue[]) => [
  round(venues.reduce((sum, v) => sum + v.lat, 0) / venues.length),
  round(venues.reduce((sum, v) => sum + v.lon, 0) / venues.length),
];

export const GET: APIRoute = () => {
  const cities = countries.flatMap((country) =>
    country.cities.map((city) => ({
      k: 'city',
      n: cityName(city),
      s: `${country.name} · ${city.venues.length} ${city.venues.length === 1 ? 'court' : 'courts'}`,
      p: city.path,
      c: centre(city.venues),
    })),
  );
  const courts = allVenues.map((venue) => ({
    k: 'court',
    n: [venue.name, englishName(venue)].filter(Boolean).join(' · '),
    s: venue.city,
    p: venue.path,
  }));
  return new Response(JSON.stringify([...cities, ...courts]), { headers: { 'Content-Type': 'application/json' } });
};
