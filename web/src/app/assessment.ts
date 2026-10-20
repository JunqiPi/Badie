// 定级问卷：与 iOS SkillAssessment.swift 同一套题和算法（见 Badie-iOS/docs/DESIGN.md §13.3）。
// 每个选项对应一个等级（可以是 2.5 这样的半级）。技术、比赛能力各取平均，但不能比自己最弱的一项高出 1 级以上；
// 两者以弱的为准，强的那边最多再加 2/3 级。5+ 往上看在俱乐部里的位置，6+ 还要有比赛或青训经历。经历给保底。最高 6+

// 带 .ts 后缀：这个文件也直接给 Node 跑单元测试
import { currentLocale, t } from './i18n.ts';

const third = 1 / 3;

type Kind = 'technique' | 'game' | 'standing' | 'experience' | 'recency';
export type Question = { id: string; kind: Kind; title: string; hint: string; options: { text: string; value?: number }[] };

const q = (id: string, kind: Kind, title: string, hint: string, options: (string | [string, number])[]): Question => ({
  id,
  kind,
  title,
  hint,
  options: options.map((o) => (typeof o === 'string' ? { text: o } : { text: o[0], value: o[1] })),
});

export const questions: Question[] = [
  q('clear', 'technique', 'Forehand clear', 'Hitting clears from the back court:', [
    ['Doesn’t reach midcourt', 1],
    ['Mostly lands midcourt', 2],
    ['Reaches the back court but not the baseline; slow', 2.5],
    ['Consistently hits baseline to baseline in play', 3],
    ['Knows attacking clears from high clears and when to use each; controls height and placement', 4],
    ['Same motion as your drops and smashes, so opponents can’t read you', 6],
  ]),
  q('smash', 'technique', 'Forehand smash', 'Smashing from the back court when you get the chance:', [
    ['Can’t smash, or smashes go into the net or out; often mishits the frame', 1],
    ['Knows how to hit down, but can’t put power through the shuttle', 1.5],
    ['Smashes go down with some pace, but aren’t hard to return', 2.5],
    ['With a good chance, sometimes hits through with power and angle; starting to threaten', 3],
    ['Starting to mix hard, half and stick smashes well, and follows up at the net', 4],
    ['Hard, sliced and stick smashes come naturally; picks one based on where the opponent stands', 6],
  ]),
  q('drop', 'technique', 'Forehand drop shot', 'Can you hit drop shots? Sliced drops or reverse slices?', [
    ['Can’t hit drops yet', 0],
    ['Drops clear the net but are often high or long', 1],
    ['Straight and cross-court drops land near the short service line', 2],
    ['Has a sliced drop or a reverse slice, but not consistent: angle is off and it often floats above the tape, so it gets punished', 3],
    ['Has both sliced drops and reverse slices, but not consistent or fast enough, and sometimes ends up under pressure', 4],
    ['Sliced drops and reverse slices are fluent, disguised like clears and smashes, and fast, dropping right after the net', 6],
  ]),
  q('backhand', 'technique', 'Backhand back court', 'When the shuttle goes to your backhand back court:', [
    ['Can only hit it round-the-head, or gives up on it', 1],
    ['Can hit backhand, but only to mid or front court; once opponents target your backhand you’re under pressure', 2],
    ['When not under pressure, returns from your mid–back court to their back court', 3],
    ['Backhand drops straight and cross-court with enough pace not to get punished; back-court to back-court clears are easy', 5],
    ['Backhand clears baseline to baseline; still very comfortable getting out of trouble with the backhand under pressure', 6],
  ]),
  q('net', 'technique', 'Net play', 'Net drops, net spins, cross-court net shots:', [
    ['Soft touch; sometimes high or long, often doesn’t clear the net', 1],
    ['Net drops stay tight; just starting net spins and cross-court net shots', 2],
    ['Net spins on both sides, uses cross-court net shots often but not tight enough', 3],
    ['Skilled net spins, can open-spin and push to the back', 4],
    ['Fluent net spins, cross-court net shots, pushes and net kills with consistent motion', 6],
  ]),
  q('drive', 'technique', 'Drives', 'A fast flat shot comes at you in midcourt:', [
    ['Can rarely return it', 1],
    ['Can block it back, but without pace', 2],
    ['Can trade a few drives', 2.5],
    ['Good at drives and can speed up the exchange', 4],
    ['Holds up in fast drive exchanges; can drive to the baseline even from low, defensive positions', 6],
  ]),
  q('footwork', 'technique', 'Footwork', 'How you move on court:', [
    ['Walks to reach the shuttle', 1],
    ['Runs for the shuttle, but without set footwork', 1.5],
    ['Knows chassé and lunge steps; reaches all six corners, but not smoothly', 2.5],
    ['Correct footwork all over the court, but not fast enough off the mark or around the court', 3],
    ['Easy footwork all over the court; above-average first step and speed', 4],
    ['Footwork is instinctive, with no blind spots on court', 6],
  ]),
  q('passive', 'game', 'Smash defense & balls under pressure', 'When returning hard smashes, or pushed to the baseline or into corners:', [
    ['Rarely gets it back, or makes an error', 2],
    ['Can only block straight to the net or lift, can’t change direction; easy points for the opponent', 3],
    ['Sometimes recovers: returns to the opponent’s back court or net to get back in position', 4],
    ['Solid defense, returns mostly on target, escapes most pressure', 5],
    ['Defends smashes that aren’t clear winners with controlled placement, and counter-drives average smashes', 6],
  ]),
  q('doubles', 'game', 'Doubles', 'In doubles, how well do you handle positioning and teamwork?', [
    ['Not sure where to stand', 1.5],
    ['Knows front-back in attack, side-by-side in defense', 2.5],
    ['Basic awareness of serve and return, covering, and net coverage', 3.5],
    ['Takes the net aggressively and keeps attacking from the back', 4.5],
    ['Finds opponents’ gaps and coordination blind spots', 6],
  ]),
  q('stability', 'game', 'Consistency', 'How often do you make errors in rallies and games?', [
    ['Rallies break down before 5 shots', 1],
    ['Can keep a slow rally going for 5–10 shots', 2],
    ['Can rally 10+ shots, but errors pile up when play speeds up', 3],
    ['Fewer errors in games than before, but still tight on big points', 4],
    ['Steady in long rallies, rarely makes unforced errors', 5],
    ['Still solid in a high-intensity third game', 6],
  ]),
  q('tactics', 'game', 'Tactics', 'How do you mainly win points in games?', [
    ['Mostly just getting it over and waiting for errors', 2],
    ['Targets the opponent’s weak spots (like the backhand)', 3],
    ['Moves opponents around with placement and pace: pushing deep, dropping short', 4],
    ['Combines tactics and skill: builds sustained attacks with deception and direction changes, adapts to opponents', 5],
    ['Plans a game plan for each opponent and executes it on court', 6],
  ]),
  q('standing', 'standing', 'Standing in your club', 'Compared with the club or regular games you usually play in, where do you stand?', [
    'Mostly mid-to-lower finishes',
    'Middle of the pack, trades points with most people',
    'Upper half, beats most people',
    ['Rising star: trades wins with the strongest players', 6 - third],
    ['Near the top: you rarely lose regular games, and people often ask you for tips', 6],
    ['Club ace: a core player in club matches, starting to play amateur / semi-pro tournaments', 6 + third],
  ]),
  q('experience', 'experience', 'Tournament & training experience', 'Pick the highest that applies', [
    'None',
    ['Taken 20+ lessons', 2],
    ['Played E or D division tournaments', 3],
    ['Top 4 in C / B flight, or 2+ years of junior training', 5 - third],
    ['Played in A flight or Open', 6 - third],
  ]),
  q('recency', 'recency', 'Past year', 'In the past year, have you played at least twice a month on average?', [
    'Yes, I play regularly',
    'No, not much lately (used to play a lot)',
  ]),
];

