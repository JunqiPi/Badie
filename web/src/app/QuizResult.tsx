import { useEffect, useMemo, useRef, useState } from 'react';
import { archetypeInfo, axes, axisLevel, axisNames, evaluate, playStyle, questionTitle, tier, tierSlug, type Axis, type PlayStyle } from './assessment';
import { currentLocale, pathPrefixes, t, useLocale } from './i18n';
import { Icon } from './icons';
import { Starburst, Tag } from './kit';
import { fontsReady, ghostWord, loadArt, loadImage, renderCard, type CardFace, type CardInput } from './levelCard';
import { clearPending, loadPending, saveArgs, validAnswers } from './quizStore';
import { Link, navigate } from './router';
import { signInFirst } from './Shell';
import { avatarUrl, problem, supabase, tagText, type Profile } from './supabase';
import { Button, toast } from './ui';
import { freeSummary } from './usual';

/**
 * 测级结果（/level-quiz/result/）：等级、打法和雷达图、分享卡片。
 * 没登录的人答案在本机（sessionStorage）；登录的人点“保存”，刚注册的人建好资料时已经自动存过
 */
export function QuizResult({ profile, onProfile }: { profile: Profile | null; onProfile: (profile: Profile) => void }) {
  useLocale();
  const pending = useMemo(() => loadPending(), []);
  const saved = profile?.assessment ? validAnswers(profile.assessment) : undefined;
  const answers = pending ?? saved;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    if (!answers) navigate('/level-quiz/', true);
  }, [answers]);
  if (!answers) return null;

  const result = evaluate(answers)!;
  const style = playStyle(answers)!;
  const level = tier(result.rating);
  const isSaved = !pending || (saved !== undefined && JSON.stringify(saved) === JSON.stringify(pending));

  async function save() {
    setBusy(true);
    const { data, error } = await supabase!.rpc('save_assessment', saveArgs(answers!)!);
    setBusy(false);
    if (error) return setError(problem(error));
    // 第一次定级（新注册的人）存完回首页，和以前一样；重测的人留在这页，可以接着分享卡片
    const firstTime = !profile?.assessment;
    clearPending();
    onProfile(data as Profile);
    toast(t('Level saved.'));
    if (firstTime) navigate('/');
  }

  return (
    <div className="mx-auto grid max-w-2xl gap-6">
      <LevelHero level={level} rating={result.rating} />

      <ul className="grid gap-2 text-subhead text-ink-secondary">
        {result.limitingGate && <li>{result.limitingGate}</li>}
        {result.needsCalibration && <li>{t('Your tournament experience ranks higher than your skill answers, so your level is set by experience.')}</li>}
        {result.isReturning && <li>{t('Coming back? This is your level on current form.')}</li>}
      </ul>

      <PlayStyleCard style={style} />

      <ShareCard result={{ rating: result.rating, next: result.next }} style={style} profile={profile} />

      {profile ? (
        isSaved ? (
          <p className="flex items-center gap-2 text-subhead font-bold"><Icon name="check" className="size-5" />{t('Level saved.')}</p>
        ) : (
          <div className="grid gap-3">
            <p className="text-subhead text-ink-secondary">{t('Players are matched within the level range they choose. You can retake the quiz after 90 days.')}</p>
            {error && <p role="alert" className="font-bold text-danger">{error}</p>}
            <Button className="button-lg" busy={busy} onClick={save}>{t('Save my level')}</Button>
          </div>
        )
      ) : (
        <section className="sticker grid gap-4 bg-[#17140f] p-6 text-[#f5f0e6]" aria-labelledby="keep">
          <h2 id="keep" className="text-title3">{t('Save your level and play')}</h2>
          <ul className="grid gap-2 text-subhead">
            {[t('Your level is saved, no need to answer again'), t('After games, the players you played help calibrate it'), t('Find players around level {n} near you', { n: level.level })].map((reason) => (
              <li key={reason} className="flex gap-2"><Icon name="check" className="mt-0.5 size-5 shrink-0 text-lime" />{reason}</li>
            ))}
          </ul>
          <Link to={signInFirst('/level-quiz/result/')} className="button button-lg justify-self-start">{t('Save my level')}</Link>
          <p className="text-footnote opacity-80">{t('Free. Your answers stay on this device until you sign up.')}</p>
        </section>
      )}

      <Link to="/level-quiz/" className="justify-self-start text-footnote font-bold text-ink-secondary underline underline-offset-4 hover:text-ink">{t('Start over')}</Link>
    </div>
  );
}

