import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

// 目录和 iOS 共用（Badie-iOS/Badie/Resources），加上只进数据库的（supabase/data：OpenStreetMap、我们整理的）。
// Cloudflare Pages 一次最多部署 2 万个文件，所以只有 App 自带的球馆有自己的页面；
// 其余的在城市页、国家页的列表里，点开是地图。少于 3 家的城市也不单独成页，列在国家页里。
const catalogDirs = [
  { dir: join(process.cwd(), '..', 'Badie-iOS', 'Badie', 'Resources'), pages: true },
  { dir: join(process.cwd(), '..', 'supabase', 'data'), pages: false },
  // 我们从头核对的（韩国：开放数据只有名字和所在区，地址、官网、价格都是对照官网补的，坐标按地址查 OpenStreetMap）。只给网站用
  { dir: join(process.cwd(), '..', 'Badie-iOS', 'data', 'catalogs'), pages: true },
];
const MIN_CITY_PAGE = 3;

/**
 * 我们对照官网核对过的价格和开放时间（按球馆 id，Badie-iOS/data/verified-venues.json，每条带来源链接）。
 * 只给网站用：App 的目录里价格只能是整数（VenueCatalog.swift），英国这类带小数的价格写进去整份目录会读不出来
 */
interface Verified {
  badminton?: boolean | null;
  perCourtHour?: number | null;
  perPerson?: number | null;
  playTimes?: string | null;
  web?: string | null;
  checked: string;
}
const verifiedFile = join(process.cwd(), '..', 'Badie-iOS', 'data', 'verified-venues.json');
const verified: Record<string, Verified> = existsSync(verifiedFile) ? JSON.parse(readFileSync(verifiedFile, 'utf8')).venues : {};

function withVerified<T extends CatalogEntry>(entry: T): T {
  const v = verified[entry.id];
  if (!v || v.badminton === false) return entry;
  const price = { ...(v.perPerson != null && { perPerson: v.perPerson }), ...(v.perCourtHour != null && { perCourtHour: v.perCourtHour }) };
  return {
    ...entry,
    ...(Object.keys(price).length && { price }),
    ...(v.playTimes && { playTimes: v.playTimes }),
    ...(v.web && { web: v.web }),
    ...((Object.keys(price).length || v.playTimes) && { checked: v.checked }),
  };
}
/**
 * 搜索引擎只收录我们自己核对过的（2026-11-20：Google 把几千个只有名字、地址的模板页整站拿出了索引）：
 * 这几个国家里，对照官网核对过价格或开放时间的球馆页、至少有一家这种球馆的城市页、国家页。其余照常能看，只是不让收录
 */
export const FOCUS_COUNTRIES = new Set(['us', 'gb', 'kr', 'jp']);

type Source = 'curated' | 'openStreetMap' | 'openData';
type Facility = 'dedicated' | 'multiSport' | 'recCenter' | 'school' | 'communityHall' | 'outdoor';

export const facilityLabel: Record<Facility, string> = {
  dedicated: 'Badminton center',
  multiSport: 'Multi-sport center',
  recCenter: 'Community center',
  school: 'School gym',
  communityHall: 'Community hall',
  outdoor: 'Outdoor court',
};

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
  tz?: string;
  courts?: number;
  price?: { perPerson?: number; perCourtHour?: number };
  phone?: string;
  web?: string;
  status?: string;
  approx?: boolean;
  attr?: string;
  facility?: Facility;
  /** When badminton is on at places that aren't badminton centres, copied from the official page */
  playTimes?: string;
  /** Date the Badie team last checked the entry, e.g. "2026-10-16" */
  checked?: string;
}

interface Catalog {
  kind?: Source;
  status?: string;
  attribution?: string;
  venues: CatalogEntry[];
}

export interface Venue extends CatalogEntry {
  slug: string;
  source: Source;
  confirmed: boolean;
  attribution?: string;
  /** 自己的页面，或者没有页面时的地图链接 */
  path: string;
  hasPage: boolean;
  indexable: boolean;
}

