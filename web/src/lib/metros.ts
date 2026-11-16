// 都会区页面：美国的球馆散在郊区的小城里（El Monte 两家、Irwindale 一家），大多数城市页不够 3 家、不让收录，
// 搜 “badminton Los Angeles” 的人没有一页可看。这里按“中心点 + 半径”把一个都会区的球馆合成一页，列出散客价和包场价。
// 只收有自己页面的球馆（App 自带、我们对照官网核对过的），OpenStreetMap 上只有名字的不收。
// 球馆够 4 家、其中 3 家有价格才成页；名单可以放宽，数据补上来以后页面自己出现
import { allVenues, distanceKm, type Venue } from './venues';

interface Area {
  slug: string;
  name: string;
  zh: string;
  lat: number;
  lon: number;
  radiusKm: number;
}

const areas: Area[] = [
  { slug: 'los-angeles', name: 'Los Angeles', zh: '洛杉矶', lat: 34.0, lon: -118.0, radiusKm: 80 },
  { slug: 'bay-area', name: 'San Francisco Bay Area', zh: '旧金山湾区', lat: 37.6, lon: -122.05, radiusKm: 75 },
  { slug: 'san-diego', name: 'San Diego', zh: '圣地亚哥', lat: 32.9, lon: -117.15, radiusKm: 50 },
  { slug: 'sacramento', name: 'Sacramento', zh: '萨克拉门托', lat: 38.58, lon: -121.45, radiusKm: 50 },
  { slug: 'seattle', name: 'Seattle', zh: '西雅图', lat: 47.62, lon: -122.2, radiusKm: 55 },
  { slug: 'portland', name: 'Portland', zh: '波特兰', lat: 45.52, lon: -122.7, radiusKm: 45 },
  { slug: 'dallas-fort-worth', name: 'Dallas–Fort Worth', zh: '达拉斯–沃斯堡', lat: 32.9, lon: -97.0, radiusKm: 70 },
  { slug: 'houston', name: 'Houston', zh: '休斯敦', lat: 29.76, lon: -95.5, radiusKm: 65 },
  { slug: 'austin', name: 'Austin', zh: '奥斯汀', lat: 30.4, lon: -97.74, radiusKm: 45 },
  { slug: 'new-york', name: 'New York City', zh: '纽约', lat: 40.74, lon: -73.92, radiusKm: 48 },
  { slug: 'central-new-jersey', name: 'Central New Jersey', zh: '新泽西中部', lat: 40.42, lon: -74.5, radiusKm: 38 },
  { slug: 'chicago', name: 'Chicago', zh: '芝加哥', lat: 41.92, lon: -87.9, radiusKm: 60 },
  { slug: 'washington-dc', name: 'Washington, D.C.', zh: '华盛顿特区', lat: 39.02, lon: -77.15, radiusKm: 55 },
  { slug: 'boston', name: 'Boston', zh: '波士顿', lat: 42.38, lon: -71.25, radiusKm: 50 },
  { slug: 'philadelphia', name: 'Philadelphia', zh: '费城', lat: 40.05, lon: -75.35, radiusKm: 45 },
  { slug: 'pittsburgh', name: 'Pittsburgh', zh: '匹兹堡', lat: 40.44, lon: -79.95, radiusKm: 40 },
  { slug: 'atlanta', name: 'Atlanta', zh: '亚特兰大', lat: 33.95, lon: -84.25, radiusKm: 50 },
  { slug: 'columbus', name: 'Columbus', zh: '哥伦布', lat: 40.03, lon: -83.03, radiusKm: 35 },
  { slug: 'denver', name: 'Denver', zh: '丹佛', lat: 39.8, lon: -105.0, radiusKm: 60 },
  { slug: 'phoenix', name: 'Phoenix', zh: '凤凰城', lat: 33.45, lon: -112.0, radiusKm: 60 },
  { slug: 'detroit', name: 'Detroit', zh: '底特律', lat: 42.45, lon: -83.3, radiusKm: 60 },
];

export interface Metro extends Area {
  path: string;
  /** 羽毛球馆、综合体育馆：天天开门，可以包场 */
  clubs: Venue[];
  /** 社区中心、学校体育馆、露天场地：每周固定几个时段 */
  community: Venue[];
  venues: Venue[];
}

const hasPrice = (venue: Venue) => venue.price?.perPerson !== undefined || venue.price?.perCourtHour !== undefined;
const isClub = (venue: Venue) => venue.facility === 'dedicated' || venue.facility === 'multiSport';
/** 便宜的在前；没标散客价的排在后面 */
const byPrice = (a: Venue, b: Venue) => (a.price?.perPerson ?? Infinity) - (b.price?.perPerson ?? Infinity) || a.name.localeCompare(b.name);

export const metros: Metro[] = areas
  .map((area) => {
    const venues = allVenues.filter((v) => v.hasPage && v.country === 'US' && distanceKm(area, v) <= area.radiusKm).sort(byPrice);
    return { ...area, path: `/courts/us/metro/${area.slug}/`, venues, clubs: venues.filter(isClub), community: venues.filter((v) => !isClub(v)) };
  })
  .filter((metro) => metro.venues.length >= 4 && metro.venues.filter(hasPrice).length >= 3)
  .sort((a, b) => b.venues.length - a.venues.length);

/** 这个位置属于哪个都会区（落在几个里面时取中心最近的） */
export function metroOf(point: { lat: number; lon: number; country: string }): Metro | undefined {
  if (point.country.toUpperCase() !== 'US') return undefined;
  return metros
    .map((metro) => ({ metro, km: distanceKm(metro, point) }))
    .filter(({ metro, km }) => km <= metro.radiusKm)
    .sort((a, b) => a.km - b.km)[0]?.metro;
}

/** 最低和最高：散客每人、包场每小时 */
export function metroSummary(metro: Metro) {
  const range = (values: number[]) => (values.length ? { low: Math.min(...values), high: Math.max(...values), count: values.length } : undefined);
  const defined = <T,>(value: T | undefined): value is T => value !== undefined;
  return {
    dropIn: range(metro.venues.map((v) => v.price?.perPerson).filter(defined)),
    rental: range(metro.venues.map((v) => v.price?.perCourtHour).filter(defined)),
    largest: metro.venues.reduce<Venue | undefined>((best, v) => ((v.courts ?? 0) > (best?.courts ?? 0) ? v : best), undefined),
    checked: metro.venues.map((v) => v.checked).filter(defined).sort().at(-1),
  };
}