/** 星形周围的小贴纸：进场时从星形后面弹出来，停在这些位置（x、y 是离星形中心的距离） */
const pieces: { x: number; y: number; turn: number; size: number; delay: number; tint?: string; round?: boolean }[] = [
  { x: -128, y: -30, turn: -28, size: 34, delay: 260 },
  { x: 124, y: 34, turn: 150, size: 28, delay: 340 },
  { x: -96, y: 52, turn: 0, size: 16, delay: 300, tint: 'pink', round: true },
  { x: 104, y: -48, turn: 0, size: 20, delay: 220, tint: 'sky', round: true },
  { x: -150, y: 26, turn: 18, size: 14, delay: 380, tint: 'lavender' },
  { x: 150, y: -6, turn: -14, size: 13, delay: 420, tint: 'mint' },
];

/** 等级从 1 数到结果（关了动效的人直接看到结果） */
function useCountUp(target: number) {
  const still = useMemo(() => typeof matchMedia !== 'function' || matchMedia('(prefers-reduced-motion: reduce)').matches, []);
  const [shown, setShown] = useState(still ? target : 1);
  useEffect(() => {
    if (still || target <= 1) return;
    let current = 1;
    let timer: ReturnType<typeof setInterval> | undefined;
    const start = setTimeout(() => {
      timer = setInterval(() => {
        current += 1;
        setShown(current);
        if (current >= target) clearInterval(timer);
      }, 110);
    }, 250);
    return () => {
      clearTimeout(start);
      clearInterval(timer);
    };
  }, [target, still]);
  return shown;
}