// 技术名翻译后用当前语言的“和”连起来；英文在句中用小写
const list = (names: string[]) =>
  new Intl.ListFormat(currentLocale()).format(names.map((n) => (currentLocale() === 'en' ? n.toLowerCase() : t(n))));

const toThirds = (rating: number) => Math.round(rating * 3) / 3;
const mean = (values: number[]) => values.reduce((sum, v) => sum + v, 0) / values.length;
/** 一组题的水平：取平均，但不能比最弱的一项高出 1 级以上（短板限制等级） */
const pillar = (values: number[]) => Math.min(mean(values), Math.min(...values) + 1);

export type Assessment = { rating: number; needsCalibration: boolean; isReturning: boolean; limitingGate?: string };

/** answers：题目 id → 选项序号。没答完返回 undefined */
export function evaluate(answers: Record<string, number>): Assessment | undefined {
  if (!questions.every((x) => answers[x.id] !== undefined)) return;
  const option = (id: string) => answers[id];
  const value = (id: string) => questions.find((x) => x.id === id)!.options[option(id)]?.value;
  const isReturning = option('recency') === 1;

  // 0. 完全的新手：高远到不了中场、还没有步法
  if (option('clear') === 0 && option('footwork') === 0) {
    return { rating: option('net') === 0 && option('doubles') === 0 ? 1 - third : 1, needsCalibration: false, isReturning };
  }

  // 1. 技术和比赛能力：各自取平均、受最弱一项限制；两者以弱的为准，强的那边最多加 2/3 级
  const scored = (kind: Kind) => questions.filter((x) => x.kind === kind).map((x) => ({ name: x.title, level: value(x.id)! }));
  const technique = scored('technique');
  const game = scored('game');
  const [low, high] = [pillar(technique.map((d) => d.level)), pillar(game.map((d) => d.level))].sort((a, b) => a - b);
  let rating = toThirds(low + Math.min(2 * third, (high - low) / 2));

  // 2. 下一档要补什么：最弱的几项（最多 3 项）
  // 3− 的下一档是 3，3 和 3+ 的下一档是 4
  const target = rating - Math.floor(rating) > 0.5 ? Math.ceil(rating) : Math.floor(rating) + 1;
  const weakest = [...technique, ...game].filter((d) => d.level < target).sort((a, b) => a.level - b.level).slice(0, 3);
  let gate = weakest.length ? t('To reach level {level}, work on: {skills}', { level: target, skills: list(weakest.map((d) => d.name)) }) : undefined;

  // 3. 6 级看俱乐部里的位置：没到“崭露头角”最高 5+；6+ 还要有比赛或青训经历
  if (rating >= 6 - third - 0.01) {
    const standing = value('standing');
    if (standing === undefined) {
      rating = 5 + third;
      gate = t('To reach 6−: be among the strongest players in your club');
    } else {
      rating = Math.min(standing, rating + third);
      gate = undefined;
      if (rating >= 6 + third - 0.01 && option('experience') < 3) {
        rating = 6;
        gate = t('To reach 6+: you need tournament or junior training experience');
      }
    }
  }

  // 4. 经历保底（回归球友减 1 级）
  const floor = (value('experience') ?? 1) - (isReturning ? 1 : 0);
  return {
    rating: toThirds(Math.min(Math.max(rating, floor, 1 - third), 6 + third)),
    needsCalibration: floor - rating >= 2 - 0.01,
    isReturning,
    limitingGate: floor > rating ? undefined : gate,
  };
}

