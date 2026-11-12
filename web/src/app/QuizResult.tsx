import { useEffect, useMemo, useRef, useState } from 'react';
import { archetypeInfo, axes, axisLevel, axisNames, evaluate, playStyle, questionTitle, tier, tierSlug, type Axis, type PlayStyle } from './assessment';
import { currentLocale, pathPrefixes, t, useLocale } from './i18n';
import { Icon } from './icons';
import { Segmented, Starburst, Tag } from './kit';
import { fontsReady, loadArt, renderCard, type CardInput, type CardSize } from './levelCard';
import { clearPending, loadPending, saveArgs, validAnswers } from './quizStore';
import { Link, navigate } from './router';
import { signInFirst } from './Shell';
import { problem, supabase, tagText, type Profile } from './supabase';
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
    clearPending();
    onProfile(data as Profile);
    toast(t('Level saved.'));
  }

  return (
    <div className="mx-auto grid max-w-2xl gap-6">
      <section className="sticker animate-enter grid justify-items-center gap-2 bg-lime p-6 text-center text-on-accent sm:p-8" aria-labelledby="result">
        <p className="kicker">{t('Your level')}</p>
        <h1 id="result" className="outline-none">
          <Starburst tint="butter" size={128}>{level.label}</Starburst>
        </h1>
        <p className="text-title2">{level.name}</p>
        <p className="max-w-md text-subhead font-semibold">{level.summary}</p>
        <Tag tint="surface">{t('Self-rated')}</Tag>
      </section>

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

/** 打法：名字、一句话、六项能力的雷达图、最强一拍、最佳搭档 */
function PlayStyleCard({ style }: { style: PlayStyle }) {
  const info = archetypeInfo[style.archetype];
  const partner = info.partner ? t(archetypeInfo[info.partner].name) : t('Anyone works');
  return (
    <section className="sticker grid gap-4 p-5 sm:grid-cols-[minmax(0,1fr)_14rem] sm:items-center sm:p-6" style={{ background: info.color, color: info.ink }} aria-labelledby="style">
      <div className="grid content-start gap-3">
        <p className="kicker">{t('Play style')}</p>
        <h2 id="style" className="text-title">{t(info.name)}</h2>
        <p className="text-subhead font-semibold">{t(info.line)}</p>
        <dl className="grid grid-cols-2 gap-3 text-subhead">
          <div><dt className="text-caption opacity-80">{t('Best shot')}</dt><dd className="font-black">{t(questionTitle(style.bestShot))}</dd></div>
          <div><dt className="text-caption opacity-80">{t('Best partner')}</dt><dd className="font-black">{partner}</dd></div>
        </dl>
      </div>
      <Radar scores={style.scores} />
    </section>
  );
}

/** 六项能力的雷达图（满格是 6 级，问卷最高到 6+） */
function Radar({ scores }: { scores: Record<Axis, number> }) {
  const [size, center, radius] = [224, 112, 70];
  const point = (i: number, r: number) => {
    const angle = ((-90 + i * 60) * Math.PI) / 180;
    return [center + r * Math.cos(angle), center + r * Math.sin(angle)];
  };
  const shape = (r: (i: number) => number) => axes.map((_, i) => point(i, r(i)).join(',')).join(' ');
  return (
    <figure className="grid justify-items-center">
      <svg viewBox={`0 0 ${size} ${size}`} className="w-full max-w-[14rem]" role="img" aria-label={axes.map((a) => `${t(axisNames[a])} ${axisLevel(scores[a])}`).join(', ')}>
        {[2, 4, 6].map((level) => (
          <polygon key={level} points={shape(() => (radius * level) / 6)} fill="none" stroke="currentColor" strokeOpacity={0.3} strokeWidth={1.5} />
        ))}
        <polygon points={shape((i) => (radius * Math.max(0.3, Math.min(6, scores[axes[i]]))) / 6)} fill="currentColor" fillOpacity={0.28} stroke="currentColor" strokeWidth={3} strokeLinejoin="round" />
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

/** 分享卡片：两种尺寸，可选印昵称、印不印网址；能调系统分享就分享，否则保存图片、复制链接 */
function ShareCard({ result, style, profile }: { result: { rating: number; next?: { level: number; skill: string; id: string } }; style: PlayStyle; profile: Profile | null }) {
  const locale = useLocale();
  const [size, setSize] = useState<CardSize>('post');
  const [name, setName] = useState(profile ? profile.nickname : '');
  const [withLink, setWithLink] = useState(true);
  const [image, setImage] = useState<{ blob: Blob; url: string }>();
  const [failed, setFailed] = useState(false);
  const latest = useRef(0);
  const level = tier(result.rating);
  const link = cardLink(result.rating);
  const fileName = `badie-level-${tierSlug(result.rating)}.png`;

  useEffect(() => {
    const run = ++latest.current;
    // 打字时等一下再画
    const timer = setTimeout(async () => {
      try {
        const [art] = await Promise.all([loadArt(style.archetype), fontsReady()]);
        const blob = await renderCard(size, cardInput({ result, style, profile, name, withLink, art }));
        if (run !== latest.current) return;
        setFailed(false);
        setImage((old) => {
          if (old) URL.revokeObjectURL(old.url);
          return { blob, url: URL.createObjectURL(blob) };
        });
      } catch {
        if (run === latest.current) setFailed(true);
      }
    }, image ? 250 : 0);
    return () => clearTimeout(timer);
  }, [size, name, withLink, locale, style.archetype, result.rating]);

  const file = image && new File([image.blob], fileName, { type: 'image/png' });
  const canShare = Boolean(file && typeof navigator.share === 'function' && navigator.canShare?.({ files: [file] }));

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
      <Segmented
        label={t('Card size')}
        value={size}
        onChange={setSize}
        options={[{ value: 'post', label: t('Post') }, { value: 'story', label: t('Story') }]}
      />
      <div className="grid justify-items-center rounded-[16px] bg-surface-muted p-3">
        {image ? (
          <img src={image.url} alt={t('Level card')} className={`w-full rounded-[8px] ${size === 'post' ? 'max-w-[20rem]' : 'max-w-[16rem]'}`} />
        ) : failed ? (
          <p role="alert" className="p-6 text-subhead">{t('Couldn’t make the image. Try again.')}</p>
        ) : (
          <span aria-hidden="true" className={`grid w-full place-items-center ${size === 'post' ? 'aspect-[4/5] max-w-[20rem]' : 'aspect-[9/16] max-w-[16rem]'}`}>
            <span className="size-6 animate-spin rounded-full border-[3px] border-ink-secondary border-t-transparent" />
          </span>
        )}
      </div>
      <label className="grid gap-1.5">
        <span className="text-subhead font-bold">{t('Name on the card')}</span>
        <input className="field" maxLength={12} value={name} onChange={(e) => setName(e.target.value)} autoComplete="nickname" />
        <span className="text-footnote text-ink-secondary">{t('Optional. It stays on this device.')}</span>
      </label>
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
function cardInput({ result, style, profile, name, withLink, art }: {
  result: { rating: number; next?: { level: number; skill: string; id: string } };
  style: PlayStyle;
  profile: Profile | null;
  name: string;
  withLink: boolean;
  art: CanvasImageSource;
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
    partner,
    scores: style.scores,
    axisNames: Object.fromEntries(axes.map((a) => [a, t(axisNames[a])])) as Record<Axis, string>,
    next: result.next && { title: t('To reach level {n}', { n: result.next.level }), skill: t(result.next.skill) },
    rows,
    text: {
      playStyle: t('Play style'),
      bestShot: t('Best shot'),
      bestPartner: t('Best partner'),
      levelStatus: t('Level · self-rated'),
      quiz: t('Find your level · 2 min'),
      noSignup: t('Find your level · No sign-up'),
      hashtag: t('#MyBadmintonCard'),
      footer: withLink ? 'BADIE.RSVP/LEVELS' : t('Search Badie badminton on the App Store'),
    },
    art,
  };
}
