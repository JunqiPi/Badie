import type { APIRoute } from 'astro';
import { allVenues, cityName, countries, englishName } from '../lib/venues';

export const GET: APIRoute = () => {
  const cities = countries.flatMap((country) =>
    country.cities.map((city) => ({
      k: 'city',
      n: cityName(city),
      s: `${country.name} · ${city.venues.length} ${city.venues.length === 1 ? 'court' : 'courts'}`,
      p: city.path,
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