const names = ['Newbie', 'Beginner', 'Novice', 'Intermediate', 'Upper intermediate', 'Club expert', 'State level', 'National level', 'International level'];
const summaries = [
  'Rallies rarely go past 5 shots.',
  'Serves mostly land in; slow rallies of 5–10 shots.',
  'Learning each stroke; rallies tend to break down after 10+ shots.',
  'Solid on attacking shots from comfortable positions, but loses points under pressure.',
  'Escapes pressure and stretched shots; uses placement and pace to move opponents.',
  'Among the best in the club; no obvious weakness.',
];

/** 3.67 → “4−”。1 级 = 3 档 */
export function tier(rating: number) {
  const step = Math.round(rating * 3);
  const level = Math.round(step / 3);
  const modifier = step - level * 3;
  return { level, label: `${level}${modifier < 0 ? '−' : modifier > 0 ? '+' : ''}`, name: t(names[level - 1]), summary: t(summaries[level - 1] ?? '') };
}

/** 对手平均强弱：“opponents 0.3 levels stronger on average” */
export const gapText = (gap: number) =>
  Math.abs(gap) < 0.05 ? t('opponents about your level')
  : gap > 0 ? t('opponents {n} levels stronger on average', { n: gap.toFixed(1) })
  : t('opponents {n} levels weaker on average', { n: Math.abs(gap).toFixed(1) });


