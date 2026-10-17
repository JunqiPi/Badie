// 定级问卷：与 iOS SkillAssessment.swift 同一套题和算法（见 Badie-iOS/docs/DESIGN.md §13.3）。
// 技术题定出 4+ 以内的档位，再按台阶往上推：5 看被动球和战术，6 看俱乐部里的位置；经历给保底。最高 6+

const third = 1 / 3;

type Kind = 'technique' | 'ladder' | 'experience' | 'recency';
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
    ['Reaches the back court but not the baseline; slow', 3],
    ['Consistently hits baseline to baseline in play', 4],
    ['Can hit both attacking and high clears, controlling height and placement', 5],
    ['Same motion as your drops and smashes, so opponents can’t read you', 6],
  ]),
  q('smash', 'technique', 'Forehand smash', 'Smashing from the back court when you get the chance:', [
    ['Can’t smash, or smashes go into the net or out', 2],
    ['Can hit down, but without much power', 3],
    ['Smashes go down with angle, but aren’t hard to return', 4],
    ['Threatening smashes straight and cross-court, follows up at the net', 5],
    ['Has hard, sliced and stick smashes, picks based on opponent position', 6],
  ]),
  q('drop', 'technique', 'Forehand drop shot', 'Can you hit drop shots? Sliced drops or reverse slices?', [
    ['Can’t hit drops yet', 2],
    ['Drops clear the net but are often high or long', 3],
    ['Straight and cross-court drops land near the short service line', 4],
    ['Can hit either a sliced drop or a reverse slice', 5],
    ['Comfortable with sliced drops and reverse slices, disguised like clears and smashes', 6],
  ]),
  q('backhand', 'technique', 'Backhand back court', 'When the shuttle goes to your backhand back court:', [
    ['Can only hit it round-the-head, or gives up on it', 2],
    ['Can hit backhand, but only to midcourt', 3],
    ['Can return it to mid or back court when not under pressure', 4],
    ['Hits backhand drops straight and cross-court; back-court to back-court comes fairly easily', 5],
    ['Backhand clears baseline to baseline, comfortable with backhand sliced drops', 6],
  ]),
  q('net', 'technique', 'Net play', 'Net drops, net spins, cross-court net shots:', [
    ['Soft touch; sometimes high or long, often doesn’t clear the net', 2],
    ['Net drops stay tight; just starting net spins and cross-court net shots', 3],
    ['Net spins on both sides, uses cross-court net shots often but not tight enough', 4],
    ['Skilled net spins, can open-spin and push to the back', 5],
    ['Fluent net spins, cross-court net shots, pushes and net kills with consistent motion', 6],
  ]),
  q('drive', 'technique', 'Drives', 'A fast flat shot comes at you in midcourt:', [
    ['Can rarely return it', 2],
    ['Can block it back, but without pace', 3],
    ['Can trade a few drives', 4],
    ['Good at drives and can speed up the exchange', 5],
    ['Holds up in fast drive exchanges; can drive to the baseline even from low, defensive positions', 6],
  ]),
  q('footwork', 'technique', 'Footwork', 'How you move on court:', [
    ['Walks to reach the shuttle', 1],
    ['Runs for the shuttle, but without set footwork', 2],
    ['Knows chassé and lunge steps; reaches all six corners, but not smoothly', 3],
    ['Correct footwork all over the court, but not fast enough off the mark', 4],
    ['Easy footwork all over the court; above-average first step and speed', 5],
    ['Footwork is instinctive, with no blind spots on court', 6],
  ]),
  q('passive', 'ladder', 'Defense under pressure', 'When returning hard smashes, or pushed to the baseline or into corners:', [
    'Rarely gets it back, or makes an error',
    'Can only block straight to the net or lift, can’t change direction; easy points for the opponent',
    'Sometimes recovers: returns deep or to the net to get back in position',
    'Solid defense, returns mostly on target, escapes most pressure',
    'Defends smashes that aren’t clear winners with controlled placement, and counter-drives average smashes',
  ]),
  q('doubles', 'ladder', 'Doubles', 'In doubles, how well do you handle positioning and teamwork?', [
    'Not sure where to stand',
    'Knows front-back in attack, side-by-side in defense',
    'Basic awareness of serve and return, covering, and net coverage',
    'Takes the net aggressively and keeps attacking from the back',
    'Finds opponents’ gaps and coordination blind spots',
  ]),
  q('stability', 'ladder', 'Consistency', 'How often do you make errors in rallies and games?', [
    'Rallies break down before 5 shots',
    'Can keep a slow rally going for 5–10 shots',
    'Can rally 10+ shots, but errors pile up when play speeds up',
    'Fewer errors in games than before, but still tight on big points',
    'Steady in long rallies, rarely makes unforced errors',
    'Still solid in a high-intensity third game',
  ]),
  q('tactics', 'ladder', 'Tactics', 'How do you mainly win points in games?', [
    'Mostly just getting it over and waiting for errors',
    'Targets the opponent’s weak spots (like the backhand)',
    'Moves opponents around with placement and pace: pushing deep, dropping short',
    'Combines tactics and skill: builds attacks with deception and direction changes, adapts to opponents',
    'Plans a game plan for each opponent and executes it on court',
  ]),
  q('standing', 'ladder', 'Standing in your club', 'Compared with the club or regular games you usually play in, where do you stand?', [
    'Mostly mid-to-lower finishes',
    'Middle of the pack, trades points with most people',
    'Upper half, beats most people',
    ['Rising star: trades wins with the strongest players', 6 - third],
    ['Near the top: rarely lose regular games, people ask you for tips', 6],
    ['Club ace: a core player in club matches, starting to play amateur / semi-pro tournaments', 6 + third],
  ]),
  q('experience', 'experience', 'Tournaments & training', 'Pick the highest that applies:', [
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

const techniqueIds = questions.filter((x) => x.kind === 'technique').map((x) => x.id);
const list = (names: string[]) => new Intl.ListFormat('en').format(names.map((n) => n.toLowerCase()));

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

  // 1. 技术题：“全部”看最弱的，“多数”看第 3 弱的，“一两项”看第 2 强的
  const dimensions = techniqueIds.map((id) => ({ name: questions.find((x) => x.id === id)!.title, level: value(id)! }));
  const levels = dimensions.map((d) => d.level).sort((a, b) => a - b);
  const [all, , most] = levels;
  const topTwo = levels[levels.length - 2];
  const below = (level: number) => list(dimensions.filter((d) => d.level < level).map((d) => d.name));

  let rating: number;
  let gate: string | undefined;
  if (all >= 4) {
    rating = topTwo >= 5 && option('stability') >= 3 ? 4 + third : 4;
  } else if (all === 3) {
    rating = most >= 4 ? 4 - third : topTwo >= 4 ? 3 + third : 3;
    gate = `To reach level 4, work on ${below(4)}.`;
  } else {
    rating = most >= 3 ? 3 - third : most >= 2 ? (topTwo >= 3 ? 2 + third : 2) : topTwo >= 2 ? 2 - third : 1 + third;
    gate = `To reach level 3, work on ${below(3)}.`;
  }
  // 4 级还要有双打的基本意识
  if (rating >= 4 - 0.01 && option('doubles') < 2) {
    rating = 4 - third;
    gate = 'To reach level 4, build basic doubles awareness: serve and return, covering, and net coverage.';
  }

  // 2. 被动球：4+ 之后，有时能过渡出来 → 5−；多数能摆脱、并会用落点和节奏 → 5
  if (rating >= 4 + third - 0.01 && option('passive') >= 2) {
    rating = option('passive') >= 3 && option('tactics') >= 2 ? 5 : 5 - third;
  }
  // 3. 战术和技巧明显结合 → 5+
  if (rating >= 5 - 0.01 && option('tactics') >= 3) rating = 5 + third;

  // 4. 6 级：俱乐部位置 + 技术（多数分项到 5 级、多拍很稳；6 要有一两项到 6 级；6+ 要有比赛经历）
  const standing = value('standing');
  if (rating >= 5 + third - 0.01 && standing !== undefined) {
    if (most >= 5 && option('stability') >= 4) {
      let reached = Math.min(standing, 6 - third);
      if (standing >= 6 - 0.01) {
        if (topTwo >= 6) reached = 6;
        else gate = 'To reach level 6, get one or two skills to level 6 (signature shots).';
      }
      if (standing >= 6 + third - 0.01 && reached >= 6 - 0.01) {
        if (option('experience') >= 3) reached = 6 + third;
        else gate = 'To reach 6+, you need tournament or junior training experience.';
      }
      rating = reached;
    } else {
      gate = 'To reach 6−, get most skills to level 5 and stay steady in long rallies.';
    }
  }

  // 5. 经历保底（回归球友减 1 级）
  const floor = (value('experience') ?? 1) - (isReturning ? 1 : 0);
  return {
    rating: Math.min(Math.max(rating, floor, 1 - third), 6 + third),
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
  return { level, label: `${level}${modifier < 0 ? '−' : modifier > 0 ? '+' : ''}`, name: names[level - 1], summary: summaries[level - 1] };
}
