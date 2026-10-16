import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// 目录和 iOS 共用（Badie-iOS/Badie/Resources），接上数据库后改为从 Supabase 读取
const catalogDir = join(process.cwd(), '..', 'Badie-iOS', 'Badie', 'Resources');
const catalogs = ['curated-US', 'curated-MY', 'venues-GB', 'venues-HK', 'venues-JP', 'venues-SG', 'venues-TW'];

type Source = 'curated' | 'openStreetMap' | 'openData';

interface CatalogEntry {
  id: string;
  name: string;
  aliases?: string[];
  lat: number;
  lon: number;
  street: string;
  unit?: string;
  city: string;
  region: string;
  postcode: string;
  country: string;
  courts?: number;
  price?: { perPerson?: number; perCourtHour?: number };
  phone?: string;
  web?: string;
  status?: string;
  approx?: boolean;
  attr?: string;
}

interface Catalog {
  source?: Source;
  status?: string;
  attribution?: string;
  venues: CatalogEntry[];
}

export interface Venue extends CatalogEntry {
  slug: string;
  source: Source;
  confirmed: boolean;
  attribution?: string;
  path: string;
  indexable: boolean;
}

export interface City {
  slug: string;
  name: string;
  region: string;
  country: string;
  path: string;
  venues: Venue[];
  indexable: boolean;
}

export interface Country {
  code: string;
  name: string;
  path: string;
  cities: City[];
  venueCount: number;
}

const regionNames = new Intl.DisplayNames(['en'], { type: 'region' });
const countryName = (code: string) => (code === 'HK' ? 'Hong Kong' : (regionNames.of(code) ?? code));

export function slugify(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .normalize('NFC')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '');
}

const hasLatin = (text: string) => /[a-z]/i.test(text);

export function englishName(venue: CatalogEntry): string | undefined {
  if (hasLatin(venue.name)) return undefined;
  return venue.aliases?.find(hasLatin);
}

function uniqueSlug(base: string, taken: Set<string>): string {
  let slug = base || 'venue';
  for (let n = 2; taken.has(slug); n++) slug = `${base}-${n}`;
  taken.add(slug);
  return slug;
}

function load(): Country[] {
  const venues = catalogs.flatMap((name) => {
    const catalog: Catalog = JSON.parse(readFileSync(join(catalogDir, `${name}.json`), 'utf8'));
    return catalog.venues
      .filter((entry) => !entry.approx)
      .map((entry) => ({
        ...entry,
        source: catalog.source ?? 'openData',
        confirmed: (entry.status ?? catalog.status ?? 'verified') !== 'unconfirmed',
        attribution: entry.attr ?? catalog.attribution,
      }));
  });

  const countries = new Map<string, Country>();
  const cities = new Map<string, City>();
  const citySlugs = new Map<string, Set<string>>();
  const venueSlugs = new Map<City, Set<string>>();

  for (const entry of venues) {
    const code = entry.country.toLowerCase();
    let country = countries.get(code);
    if (!country) {
      country = { code, name: countryName(entry.country), path: `/courts/${code}/`, cities: [], venueCount: 0 };
      countries.set(code, country);
    }

    const cityKey = `${code}|${entry.region}|${entry.city}`;
    let city = cities.get(cityKey);
    if (!city) {
      const label = entry.region && !entry.city.includes(entry.region) ? `${entry.city} ${entry.region}` : entry.city;
      const taken = citySlugs.get(code) ?? new Set<string>();
      citySlugs.set(code, taken);
      const slug = uniqueSlug(slugify(label), taken);
      city = {
        slug,
        name: entry.city,
        region: entry.region === entry.city ? '' : entry.region,
        country: code,
        path: `${country.path}${slug}/`,
        venues: [],
        indexable: false,
      };
      cities.set(cityKey, city);
      country.cities.push(city);
    }

    const taken = venueSlugs.get(city) ?? new Set<string>();
    venueSlugs.set(city, taken);
    const slug = uniqueSlug(slugify(englishName(entry) ?? entry.name), taken);
    // 只有名字和地址的页面对搜索没有价值，先不让收录，等有了场地数、价格或球友贡献再放开
    const indexable = entry.courts !== undefined || entry.price !== undefined;
    city.venues.push({ ...entry, slug, path: `${city.path}${slug}/`, indexable });
    country.venueCount++;
  }

  for (const city of cities.values()) {
    city.venues.sort((a, b) => a.name.localeCompare(b.name));
    city.indexable = city.venues.length >= 3;
  }
  for (const country of countries.values()) {
    country.cities.sort((a, b) => b.venues.length - a.venues.length || a.name.localeCompare(b.name));
  }
  return [...countries.values()].sort((a, b) => b.venueCount - a.venueCount);
}

export const countries = load();
export const allCities = countries.flatMap((c) => c.cities);
export const inCountry = (country: Country) => (country.name.startsWith('United ') ? `the ${country.name}` : country.name);
export const cityName = (city: City) => (city.region ? `${city.name}, ${city.region}` : city.name);
export const allVenues = allCities.flatMap((c) => c.venues);

export function noindexPaths(): Set<string> {
  return new Set([...allCities.filter((c) => !c.indexable), ...allVenues.filter((v) => !v.indexable)].map((p) => p.path));
}

function distanceKm(a: CatalogEntry, b: CatalogEntry): number {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}

export function nearby(venue: Venue, limit = 5, radiusKm = 30): { venue: Venue; km: number }[] {
  return allVenues
    .filter((other) => other.id !== venue.id && other.country === venue.country)
    .map((other) => ({ venue: other, km: distanceKm(venue, other) }))
    .filter(({ km }) => km <= radiusKm)
    .sort((a, b) => a.km - b.km)
    .slice(0, limit);
}

const currencies: Record<string, string> = { US: 'USD', GB: 'GBP', HK: 'HKD', SG: 'SGD', TW: 'TWD', JP: 'JPY', MY: 'MYR' };

export function formatPrice(amount: number, country: string): string {
  const currency = currencies[country];
  if (!currency) return String(amount);
  return new Intl.NumberFormat('en', { style: 'currency', currency, maximumFractionDigits: 0 }).format(amount);
}

export function formatAddress(venue: CatalogEntry): string {
  const street = [venue.street, venue.unit].filter(Boolean).join(', ');
  const area = [venue.city, [venue.region, venue.postcode].filter(Boolean).join(' ')].filter(Boolean).join(', ');
  return [street, area].filter(Boolean).join(', ');
}
