import { useEffect, useState, type ReactNode } from 'react';
import { setArea, useArea } from './area';
import { APP_STORE_URL } from './Contact';
import { km } from './Courts';
import { t } from './i18n';
import { Icon } from './icons';
import { CardFan, IconTile, fill, type Tint } from './kit';
import type { Centre } from './pickers';
import { QuizEntry } from './Levels';
import { Link } from './router';
import { signInFirst } from './Shell';
import { supabase, type Game, type NearbyVenue } from './supabase';
import { toast } from './ui';

/** 结束后 48 小时内还有没评价的球友 */
export const toReview = (g: Game) =>
  g.status === 'scheduled' && Date.now() > new Date(g.ends_at).getTime() && Date.now() < new Date(g.review_until).getTime() &&
  g.players.some((p) => !p.me && !p.reviewed);

/** 没登录时的首页（登录后的首页是发现页，见 Discover.tsx） */
export function Home() {
  return <Welcome />;
}

/** 大标题：星号里的字用荧光笔标出来 */
function Headline({ text, children, size = 'text-[2.375rem] sm:text-[2.75rem] lg:text-[3.25rem]' }: { text: string; children?: ReactNode; size?: string }) {
  const parts = text.split('*');
  return (
    <div className="min-w-0">
      {children}
      <h1 className={`display mt-1 whitespace-pre-line ${size}`}>
        {parts.map((part, i) => (i % 2 ? <mark key={i} className="marker">{part}</mark> : part))}
      </h1>
    </div>
  );
}

/** 附近球馆：最近的 3 家，点进球馆页 */
function NearbyCourts() {
  const area = useArea();
  const [courts, setCourts] = useState<NearbyVenue[]>();
  useEffect(() => {
    if (!area) return;
    supabase!.rpc('venues_near', { lat: area.lat, lng: area.lon, radius_km: 15, max_results: 3 }).then(({ data }) => setCourts((data ?? []) as NearbyVenue[]));
  }, [area?.lat, area?.lon]);

  if (!area) return <AreaPrompt />;
  return (
    <div className="sticker grid p-2">
      {courts === undefined && [0, 1, 2].map((i) => <div key={i} className="skeleton m-2 h-12" />)}
      {courts?.length === 0 && <p className="p-3 text-footnote text-ink-secondary">{t('No courts within {distance} yet', { distance: km(15_000) })}</p>}
      {courts?.slice(0, 3).map(({ venue, distance_m }) => (
        <Link key={venue.id} to={`/courts/?venue=${venue.id}`} className="press flex items-center gap-3 rounded-[14px] p-2 hover:bg-surface-muted/70">
          <IconTile icon="pin" tint="sky" size="sm" />
          <span className="min-w-0 flex-1">
            <span className="block truncate font-bold">{venue.name}</span>
            <span className="block truncate text-footnote text-ink-secondary">{venue.city}</span>
          </span>
          <span className="shrink-0 text-footnote font-bold text-ink-secondary tabular-nums">{km(distance_m)}</span>
        </Link>
      ))}
    </div>
  );
}

/** 还不知道你在哪：用定位（不存坐标到服务器，只存在这个浏览器） */
export function AreaPrompt({ tint = 'sky' }: { tint?: Tint }) {
  const [busy, setBusy] = useState(false);
  function locate() {
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      (p) => {
        setBusy(false);
        setArea({ lat: p.coords.latitude, lon: p.coords.longitude } satisfies Centre);
      },
      () => {
        setBusy(false);
        toast(t('Location is off. Search an area instead.'), 'error');
      },
      { timeout: 10000 },
    );
  }
  return (
    <div className={`tile grid gap-3 p-4 ${fill[tint]}`}>
      <p className="flex items-center gap-3 text-footnote font-bold">
        <IconTile icon="locate" tint="surface" />
        {t('Show what’s near you. Your location is only used to find courts and games nearby.')}
      </p>
      <span className="flex flex-wrap gap-2">
        <button type="button" onClick={locate} disabled={busy} className="button button-sm button-quiet">{t('Use my location')}</button>
        <Link to="/courts/" className="button button-sm button-quiet">{t('Search an area')}</Link>
      </span>
    </div>
  );
}

// MARK: 没登录时的首页：先把 Badie 讲清楚，一节只讲一件事、留足空白；能用的功能直接用，要账号的先去登录

const steps: { tint: Tint; title: string }[] = [
  { tint: 'lavender', title: 'Set your level' },
  { tint: 'lime', title: 'Get matched' },
  { tint: 'peach', title: 'Play, then confirm' },
];

const lead = 'text-[1.0625rem] leading-relaxed text-ink-secondary lg:text-[1.1875rem]';

function Welcome() {
  return (
    <div className="grid gap-20 pb-4 lg:gap-28">
      <header className="grid items-center gap-10 lg:min-h-[28rem] lg:grid-cols-[minmax(0,1fr)_auto] lg:gap-16">
        <div className="grid justify-items-start gap-6">
          <Headline text={t('Badminton buddy?\nFind one *today*.')} size="text-[2.25rem] sm:text-[3.75rem] lg:text-[4.5rem]" />
          <p className={`max-w-xl ${lead}`}>{t('Badie finds players at your level near you. Free.')}</p>
          <div className="flex flex-wrap gap-3">
            <Link to={signInFirst('/play/')} className="button button-lg">{t('Start matching')}<Icon name="arrowRight" className="size-5" /></Link>
            <a href={APP_STORE_URL} className="button button-lg button-quiet">{t('Get the iPhone app')}</a>
          </div>
          <QuizEntry />
        </div>
        <div className="max-sm:-my-4 lg:px-12"><CardFan className="max-sm:scale-[0.8] lg:scale-125" /></div>
      </header>

      <section aria-labelledby="how" className="grid gap-8">
        <h2 id="how" className="text-title lg:text-[2.5rem]">{t('How Badie works')}</h2>
        <ol className="grid gap-4 sm:grid-cols-3">
          {steps.map((s, i) => (
            <li key={s.title} className={`sticker flex items-center gap-4 p-5 lg:p-6 ${fill[s.tint]}`}>
              <span className="grid size-10 shrink-0 place-items-center rounded-full bg-[#17140f] text-headline font-black text-lime">{i + 1}</span>
              <h3 className="text-title3">{t(s.title)}</h3>
            </li>
          ))}
        </ol>
      </section>

      <section aria-labelledby="find-courts" className="grid gap-8">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <h2 id="find-courts" className="text-title lg:text-[2.5rem]">{t('Find courts around you')}</h2>
          <Link to="/courts/" className="button button-quiet">{t('Browse by country')}</Link>
        </div>
        <NearbyCourts />
      </section>

      <section aria-labelledby="ready" className="sticker grid gap-6 bg-[#17140f] p-8 text-[#f5f0e6] sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center lg:p-12">
        <h2 id="ready" className="text-title lg:text-[2.5rem]">{t('Ready to play?')}</h2>
        <Link to="/signin/?new" className="button button-lg justify-self-start">{t('Create account')}</Link>
      </section>
    </div>
  );
}

