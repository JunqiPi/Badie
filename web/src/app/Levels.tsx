import { tier } from './assessment';
import { t } from './i18n';
import { Icon } from './icons';
import { IconTile, LargeTitle, Notice, Tag, fill, type Tint } from './kit';
import { levels } from './levels';
import { Link } from './router';
import { signInFirst } from './Shell';
import type { Profile } from './supabase';

const levelTints: Tint[] = ['mint', 'butter', 'pink', 'lavender', 'sky', 'peach', 'lime', 'lavender', 'butter'];

/** 等级对照表（iOS 的 SkillLevelGuideView）：不用登录也能看 */
export function LevelGuide({ profile }: { profile: Profile | null }) {
  const mine = profile ? tier(profile.rating).level : undefined;
  return (
    <div className="mx-auto grid max-w-3xl gap-5">
      <LargeTitle title={t('Level Chart')} subtitle={t('Badie levels 1–9')} />
      <p className="text-subhead text-ink-secondary">
        {t('Levels 1–9, each split into three tiers (−, base, +), for 27 tiers in total. Each level from 3 to 6 adds one more dimension: can you do the shots → how good are your attacking shots → can you get out of trouble on defensive shots, plus tactics → where you stand in your club. Expand any level to see its skill breakdown (footwork, power, front and back court, attack and defense). Judge by what you can do consistently, not shots you pull off once in a while. 7 and up means state, national, and international level, based only on verifiable results, rankings, and certificates.')}
      </p>

      {profile ? (
        !profile.assessed_at && (
          <Notice icon="list" tint="lime" action={{ label: t('Take the quiz'), to: '/level-quiz/' }}>{t('Not sure? The 2-minute quiz places you.')}</Notice>
        )
      ) : (
        <Notice icon="list" tint="lime" action={{ label: t('Take the quiz'), to: signInFirst('/level-quiz/') }}>{t('Not sure? The 2-minute quiz places you.')}</Notice>
      )}

      <dl className="tile grid gap-1.5 bg-surface-muted p-4 text-footnote">
        {[['−', 'Just reached this level; some strokes aren’t consistent yet'], [t('Base'), 'Consistently does everything at this level'], ['+', 'Solid at this level, with some next-level skills']].map(([mark, meaning]) => (
          <div key={mark} className="flex gap-3">
            <dt className="w-10 shrink-0 font-black">{mark}</dt>
            <dd>{t(meaning)}</dd>
          </div>
        ))}
        <p className="mt-1 text-caption text-ink-secondary">{t('From level 7 up, the gaps are big, so each tier has its own name and is set by evidence.')}</p>
      </dl>

      <section className="sticker grid gap-2 p-5">
        <h2 className="text-title3">{t('Men’s and women’s levels')}</h2>
        <p className="text-subhead text-ink-secondary">
          {t('Men and women are rated on separate ladders, the way clubs and tournaments do it: a women’s 4 is a strong player among women. When men and women play together, Badie counts a women’s level about 1.5 levels lower (a men’s 3 usually beats a women’s 4 in singles), so mixed games stay even. You can also choose to play only with women or only with men.')}
        </p>
      </section>

      <ol className="grid gap-3">
        {levels.map((l) => (
          <li key={l.level} id={`level-${l.level}`} className={`sticker grid gap-3 p-4 ${l.level === mine ? 'bg-lime/35' : ''}`}>
            {/* 手机上放不下时，标签换到下一行 */}
            <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
              <span className={`grid size-11 shrink-0 place-items-center rounded-[12px] border-2 border-stroke text-title3 ${fill[levelTints[l.level - 1]]}`}>{l.level}</span>
              <div className="min-w-0 flex-1 basis-40">
                <h2 className="text-headline">{t(l.name)}</h2>
                <p className="text-caption text-ink-secondary">{[l.usFlight && `≈ ${t(l.usFlight)}`, t(l.experience)].filter(Boolean).join(' · ')}</p>
              </div>
              {l.level === mine ? <Tag tint="lime">{t('You’re here')}</Tag> : l.level > 6 && <Tag icon="lock" tint="muted">{t('Verification required')}</Tag>}
            </div>
            <ul className="grid gap-1.5">
              {l.anchors.map((a) => (
                <li key={a} className="flex gap-2 text-subhead">
                  <span aria-hidden="true" className="mt-2 size-1.5 shrink-0 rounded-full bg-ink" />
                  {t(a)}
                </li>
              ))}
            </ul>
            {l.notes.length > 0 && (
              <details className="group" open={l.level === mine}>
                <summary className="flex min-h-9 cursor-pointer list-none items-center gap-1.5 text-footnote font-bold text-ink-secondary hover:text-ink [&::-webkit-details-marker]:hidden">
                  <Icon name="list" className="size-4" />
                  {t('Skill breakdown ({n})', { n: l.notes.length })}
                  <Icon name="chevronDown" className="ml-auto size-3.5 transition-transform group-open:rotate-180" />
                </summary>
                <dl className="mt-2 grid gap-2 rounded-[12px] bg-surface-muted p-3 text-footnote">
                  {l.notes.map(([name, text]) => (
                    <div key={name} className="grid gap-x-3 sm:grid-cols-[7rem_1fr]">
                      <dt className="font-bold">{t(name)}</dt>
                      <dd>{t(text)}</dd>
                    </div>
                  ))}
                </dl>
              </details>
            )}
            {l.level > 6 && (
              <Link to={profile ? '/verification/' : signInFirst('/verification/')} className="text-footnote font-bold underline underline-offset-4">
                {t('Apply for verification')}
              </Link>
            )}
          </li>
        ))}
      </ol>
      <p className="text-caption text-ink-tertiary">
        {t('Breakdowns follow the level descriptions shared on the Zhongyu Online forum, USTA NTRP and public tournament results.')}
      </p>
    </div>
  );
}