/** 结果的第一块：星形里的等级（盖章一样弹出来）、名字、一句话，下面是 1–9 级的刻度 */
function LevelHero({ level, rating }: { level: ReturnType<typeof tier>; rating: number }) {
  const shown = useCountUp(level.level);
  return (
    <section className="sticker relative isolate overflow-hidden bg-lime text-on-accent" aria-labelledby="result">
      <div aria-hidden="true" className="result-pattern absolute -inset-16 -z-10" />
      <div className="grid justify-items-center gap-2 p-6 text-center sm:p-8">
        <p className="kicker">{t('Your level')}</p>
        <h1 id="result" aria-label={level.label} className="relative outline-none">
          <span aria-hidden="true" className="max-[419px]:hidden">
            {pieces.map((piece) => (
              <span
                key={`${piece.x},${piece.y}`}
                className={`result-piece absolute top-1/2 left-1/2 ${piece.tint ? `border-2 border-[#17140f] shadow-[1.5px_2px_0_#17140f] ${piece.round ? 'rounded-full' : 'rounded-[4px]'}` : ''}`}
                style={{
                  ['--x' as string]: `${piece.x}px`,
                  ['--y' as string]: `${piece.y}px`,
                  ['--turn' as string]: `${piece.turn}deg`,
                  ['--delay' as string]: `${piece.delay}ms`,
                  width: piece.size,
                  height: piece.size,
                  background: piece.tint ? `var(--color-${piece.tint})` : 'url(/logo.svg) center / contain no-repeat',
                }}
              />
            ))}
          </span>
          <span className="result-stamp relative block">
            <Starburst tint="butter" size={152}>{shown >= level.level ? level.label : shown}</Starburst>
          </span>
        </h1>
        <p className="text-display">{level.name}</p>
        <p className="max-w-md text-subhead font-semibold">{level.summary}</p>
        <Tag tint="surface">{t('Self-rated')}</Tag>
        <LevelScale rating={rating} />
      </div>
    </section>
  );
}

/** 1–9 级的刻度：到自己这一级为止涂黑，圆点停在 −、平、+ 的准确位置 */
function LevelScale({ rating }: { rating: number }) {
  const clamped = Math.min(9.33, Math.max(0.67, rating));
  return (
    <div aria-hidden="true" className="mt-3 w-full max-w-sm">
      <div className="relative">
        <div className="grid grid-cols-9 gap-1">
          {Array.from({ length: 9 }, (_, i) => (
            <span key={i} className={`h-2.5 rounded-full border-2 border-[#17140f] ${i + 1 <= Math.round(rating) ? 'bg-[#17140f]' : 'bg-white/70'}`} />
          ))}
        </div>
        <span
          className="result-marker absolute top-1/2 size-5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-[#17140f] bg-butter shadow-[1.5px_2px_0_#17140f]"
          style={{ left: `${((clamped - 0.5) / 9) * 100}%` }}
        />
      </div>
      <div className="mt-1.5 grid grid-cols-9 gap-1 text-caption font-black tabular-nums">
        {Array.from({ length: 9 }, (_, i) => (
          <span key={i} className={i + 1 === Math.round(rating) ? '' : 'opacity-50'}>{i + 1}</span>
        ))}
      </div>
    </div>
  );
}

/** 打法：上面是和卡片一样的人物区（英文大字、剪影），下面是一句话、最强一拍、最佳搭档和六项能力的雷达图 */
function PlayStyleCard({ style }: { style: PlayStyle }) {
  const info = archetypeInfo[style.archetype];
  const partner = info.partner ? t(archetypeInfo[info.partner].name) : t('Anyone works');
  return (
    <section className="sticker animate-enter overflow-hidden" style={{ background: info.color, color: info.ink }} aria-labelledby="style">
      <div className="relative isolate flex h-48 items-start overflow-hidden border-b-2 border-stroke bg-[#f2efe7] p-5 text-[#17140f] sm:h-52 sm:items-end sm:p-6">
        <div aria-hidden="true" className="absolute -top-3 -left-1 -z-10 grid text-[5.75rem] leading-[0.84] font-black tracking-tight whitespace-nowrap text-[#17140f]/[0.07] select-none sm:text-[6.5rem]">
          <span>{ghostWord[style.archetype]}</span>
          <span>{ghostWord[style.archetype]}</span>
          <span>{ghostWord[style.archetype]}</span>
        </div>
        <img src={`/cards/${style.archetype}.png`} alt="" className="style-figure absolute right-3 bottom-0 -z-10 max-h-[72%] max-w-[62%] object-contain object-bottom sm:right-8 sm:max-h-[94%] sm:max-w-[48%]" />
        <div className="grid max-w-[80%] gap-1 sm:max-w-[50%]">
          <p className="kicker">{t('Play style')}</p>
          <h2 id="style" className="text-title sm:text-display">{t(info.name)}</h2>
        </div>
      </div>
      <div className="grid gap-5 p-5 sm:grid-cols-[minmax(0,1fr)_13.5rem] sm:items-center sm:p-6">
        <div className="grid content-start gap-4">
          <p className="text-headline">{t(info.line)}</p>
          <dl className="flex flex-wrap gap-2">
            {[[t('Best shot'), t(questionTitle(style.bestShot))], [t('Best partner'), partner]].map(([label, value]) => (
              <div key={label} className="grid gap-0.5 rounded-control border-2 border-stroke bg-surface px-3 py-2 text-ink shadow-low">
                <dt className="text-caption text-ink-secondary">{label}</dt>
                <dd className="text-subhead font-black">{value}</dd>
              </div>
            ))}
          </dl>
        </div>
        <Radar scores={style.scores} />
      </div>
    </section>
  );
}

/** 六项能力的雷达图（满格是 6 级，问卷最高到 6+）：形状从中心长出来 */
function Radar({ scores }: { scores: Record<Axis, number> }) {
  const [size, center, radius] = [224, 112, 70];
  const point = (i: number, r: number) => {
    const angle = ((-90 + i * 60) * Math.PI) / 180;
    return [center + r * Math.cos(angle), center + r * Math.sin(angle)];
  };
  const reach = (i: number) => (radius * Math.max(0.3, Math.min(6, scores[axes[i]]))) / 6;
  const shape = (r: (i: number) => number) => axes.map((_, i) => point(i, r(i)).join(',')).join(' ');
  return (
    <figure className="grid justify-items-center">
      <svg viewBox={`0 0 ${size} ${size}`} className="w-full max-w-[14rem]" role="img" aria-label={axes.map((a) => `${t(axisNames[a])} ${axisLevel(scores[a])}`).join(', ')}>
        {[2, 4, 6].map((level) => (
          <polygon key={level} points={shape(() => (radius * level) / 6)} fill="none" stroke="currentColor" strokeOpacity={0.3} strokeWidth={1.5} />
        ))}
        {axes.map((axis, i) => {
          const [x, y] = point(i, radius);
          return <line key={axis} x1={center} y1={center} x2={x} y2={y} stroke="currentColor" strokeOpacity={0.18} strokeWidth={1.5} />;
        })}
        <g className="radar-shape" style={{ transformOrigin: `${center}px ${center}px` }}>
          <polygon points={shape(reach)} fill="currentColor" fillOpacity={0.3} stroke="currentColor" strokeWidth={3} strokeLinejoin="round" />
          {axes.map((axis, i) => {
            const [x, y] = point(i, reach(i));
            return <circle key={axis} cx={x} cy={y} r={4} fill="currentColor" />;
          })}
        </g>
        {axes.map((axis, i) => {
          const [x, y] = point(i, radius + 24);
          return (
            <text key={axis} x={x} y={y} textAnchor="middle" dominantBaseline="middle" fill="currentColor" className="text-[11px] font-black">
              <tspan>{t(axisNames[axis])}</tspan>
              <tspan x={x} dy="13">{axisLevel(scores[axis])}</tspan>
            </text>
          );
        })}
      </svg>
    </figure>
  );
}

/** 这一档页面的链接：卡片带来的访问加 ?ref=card；中文等界面语言用对应语言的页面 */
export const cardLink = (rating: number) => `${location.origin}${pathPrefixes[currentLocale()]}/levels/${tierSlug(rating)}/?ref=card`;

/** 分享卡片：一张卡，点一下翻面；可选印昵称、头像、网址。能调系统分享就分享，否则保存图片、复制链接。分享的是正在看的那一面 */
function ShareCard({ result, style, profile }: { result: { rating: number; next?: { level: number; skill: string; id: string } }; style: PlayStyle; profile: Profile | null }) {
  const locale = useLocale();
  const [face, setFace] = useState<CardFace>('front');
  const [name, setName] = useState(profile ? profile.nickname : '');
  const [withLink, setWithLink] = useState(true);
  const [withPhoto, setWithPhoto] = useState(true);
  const [images, setImages] = useState<Record<CardFace, { blob: Blob; url: string }>>();
  const [failed, setFailed] = useState(false);
  const latest = useRef(0);
  const level = tier(result.rating);
  const link = cardLink(result.rating);
  const fileName = `badie-level-${tierSlug(result.rating)}${face === 'back' ? '-back' : ''}.png`;
  const photo = profile?.avatar_path;

  useEffect(() => {
    const run = ++latest.current;
    // 打字时等一下再画
    const timer = setTimeout(async () => {
      try {
        const [art, avatar] = await Promise.all([
          loadArt(style.archetype),
          // 头像取不到就不印，卡片照样出
          photo && withPhoto ? loadImage(avatarUrl(photo)).catch(() => undefined) : undefined,
          fontsReady(),
        ]);
        const input = cardInput({ result, style, profile, name, withLink, art, avatar });
        const [front, back] = await Promise.all([renderCard('front', input), renderCard('back', input)]);
        if (run !== latest.current) return;
        setFailed(false);
        setImages((old) => {
          if (old) Object.values(old).forEach((image) => URL.revokeObjectURL(image.url));
          return { front: { blob: front, url: URL.createObjectURL(front) }, back: { blob: back, url: URL.createObjectURL(back) } };
        });
      } catch {
        if (run === latest.current) setFailed(true);
      }
    }, images ? 250 : 0);
    return () => clearTimeout(timer);
  }, [name, withLink, withPhoto, photo, locale, style.archetype, result.rating]);

  const image = images?.[face];
  const file = image && new File([image.blob], fileName, { type: 'image/png' });
  const canShare = Boolean(file && typeof navigator.share === 'function' && navigator.canShare?.({ files: [file] }));
  const flip = () => setFace((current) => (current === 'front' ? 'back' : 'front'));

  async function share() {
    try {
      await navigator.share({ files: [file!], text: `${t('I’m level {level} on Badie. What’s yours?', { level: level.label })} ${link}` });
    } catch (error) {
      if ((error as Error).name !== 'AbortError') toast(t('Couldn’t open sharing. Save the image instead.'));
    }
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      toast(t('Link copied'));
    } catch {
      toast(link);
    }
  }

  return (
    <section className="sticker grid gap-4 p-5 sm:p-6" aria-labelledby="share">
      <h2 id="share" className="text-title3">{t('Level card')}</h2>
      <div className="grid justify-items-center gap-3 rounded-[16px] bg-surface-muted p-4">
        {images ? (
          // 两面背靠背叠在一起，翻面时整张转半圈；点卡片和点“翻面”一样
          <div className="w-full max-w-[20rem] cursor-pointer [perspective:1200px]" onClick={flip}>
            <div className={`relative aspect-[4/5] transition-transform duration-500 [transform-style:preserve-3d] motion-reduce:transition-none ${face === 'back' ? '[transform:rotateY(180deg)]' : ''}`}>
              {(['front', 'back'] as const).map((side) => (
                <img key={side} src={images[side].url} alt={t(side === 'front' ? 'Front of the level card' : 'Back of the level card')} aria-hidden={side !== face}
                     className={`absolute inset-0 size-full rounded-[14px] shadow-lg [backface-visibility:hidden] ${side === 'back' ? '[transform:rotateY(180deg)]' : ''}`} />
              ))}
            </div>
          </div>
        ) : failed ? (
          <p role="alert" className="p-6 text-subhead">{t('Couldn’t make the image. Try again.')}</p>
        ) : (
          <span aria-hidden="true" className="grid aspect-[4/5] w-full max-w-[20rem] place-items-center">
            <span className="size-6 animate-spin rounded-full border-[3px] border-ink-secondary border-t-transparent" />
          </span>
        )}
        {images && <Button variant="quiet" onClick={flip}>{t('Flip')}</Button>}
      </div>
      <label className="grid gap-1.5">
        <span className="text-subhead font-bold">{t('Name on the card')}</span>
        <input className="field" maxLength={12} value={name} onChange={(e) => setName(e.target.value)} autoComplete="nickname" />
        <span className="text-footnote text-ink-secondary">{t('Optional. It stays on this device.')}</span>
      </label>
      {photo && (
        <label className="flex cursor-pointer items-center gap-3">
          <input type="checkbox" checked={withPhoto} onChange={(e) => setWithPhoto(e.target.checked)} className="size-5 accent-[#17140f]" />
          <span className="text-subhead font-bold">{t('Show my photo on the card')}</span>
        </label>
      )}
      <label className="flex cursor-pointer items-start gap-3">
        <input type="checkbox" checked={withLink} onChange={(e) => setWithLink(e.target.checked)} className="mt-1 size-5 accent-[#17140f]" />
        <span className="grid gap-0.5">
          <span className="text-subhead font-bold">{t('Show the link on the card')}</span>
          <span className="text-footnote text-ink-secondary">{t('Turn it off for apps that don’t allow links. The card then says to search for Badie on the App Store.')}</span>
        </span>
      </label>
      <div className="flex flex-wrap gap-3">
        {canShare && <Button className="button-lg" onClick={share}><Icon name="share" className="size-5" />{t('Share')}</Button>}
        {image && <a href={image.url} download={fileName} className={`button button-lg ${canShare ? 'button-quiet' : ''}`}>{t('Save image')}</a>}
        <Button className="button-lg" variant="quiet" onClick={copy}>{t('Copy link')}</Button>
      </div>
    </section>
  );
}

/** 卡片上的文字按当前界面语言翻译好 */
function cardInput({ result, style, profile, name, withLink, art, avatar }: {
  result: { rating: number; next?: { level: number; skill: string; id: string } };
  style: PlayStyle;
  profile: Profile | null;
  name: string;
  withLink: boolean;
  art: HTMLImageElement;
  avatar?: HTMLImageElement;
}): CardInput {
  const info = archetypeInfo[style.archetype];
  const level = tier(result.rating);
  const trimmed = name.trim();
  // 用自己的昵称时带上编号（昵称#0042）
  const printed = trimmed ? (profile && trimmed === profile.nickname ? `${trimmed}${tagText(profile.tag)}` : trimmed) : undefined;
  const partner = info.partner ? t(archetypeInfo[info.partner].name) : t('Anyone works');
  const region = profile?.country_code ? new Intl.DisplayNames([currentLocale()], { type: 'region' }).of(profile.country_code) : undefined;
  const mode = profile?.preferred_mode ?? null;
  const free = freeSummary(profile?.usual_times);
  const rows = [
    mode && { label: t('Preference'), value: t(mode === 'singles' ? 'Singles' : 'Doubles') },
    free && { label: t('Free times'), value: free },
    { label: t('Best partner'), value: partner },
  ].filter(Boolean) as { label: string; value: string }[];
  return {
    archetype: style.archetype,
    locale: currentLocale(),
    label: level.label,
    levelName: level.name,
    status: t('Self-rated'),
    name: printed,
    region,
    mode,
    styleName: t(info.name),
    line: t(info.line),
    bestShot: t(questionTitle(style.bestShot)),
    scores: style.scores,
    axisNames: Object.fromEntries(axes.map((a) => [a, t(axisNames[a])])) as Record<Axis, string>,
    next: result.next && { title: t('To reach level {n}', { n: result.next.level }), skill: t(result.next.skill) },
    rows,
    text: {
      playStyle: t('Play style'),
      bestShot: t('Best shot'),
      quiz: t('Find your level · 2 min'),
      footer: withLink ? 'BADIE.RSVP/LEVELS' : t('Search Badie badminton on the App Store'),
    },
    art,
    avatar,
  };
}