export interface City {
  slug: string;
  name: string;
  region: string;
  country: string;
  /** 城市页；不单独成页的城市是国家页上的锚点 */
  path: string;
  hasPage: boolean;
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

const mapLink = (venue: CatalogEntry) => `https://www.google.com/maps/search/?api=1&query=${venue.lat},${venue.lon}`;

// 州 / 省有的写缩写、有的写全名（“CA”和“California”），统一成缩写，不然同一个城市会拆成两页
const stateNames: Record<string, Record<string, string>> = {
  US: {
    AL: 'Alabama', AK: 'Alaska', AZ: 'Arizona', AR: 'Arkansas', CA: 'California', CO: 'Colorado', CT: 'Connecticut', DE: 'Delaware',
    DC: 'District of Columbia', FL: 'Florida', GA: 'Georgia', HI: 'Hawaii', ID: 'Idaho', IL: 'Illinois', IN: 'Indiana', IA: 'Iowa',
    KS: 'Kansas', KY: 'Kentucky', LA: 'Louisiana', ME: 'Maine', MD: 'Maryland', MA: 'Massachusetts', MI: 'Michigan', MN: 'Minnesota',
    MS: 'Mississippi', MO: 'Missouri', MT: 'Montana', NE: 'Nebraska', NV: 'Nevada', NH: 'New Hampshire', NJ: 'New Jersey',
    NM: 'New Mexico', NY: 'New York', NC: 'North Carolina', ND: 'North Dakota', OH: 'Ohio', OK: 'Oklahoma', OR: 'Oregon',
    PA: 'Pennsylvania', RI: 'Rhode Island', SC: 'South Carolina', SD: 'South Dakota', TN: 'Tennessee', TX: 'Texas', UT: 'Utah',
    VT: 'Vermont', VA: 'Virginia', WA: 'Washington', WV: 'West Virginia', WI: 'Wisconsin', WY: 'Wyoming', PR: 'Puerto Rico',
  },
  CA: {
    AB: 'Alberta', BC: 'British Columbia', MB: 'Manitoba', NB: 'New Brunswick', NL: 'Newfoundland and Labrador', NS: 'Nova Scotia',
    NT: 'Northwest Territories', NU: 'Nunavut', ON: 'Ontario', PE: 'Prince Edward Island', QC: 'Quebec', SK: 'Saskatchewan', YT: 'Yukon',
  },
  AU: {
    ACT: 'Australian Capital Territory', NSW: 'New South Wales', NT: 'Northern Territory', QLD: 'Queensland', SA: 'South Australia',
    TAS: 'Tasmania', VIC: 'Victoria', WA: 'Western Australia',
  },
};
const plain = (text: string) => text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
const stateCodes = new Map(
  Object.entries(stateNames).map(([country, names]) => [
    country,
    new Map(Object.entries(names).flatMap(([code, name]) => [[plain(code), code], [plain(name), code]])),
  ]),
);

function normalRegion(country: string, region: string): string {
  if (['HK', 'SG'].includes(country)) return '';
  return stateCodes.get(country)?.get(plain(region ?? '')) ?? region ?? '';
}

/** 国家页按州 / 省分组时的标题：缩写换回全名 */
export const regionLabel = (country: string, region: string) => stateNames[country.toUpperCase()]?.[region] ?? region;

/**
 * 同一个城市的球馆在数据里地区写法不一样（英国常写成所在的区，比如曼彻斯特的球馆有的写 Trafford、有的写 Salford），
 * 会拆成好几页“Badminton courts in Manchester”，每页都不够 3 家、不让收录。
 * 同一国家、同名、离第一家 25 公里以内的算一个城市，地区用其中最多的写法
 */
function cityRegions(venues: CatalogEntry[]): Map<CatalogEntry, string> {
  const byName = Map.groupBy(venues, (v) => `${v.country}|${plain(v.city)}`);
  const result = new Map<CatalogEntry, string>();
  for (const group of byName.values()) {
    const clusters: CatalogEntry[][] = [];
    for (const venue of group) {
      const cluster = clusters.find(([seed]) => distanceKm(seed, venue) <= 25);
      if (cluster) cluster.push(venue);
      else clusters.push([venue]);
    }
    for (const cluster of clusters) {
      const counts = new Map<string, number>();
      for (const v of cluster) counts.set(normalRegion(v.country, v.region), (counts.get(normalRegion(v.country, v.region)) ?? 0) + 1);
      const region = [...counts].sort((a, b) => b[1] - a[1])[0][0];
      for (const v of cluster) result.set(v, region);
    }
  }
  return result;
}

/** 旧分法的城市：地址、里面的球馆、有页面的球馆的旧地址 */
let oldCityList: { path: string; members: CatalogEntry[]; pages: boolean; venues: { venue: CatalogEntry; slug: string }[] }[] = [];

function load(): Country[] {
  const venues = catalogDirs.filter(({ dir }) => existsSync(dir)).flatMap(({ dir, pages }) =>
    readdirSync(dir)
      .filter((file) => file.endsWith('.json'))
      .sort()
      .flatMap((file) => {
        const catalog: Catalog = JSON.parse(readFileSync(join(dir, file), 'utf8'));
        return catalog.venues
          .filter((entry) => !entry.approx) // 位置不准的不上网站
          .map((entry) => ({
            ...withVerified(entry),
            source: catalog.kind ?? 'openData',
            confirmed: (entry.status ?? catalog.status ?? 'verified') !== 'unconfirmed',
            attribution: entry.attr ?? catalog.attribution,
            hasPage: pages,
          }));
      }),
  );

  const countries = new Map<string, Country>();
  const cities = new Map<string, City>();
  const citySlugs = new Map<string, Set<string>>();
  const venueSlugs = new Map<City, Set<string>>();
  const regionOf = cityRegions(venues);
  // 2026-11-19 以前的分法（地区按原样、不并同名城市）算出的旧地址，给 movedPaths() 做跳转
  const oldCities = new Map<string, { path: string; members: CatalogEntry[]; pages: boolean; slugs: Set<string>; venues: { venue: CatalogEntry; slug: string }[] }>();
  const oldCitySlugs = new Map<string, Set<string>>();

  for (const entry of venues) {
    const code = entry.country.toLowerCase();
    let country = countries.get(code);
    if (!country) {
      country = { code, name: countryName(entry.country), path: `/courts/${code}/`, cities: [], venueCount: 0 };
      countries.set(code, country);
    }

    const region = regionOf.get(entry)!;
    const cityKey = `${code}|${region}|${plain(entry.city)}`;
    let city = cities.get(cityKey);
    if (!city) {
      const label = region && !entry.city.includes(region) ? `${entry.city} ${region}` : entry.city;
      const taken = citySlugs.get(code) ?? new Set<string>();
      citySlugs.set(code, taken);
      const slug = uniqueSlug(slugify(label), taken);
      city = {
        slug,
        name: entry.city,
        region: region === entry.city ? '' : region,
        country: code,
        path: `${country.path}${slug}/`,
        hasPage: true,
        venues: [],
        indexable: false,
      };
      cities.set(cityKey, city);
      country.cities.push(city);
    }

    const taken = venueSlugs.get(city) ?? new Set<string>();
    venueSlugs.set(city, taken);
    const slug = entry.hasPage ? uniqueSlug(slugify(englishName(entry) ?? entry.name), taken) : '';
    // 只收录核对过价格或开放时间的（见 FOCUS_COUNTRIES）
    const indexable = entry.hasPage && FOCUS_COUNTRIES.has(code) && (entry.price !== undefined || entry.playTimes !== undefined);
    city.venues.push({ ...entry, slug, path: entry.hasPage ? `${city.path}${slug}/` : mapLink(entry), indexable });
    country.venueCount++;

    const oldRegion = ['HK', 'SG'].includes(entry.country) ? '' : entry.region;
    const oldKey = `${code}|${oldRegion}|${entry.city}`;
    let old = oldCities.get(oldKey);
    if (!old) {
      const taken = oldCitySlugs.get(code) ?? new Set<string>();
      oldCitySlugs.set(code, taken);
      const oldSlug = uniqueSlug(slugify(oldRegion && !entry.city.includes(oldRegion) ? `${entry.city} ${oldRegion}` : entry.city), taken);
      old = { path: `${country.path}${oldSlug}/`, members: [], pages: false, slugs: new Set(), venues: [] };
      oldCities.set(oldKey, old);
    }
    old.members.push(entry);
    old.pages ||= entry.hasPage;
    if (entry.hasPage) old.venues.push({ venue: entry, slug: uniqueSlug(slugify(englishName(entry) ?? entry.name), old.slugs) });
  }

  for (const city of cities.values()) {
    city.venues.sort((a, b) => a.name.localeCompare(b.name));
    city.hasPage = city.venues.length >= MIN_CITY_PAGE || city.venues.some((v) => v.hasPage);
    city.indexable = city.hasPage && city.venues.some((v) => v.indexable);
    if (!city.hasPage) city.path = `${countries.get(city.country)!.path}#area-${city.slug}`;
  }
  for (const country of countries.values()) {
    country.cities.sort((a, b) => b.venues.length - a.venues.length || a.name.localeCompare(b.name));
  }
  oldCityList = [...oldCities.values()];
  return [...countries.values()].sort((a, b) => Number(b.code === 'us') - Number(a.code === 'us') || b.venueCount - a.venueCount);
}

export const countries = load();
export const allCities = countries.flatMap((c) => c.cities);
export const inCountry = (country: Country) => (country.name.startsWith('United ') ? `the ${country.name}` : country.name);
export const cityName = (city: City) => (city.region ? `${city.name}, ${city.region}` : city.name);
export const allVenues = allCities.flatMap((c) => c.venues);
export const venuePages = allVenues.filter((v) => v.hasPage);
export const cityPages = allCities.filter((c) => c.hasPage);

/**
 * 城市的分法改过（2026-11-19：州 / 省统一成缩写、同名的近处城市并成一个），以前收录的城市页、球馆页地址变了。
 * 构建时写进 _redirects 做 301（见 astro.config.ts）。只跳以前有页面、现在地址不一样、新地址上没有别的页面的
 */
export function movedPaths(): [string, string][] {
  const current = new Set([...cityPages.map((c) => c.path), ...venuePages.map((v) => v.path)]);
  const byId = new Map(allVenues.map((v) => [v.id, v]));
  const cityOf = new Map(allCities.flatMap((c) => c.venues.map((v) => [v.id, c] as const)));
  const moves = new Map<string, string>();
  for (const old of oldCityList) {
    for (const { venue, slug } of old.venues) {
      const now = byId.get(venue.id);
      const from = `${old.path}${slug}/`;
      if (now?.hasPage && now.path !== from && !current.has(from)) moves.set(from, now.path);
    }
    const target = cityOf.get(old.members[0].id);
    if ((old.members.length >= MIN_CITY_PAGE || old.pages) && target && target.path !== old.path && !current.has(old.path)) moves.set(old.path, target.path);
  }
  return [...moves];
}

export function noindexPaths(): Set<string> {
  // 不在 FOCUS_COUNTRIES 里的国家页不收录；只有一个城市的国家（新加坡）国家页和城市页内容重复，也不收录
  const single = countries.filter((c) => !FOCUS_COUNTRIES.has(c.code) || c.cities.length === 1);
  return new Set([...single, ...cityPages.filter((c) => !c.indexable), ...venuePages.filter((v) => !v.indexable)].map((p) => p.path));
}

export function distanceKm(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
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

const currencies: Record<string, string> = { US: 'USD', GB: 'GBP', HK: 'HKD', SG: 'SGD', TW: 'TWD', JP: 'JPY', MY: 'MYR', KR: 'KRW' };

export function formatPrice(amount: number, country: string): string {
  if (amount === 0) return 'Free';
  const currency = currencies[country];
  if (!currency) return String(amount);
  return new Intl.NumberFormat('en', { style: 'currency', currency, minimumFractionDigits: amount % 1 ? 2 : 0, maximumFractionDigits: 2 }).format(amount);
}

export function formatAddress(venue: CatalogEntry): string {
  const street = [venue.street, venue.unit].filter(Boolean).join(', ');
  const area = [venue.city, [venue.region, venue.postcode].filter(Boolean).join(' ')].filter(Boolean).join(', ');
  return [street, area].filter(Boolean).join(', ');
}

// 时区在 Atlantic/、Indian/ 下的地方
const ISLANDS: Record<string, string> = {
  is: '150', fo: '150', pt: '150', es: '150', mv: '142', io: '142', re: '002', mu: '002', sc: '002', km: '002',
  yt: '002', cv: '002', mg: '002', bm: '003', fk: '005', gs: '005', sh: '002',
};
const SOUTH_AMERICA = new Set(['ar', 'bo', 'br', 'cl', 'co', 'ec', 'gy', 'pe', 'py', 'sr', 'uy', 've']);

/** 按这个国家球馆的时区归到大洲（Europe/London → 欧洲）。code 是联合国 M.49 编码，页面上用 data-region 翻成各种语言 */
function continentOf(country: Country): { code: string; name: string } {
  const zone = country.cities[0]?.venues[0]?.tz?.split('/')[0] ?? '';
  const code =
    ISLANDS[country.code] ??
    (zone === 'America' ? (SOUTH_AMERICA.has(country.code) ? '005' : '003')
    : zone === 'Australia' || zone === 'Pacific' ? '009'
    : ({ Europe: '150', Asia: '142', Africa: '002' } as Record<string, string>)[zone] ?? '001');
  return { code, name: new Intl.DisplayNames(['en'], { type: 'region' }).of(code) ?? 'World' };
}

/** 各大洲（球馆多的在前），每个大洲里的国家按球馆数排 */
export function byContinent(list: Country[] = countries): { code: string; continent: string; count: number; countries: Country[] }[] {
  const groups = new Map<string, { code: string; continent: string; count: number; countries: Country[] }>();
  for (const country of list) {
    const { code, name } = continentOf(country);
    const group = groups.get(code) ?? { code, continent: name, count: 0, countries: [] };
    group.countries.push(country);
    group.count += country.venueCount;
    groups.set(code, group);
  }
  for (const group of groups.values()) group.countries.sort((a, b) => b.venueCount - a.venueCount);
  return [...groups.values()].sort((a, b) => b.count - a.count);
}

/** 国旗：两个“区域指示符”字母拼成的 emoji（不支持的系统上显示成两个字母，也看得懂） */
export const flag = (code: string) => String.fromCodePoint(...[...code.toUpperCase()].map((letter) => 0x1f1a5 + letter.charCodeAt(0)));

function centroid(city: City) {
  const n = city.venues.length;
  return { lat: city.venues.reduce((sum, v) => sum + v.lat, 0) / n, lon: city.venues.reduce((sum, v) => sum + v.lon, 0) / n };
}

export function nearbyCities(city: City, limit = 6): City[] {
  const here = centroid(city);
  return allCities
    .filter((other) => other !== city && other.country === city.country)
    .map((other) => ({ other, km: distanceKm(here, centroid(other)) }))
    .filter(({ km }) => km <= 40)
    .sort((a, b) => a.km - b.km)
    .slice(0, limit)
    .map(({ other }) => other);
}

export function citySummary(city: City) {
  const priced = city.venues.filter((v) => v.price?.perPerson !== undefined);
  const cheapest = priced.reduce<Venue | undefined>((best, v) => (!best || v.price!.perPerson! < best.price!.perPerson! ? v : best), undefined);
  const largest = city.venues.reduce<Venue | undefined>((best, v) => ((v.courts ?? 0) > (best?.courts ?? 0) ? v : best), undefined);
  const totalCourts = city.venues.reduce((sum, v) => sum + (v.courts ?? 0), 0);
  return { priced: priced.length, cheapest, largest, totalCourts };
}