/** 为什么做 Badie：不敢开口找人、固定球友有事、刚到新地方（首页和关于页共用）。白底，和下面彩色的步骤分开 */
const reasons: { icon: Parameters<typeof Icon>[0]['name']; tint: Tint; title: string; text: string }[] = [
  { icon: 'hand', tint: 'lavender', title: 'Too shy to ask around',
    text: 'Walking up to strangers at the gym or asking online takes nerve, and you never know their level until you’re on court. Badie does the asking and matches you by level.' },
  { icon: 'swap', tint: 'peach', title: 'Your usual partner can’t make it',
    text: 'Don’t sit the night out. Quick Match looks for someone at your level for the same time, or try a last-minute game with players who are free right now.' },
  { icon: 'compass', tint: 'mint', title: 'New in town',
    text: 'Moved for school or work? See the courts nearby, join a weekly group and meet players at your level in your first week.' },
];

export function Reasons({ heading: Heading = 'h2' }: { heading?: 'h2' | 'h3' }) {
  return (
    <ul className="grid gap-4 lg:grid-cols-3">
      {reasons.map((r) => (
        <li key={r.title} className={`sticker grid content-start gap-3 p-6 ${fill.surface}`}>
          <IconTile icon={r.icon} tint={r.tint} size="lg" />
          <Heading className="text-title3">{t(r.title)}</Heading>
          <p className="text-subhead">{t(r.text)}</p>
        </li>
      ))}
    </ul>
  );
}

/** 关于 Badie：免费、隐私、靠谱、数据来源 */
const facts: { icon: Parameters<typeof Icon>[0]['name']; tint: Tint; title: string; text: string }[] = [
  { icon: 'heart', tint: 'pink', title: 'Free to use', text: 'Every feature is free. Badie exists to get more people playing even games.' },
  { icon: 'eyeSlash', tint: 'sky', title: 'Private by default', text: 'Your exact location never leaves your device. Players see your nickname and level, not your contact details.' },
  { icon: 'reliable', tint: 'mint', title: 'Reliability counts', text: 'No-shows and late cancellations are tracked, so the players you meet actually turn up.' },
  { icon: 'map', tint: 'butter', title: 'Where court data comes from', text: 'Government open data, OpenStreetMap and players themselves. Players confirm courts they’ve played at.' },
];

/** 关于页和首页共用：免费、隐私、靠谱、数据来源 */
export function AboutFacts({ className = 'sm:grid-cols-2', heading: Heading = 'h2' }: { className?: string; heading?: 'h2' | 'h3' }) {
  return (
    <ul className={`grid gap-3 ${className}`}>
      {facts.map((f) => (
        <li key={f.title} className={`sticker grid content-start gap-2 p-5 ${fill[f.tint]}`}>
          <Icon name={f.icon} className="size-7" />
          <Heading className="text-title3">{t(f.title)}</Heading>
          <p className="text-subhead">{t(f.text)}</p>
        </li>
      ))}
    </ul>
  );
}

export function About() {
  return (
    <div className="mx-auto grid max-w-3xl gap-6">
      <LargeTitle title={t('About Badie')} subtitle={t('Built by a player, for players')} />
      <section aria-labelledby="story" className="grid gap-3">
        <h2 id="story" className="text-title2">{t('Why we built Badie')}</h2>
        <p className="max-w-prose text-[1.0625rem] leading-relaxed">{t('Badie began with its founder, who was too shy to walk up to strangers at the gym or ask for a game online. Even when a game came together, there was no telling whether the other side would be far better or just starting out.')}</p>
        <p className="max-w-prose text-[1.0625rem] leading-relaxed">{t('Plenty of players feel the same, so they play less than they’d like. Others lose their game when a regular partner can’t make it, or move somewhere new and don’t know anyone. In the US and Europe, where badminton communities are still small, that keeps courts quieter than they should be.')}</p>
        <p className="max-w-prose text-[1.0625rem] leading-relaxed">{t('So Badie does the finding for you. Tell it when you’re free and which courts you can reach, and it matches you with players at your level.')}</p>
      </section>
      <p className={`sticker p-5 text-title3 ${fill.lime}`}>{t('Our goal: more people playing badminton in the US and Europe, more often.')}</p>
      <section aria-labelledby="moments" className="grid gap-3">
        <h2 id="moments" className="text-title2">{t('Made for moments like these')}</h2>
        <Reasons heading="h3" />
      </section>
      <section aria-labelledby="promises" className="grid gap-3">
        <h2 id="promises" className="text-title2">{t('What you can count on')}</h2>
        <AboutFacts heading="h3" />
      </section>
      <section className="sticker grid gap-3 bg-[#17140f] p-5 text-[#f5f0e6]">
        <h2 className="text-title3">{t('Play from any browser')}</h2>
        <p className="text-subhead">{t('Badie works on the web on any phone or computer, no download needed. The iPhone app is in testing.')}</p>
        <Link to="/" className="button justify-self-start">{t('Open Badie')}</Link>
      </section>
      <p className="flex gap-4 text-footnote font-bold">
        <Link to="/privacy/" className="link">{t('Privacy Policy')}</Link>
        <Link to="/terms/" className="link">{t('Terms of Service')}</Link>
        <Link to="/contact/" className="link">{t('Contact us')}</Link>
      </p>
    </div>
  );
}
