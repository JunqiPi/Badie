// 等级卡片：在浏览器里用 canvas 画，不经过服务器。版式见 Badie-iOS/docs/LEVEL_CARD.md 和设计稿 v2（照 Valorant 的球员卡）：
// 帖子 1080×1350（海报上斜放正面和背面两张卡），限时动态 1080×1920（角色窗 + 打法面板 + 六格数据）。
// 人物先用剪影占位：public/cards/<打法>.svg，正式插画做好后直接换文件
import { archetypeInfo, axes, axisLevel, type Archetype, type Axis } from './assessment';

export type CardSize = 'post' | 'story';
export const cardSizes: Record<CardSize, [number, number]> = { post: [1080, 1350], story: [1080, 1920] };

/** 卡片上的文字都由调用方翻译好再传进来 */
export type CardInput = {
  archetype: Archetype;
  locale: string;
  /** 4+ */
  label: string;
  /** 中级 */
  levelName: string;
  /** 自评 */
  status: string;
  /** 昵称#编号；不填就不印 */
  name?: string;
  region?: string;
  /** 偏好单打还是双打（右上角两个图标哪个亮）；null = 都行 */
  mode?: 'singles' | 'doubles' | null;
  styleName: string;
  line: string;
  bestShot: string;
  partner: string;
  scores: Record<Axis, number>;
  axisNames: Record<Axis, string>;
  /** 离 5 级还差 → 反手后场 */
  next?: { title: string; skill: string };
  /** 背面的几行（位置、常去球馆、空闲时间、最佳搭档），只放知道的 */
  rows: { label: string; value: string }[];
  text: { playStyle: string; bestShot: string; bestPartner: string; levelStatus: string; quiz: string; noSignup: string; hashtag: string; footer: string };
  art: CanvasImageSource;
};

const ink = '#17140f';
const cream = '#f2efe7';
const gray = '#9a948a';
const red = '#e5484d';
const lime = '#d4f33f';
const gold = '#d9b44a';
const stack = '"Nunito Variable", ui-rounded, system-ui, "PingFang SC", "Hiragino Sans", "Apple SD Gothic Neo", "Noto Sans CJK SC", sans-serif';
const font = (size: number, weight = 900) => `${weight} ${size}px ${stack}`;

/** 鬼影大字（卡片美术区里重复的打法名）：装饰，用英文 */
const ghostWord: Record<Archetype, string> = { cannon: 'CANNON', net: 'NET', wall: 'WALL', quick: 'QUICK', engine: 'ENGINE', captain: 'CAPTAIN', allround: 'ALL-ROUND', rookie: 'ROOKIE' };

// MARK: 颜色

const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const rgba = (hex: string, alpha: number) => `rgba(${rgb(hex).join(',')},${alpha})`;
/** a 往 b 混 amount（0–1） */
function mix(a: string, b: string, amount: number) {
  const [x, y] = [rgb(a), rgb(b)];
  return `#${x.map((v, i) => Math.round(v + (y[i] - v) * amount).toString(16).padStart(2, '0')).join('')}`;
}

/** 每种打法的海报底色、底色上的字、深色卡片上的强调色 */
function palette(archetype: Archetype) {
  const info = archetypeInfo[archetype];
  const allround = archetype === 'allround';
  return {
    background: info.color,
    onBackground: info.ink,
    accent: allround ? gold : info.color,
    band: allround ? '#2a2620' : ink,
    circuit: archetype === 'net' || archetype === 'captain' ? ink : allround ? gold : '#6b4cff',
    glow: allround ? gold : info.color,
    brand: allround ? gold : lime,
  };
}

// MARK: 画图的小工具

function polygon(ctx: CanvasRenderingContext2D, points: [number, number][]) {
  ctx.beginPath();
  points.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
  ctx.closePath();
}

function hexagon(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  polygon(ctx, [[x + w / 2, y], [x + w, y + h / 4], [x + w, y + (h * 3) / 4], [x + w / 2, y + h], [x, y + (h * 3) / 4], [x, y + h / 4]]);
}

/** 字号缩到放得下（最小一半），还放不下就截断加省略号 */
function fitText(ctx: CanvasRenderingContext2D, text: string, maxWidth: number, size: number, weight = 900) {
  let current = size;
  ctx.font = font(current, weight);
  while (ctx.measureText(text).width > maxWidth && current > size / 2) {
    current -= 1;
    ctx.font = font(current, weight);
  }
  if (ctx.measureText(text).width <= maxWidth) return text;
  let cut = [...text];
  while (cut.length > 1 && ctx.measureText(`${cut.join('')}…`).width > maxWidth) cut = cut.slice(0, -1);
  return `${cut.join('')}…`;
}

function drawFit(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, maxWidth: number, size: number, weight = 900) {
  ctx.fillText(fitText(ctx, text, maxWidth, size, weight), x, y);
}

/** 按词换行（泰文、中日文没有空格，用 Intl.Segmenter 断词），最多 maxLines 行 */
function wrapLines(ctx: CanvasRenderingContext2D, text: string, maxWidth: number, maxLines: number, locale: string) {
  const words = typeof Intl.Segmenter === 'function'
    ? [...new Intl.Segmenter(locale, { granularity: 'word' }).segment(text)].map((s) => s.segment)
    : text.split(/(?<=\s)/);
  const lines: string[] = [];
  let line = '';
  for (const word of words) {
    const next = line + word;
    if (line && ctx.measureText(next.trimEnd()).width > maxWidth) {
      lines.push(line.trimEnd());
      line = word.trimStart();
    } else line = next;
  }
  if (line.trim()) lines.push(line.trimEnd());
  if (lines.length <= maxLines) return lines;
  const kept = lines.slice(0, maxLines);
  kept[maxLines - 1] = fitEllipsis(ctx, lines.slice(maxLines - 1).join(' '), maxWidth);
  return kept;
}

function fitEllipsis(ctx: CanvasRenderingContext2D, text: string, maxWidth: number) {
  if (ctx.measureText(text).width <= maxWidth) return text;
  let cut = [...text];
  while (cut.length > 1 && ctx.measureText(`${cut.join('')}…`).width > maxWidth) cut = cut.slice(0, -1);
  return `${cut.join('').trimEnd()}…`;
}

/** 窄一点的大数字（照设计稿的 condensed） */
function condensed(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number) {
  ctx.save();
  ctx.font = font(size);
  ctx.translate(x, y);
  ctx.scale(0.78, 1);
  ctx.fillText(text, 0, 0);
  ctx.restore();
}

function spaced(ctx: CanvasRenderingContext2D, spacing: number) {
  // 旧版 Safari 没有 letterSpacing，不设也能看
  if ('letterSpacing' in ctx) (ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = `${spacing}px`;
}

/** 在 (cx, cy) 转 angle 度，再以 w×h 的左上角为原点画 */
function rotated(ctx: CanvasRenderingContext2D, cx: number, cy: number, w: number, h: number, angle: number, draw: () => void) {
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate((angle * Math.PI) / 180);
  ctx.translate(-w / 2, -h / 2);
  draw();
  ctx.restore();
}

// 小图标：40×40 的路径，和设计稿一样
type IconName = 'hex' | 'racket' | 'next' | 'pair' | Axis;
const icons: Record<IconName, { d: string; stroke?: number }> = {
  hex: { d: 'M20 2 L38 12 L38 28 L20 38 L2 28 L2 12 Z' },
  racket: { d: 'M38 12 A10 8 0 1 1 18 12 A10 8 0 1 1 38 12 M4 36 L22 18', stroke: 3.5 },
  next: { d: 'M6 34 L34 6 M24 6 L34 6 L34 16', stroke: 4 },
  pair: { d: 'M21 14 A7 7 0 1 1 7 14 A7 7 0 1 1 21 14 M35 18 A7 7 0 1 1 21 18 A7 7 0 1 1 35 18' },
  attack: { d: 'M4 30 L36 6 L30 20 L38 22 L8 38 Z' },
  net: { d: 'M2 18 H38 V21 H2 Z M20 4 L26 14 L14 14 Z' },
  defense: { d: 'M20 3 L36 9 L34 26 Q28 35 20 38 Q12 35 6 26 L4 9 Z' },
  speed: { d: 'M4 8 L16 20 L4 32 M18 8 L30 20 L18 32', stroke: 4 },
  footwork: { d: 'M18 26 A6 9 0 1 1 6 26 A6 9 0 1 1 18 26 M34 14 A6 9 0 1 1 22 14 A6 9 0 1 1 34 14' },
  tactics: { d: 'M36 20 A16 16 0 1 1 4 20 A16 16 0 1 1 36 20 M28 20 A8 8 0 1 1 12 20 A8 8 0 1 1 28 20 M23 20 A3 3 0 1 1 17 20 A3 3 0 1 1 23 20', stroke: 3 },
};

function icon(ctx: CanvasRenderingContext2D, name: IconName, x: number, y: number, size: number, color: string) {
  const { d, stroke } = icons[name];
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(size / 40, size / 40);
  const path = new Path2D(d);
  if (stroke) {
    ctx.strokeStyle = color;
    ctx.lineWidth = stroke;
    ctx.lineCap = 'round';
    ctx.stroke(path);
  } else {
    ctx.fillStyle = color;
    ctx.fill(path);
  }
  ctx.restore();
}

/** 得分最高的几项（同分按六项的顺序） */
const topAxes = (scores: Record<Axis, number>) => [...axes].sort((a, b) => scores[b] - scores[a]);

// MARK: 帖子 1080×1350

export function drawPost(ctx: CanvasRenderingContext2D, card: CardInput) {
  const [W, H] = cardSizes.post;
  const color = palette(card.archetype);
  ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = color.background;
  ctx.fillRect(0, 0, W, H);

  // 上下两条带缺口的黑边
  ctx.fillStyle = color.band;
  polygon(ctx, [[0, 0], [W, 0], [W, 124], [842, 124], [778, 74], [302, 74], [238, 124], [0, 124]]);
  ctx.fill();
  polygon(ctx, [[0, H - 124], [238, H - 124], [302, H - 74], [778, H - 74], [842, H - 124], [W, H - 124], [W, H], [0, H]]);
  ctx.fill();

  // 电路线
  ctx.fillStyle = color.circuit;
  for (const [x, top, length] of [[88, true, 240], [W - 94, true, 300], [120, false, 220], [W - 126, false, 260]] as [number, boolean, number][]) {
    const y = top ? 0 : H - length;
    ctx.fillRect(x, y, 6, length);
    ctx.beginPath();
    ctx.arc(x + 3, top ? length : H - length, 9, 0, Math.PI * 2);
    ctx.fill();
  }

  // 背景里的大字
  ctx.fillStyle = rgba(color.onBackground, 0.07);
  ctx.font = font(300);
  ctx.textAlign = 'left';
  ctx.fillText('BAD', 320, 600);
  ctx.fillText('IE', 320, 855);

  // 顶部：测测你几级 · 2 分钟 / 网址
  ctx.textAlign = 'center';
  ctx.fillStyle = color.onBackground;
  spaced(ctx, 3);
  drawFit(ctx, card.text.quiz, W / 2, 182, 860, 24);
  spaced(ctx, 1);
  drawFit(ctx, card.text.footer, W / 2, 240, 900, 52);
  spaced(ctx, 0);

  drawBack(ctx, card, color);
  drawFront(ctx, card, color);

  // 话题
  ctx.textAlign = 'center';
  ctx.fillStyle = color.onBackground;
  drawFit(ctx, card.text.hashtag, W / 2, H - 162, 900, 34);
}

function cardBase(ctx: CanvasRenderingContext2D, w: number, h: number) {
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.35)';
  ctx.shadowBlur = 60;
  ctx.shadowOffsetY = 28;
  ctx.fillStyle = ink;
  ctx.beginPath();
  ctx.roundRect(0, 0, w, h, 16);
  ctx.fill();
  ctx.restore();
  ctx.beginPath();
  ctx.roundRect(0, 0, w, h, 16);
  ctx.clip();
}

/** 正面：美术区（鬼影字、人物、等级徽章、单双打图标），下面是名字、打法和最强一拍 */
function drawFront(ctx: CanvasRenderingContext2D, card: CardInput, color: ReturnType<typeof palette>) {
  const [w, h] = [472, 700];
  rotated(ctx, 296, 650, w, h, -4, () => {
    cardBase(ctx, w, h);
    ctx.fillStyle = cream;
    ctx.fillRect(0, 0, w, 416);
    ctx.fillStyle = 'rgba(23,20,15,0.09)';
    ctx.font = font(116);
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    for (let i = 0; i < 4; i++) ctx.fillText(ghostWord[card.archetype], -12, -12 + i * 100);
    ctx.textBaseline = 'alphabetic';
    ctx.drawImage(card.art, 60, 12, 360, 420);

    // 等级徽章
    ctx.fillStyle = ink;
    hexagon(ctx, 20, 20, 68, 76);
    ctx.fill();
    ctx.fillStyle = color.accent;
    ctx.textAlign = 'center';
    drawFit(ctx, card.label, 54, 68, 56, 28);

    // 单打、双打：偏好的那个填满
    ([['singles', 40], ['doubles', 92]] as const).forEach(([mode, cy]) => {
      const on = card.mode === mode;
      ctx.beginPath();
      ctx.arc(w - 40, cy, 20, 0, Math.PI * 2);
      ctx.fillStyle = on ? ink : cream;
      ctx.fill();
      ctx.lineWidth = 4;
      ctx.strokeStyle = ink;
      ctx.stroke();
      ctx.fillStyle = on ? cream : ink;
      for (const dx of mode === 'singles' ? [0] : [-6, 6]) {
        ctx.beginPath();
        ctx.arc(w - 40 + dx, cy, 5, 0, Math.PI * 2);
        ctx.fill();
      }
    });

    // 红色的 HUD 线
    ctx.fillStyle = red;
    ctx.fillRect(20, 300, 68, 4);
    ctx.fillRect(w - 68, 240, 48, 4);

    // 下半部分
    ctx.fillStyle = ink;
    ctx.fillRect(0, 416, w, h - 416);
    polygon(ctx, [[176, 400], [296, 400], [306, 428], [166, 428]]);
    ctx.fill();
    ctx.fillStyle = color.brand;
    ctx.font = font(20);
    spaced(ctx, 4);
    ctx.fillText('BADIE', w / 2 + 2, 421);
    spaced(ctx, 0);

    const title = card.name ?? `${card.label} ${card.levelName}`;
    const sub = [card.region?.toUpperCase(), card.name ? `${card.label} ${card.levelName}` : undefined, card.status].filter(Boolean).join(' · ');
    ctx.fillStyle = '#ffffff';
    drawFit(ctx, title, w / 2, 488, w - 48, 38);
    ctx.fillStyle = gray;
    spaced(ctx, 1);
    drawFit(ctx, sub, w / 2, 522, w - 48, 17, 800);
    spaced(ctx, 0);

    // 左下：打法
    ctx.textAlign = 'left';
    ctx.font = font(15, 700);
    const lines = wrapLines(ctx, card.line, 236, 2, card.locale);
    ctx.fillStyle = '#d6d1c8';
    lines.forEach((line, i) => ctx.fillText(line, 24, h - 24 - (lines.length - 1 - i) * 20));
    const nameY = h - 24 - lines.length * 20 - 6;
    ctx.fillStyle = '#ffffff';
    drawFit(ctx, card.styleName, 24, nameY, 236, 46);
    ctx.fillStyle = gray;
    drawFit(ctx, card.text.playStyle, 24, nameY - 50, 236, 16);

    // 右下：最强一拍
    ctx.textAlign = 'right';
    icon(ctx, 'racket', w - 24 - 64, h - 24 - 60, 64, '#ffffff');
    ctx.fillStyle = '#ffffff';
    drawFit(ctx, card.bestShot, w - 24, h - 96, 170, 28);
    ctx.fillStyle = gray;
    drawFit(ctx, card.text.bestShot, w - 24, h - 134, 170, 16);
  });
}

/** 背面：名字、浅色的 HUD 面板（只放知道的几行）、竖排 BADIE、底部六项能力 */
function drawBack(ctx: CanvasRenderingContext2D, card: CardInput, color: ReturnType<typeof palette>) {
  const [w, h] = [472, 680];
  rotated(ctx, 800, 792, w, h, 3, () => {
    cardBase(ctx, w, h);

    ctx.fillStyle = '#2a2620';
    ctx.beginPath();
    ctx.roundRect(24, 24, 68, 68, 14);
    ctx.fill();
    ctx.fillStyle = color.accent;
    hexagon(ctx, 36, 32, 44, 52);
    ctx.fill();
    ctx.fillStyle = card.archetype === 'net' || card.archetype === 'wall' || card.archetype === 'captain' ? '#ffffff' : ink;
    ctx.textAlign = 'center';
    drawFit(ctx, card.label, 58, 66, 38, 18);

    ctx.textAlign = 'left';
    ctx.fillStyle = '#ffffff';
    drawFit(ctx, card.name ?? card.styleName, 108, 58, w - 132, 28);
    let x = 108;
    if (card.region) {
      ctx.fillStyle = gray;
      spaced(ctx, 1);
      const region = fitText(ctx, card.region.toUpperCase(), 220, 16, 800);
      ctx.fillText(region, x, 86);
      x += ctx.measureText(region).width + 10;
      spaced(ctx, 0);
    }
    ctx.font = font(15);
    const chip = `LV.${card.label}`;
    const chipWidth = ctx.measureText(chip).width + 12;
    ctx.fillStyle = '#6b4cff';
    ctx.fillRect(x, 70, chipWidth, 22);
    ctx.fillStyle = '#ffffff';
    ctx.fillText(chip, x + 6, 87);

    // 浅色面板：行少时矮一点，上下居中
    const rows = card.rows.slice(0, 4);
    const ph = Math.max(240, rows.length * 86 + 130);
    const top = 132 + (396 - ph) / 2;
    ctx.fillStyle = cream;
    polygon(ctx, ([[0, 0.08], [0.14, 0.08], [0.18, 0], [0.82, 0], [0.86, 0.08], [1, 0.08], [1, 0.92], [0.86, 0.92], [0.82, 1], [0.18, 1], [0.14, 0.92], [0, 0.92]] as [number, number][])
      .map(([px, py]) => [px * w, top + py * ph]));
    ctx.fill();

    // 竖排 BADIE
    ctx.save();
    ctx.translate(30, top + ph / 2 - 50);
    ctx.rotate(Math.PI / 2);
    ctx.fillStyle = card.archetype === 'cannon' || card.archetype === 'rookie' ? ink : color.accent;
    ctx.font = font(20);
    spaced(ctx, 6);
    ctx.textAlign = 'left';
    ctx.fillText('BADIE', 0, 0);
    spaced(ctx, 0);
    ctx.restore();

    const rowHeight = 76;
    const gap = 10;
    let y = top + ph / 2 - (rows.length * rowHeight + (rows.length - 1) * gap) / 2;
    ctx.textAlign = 'center';
    for (const row of rows) {
      ctx.fillStyle = '#e2ddd2';
      ctx.fillRect(60, y, w - 120, rowHeight);
      ctx.fillStyle = red;
      spaced(ctx, 2);
      drawFit(ctx, row.label, w / 2, y + 27, w - 150, 15);
      spaced(ctx, 0);
      ctx.fillStyle = ink;
      drawFit(ctx, row.value, w / 2, y + 60, w - 150, 22);
      y += rowHeight + gap;
    }

    // 六项能力
    const col = (w - 48) / axes.length;
    axes.forEach((axis, i) => {
      const cx = 24 + col * i + col / 2;
      ctx.fillStyle = gray;
      ctx.textAlign = 'center';
      drawFit(ctx, card.axisNames[axis], cx, 580, col - 6, 15);
      ctx.fillStyle = '#ffffff';
      const value = String(axisLevel(card.scores[axis]));
      ctx.font = font(54);
      condensed(ctx, value, cx - (ctx.measureText(value).width * 0.78) / 2, 648, 54);
    });
  });
}

// MARK: 限时动态 1080×1920

export function drawStory(ctx: CanvasRenderingContext2D, card: CardInput) {
  const [W, H] = cardSizes.story;
  const color = palette(card.archetype);
  const base = card.archetype === 'allround' ? '#120f0a' : '#0b0d24';
  const soft = mix(color.glow, '#ffffff', 0.7);
  ctx.textBaseline = 'alphabetic';

  const background = ctx.createRadialGradient(W / 2, 576, 0, W / 2, 576, 1400);
  background.addColorStop(0, mix(color.glow, base, 0.72));
  background.addColorStop(0.55, mix(color.glow, base, 0.94));
  background.addColorStop(1, '#05060f');
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, W, H);

  // 斜线
  ctx.save();
  ctx.translate(W / 2, H / 2);
  ctx.rotate((30 * Math.PI) / 180);
  ctx.fillStyle = rgba(color.glow, 0.09);
  for (let x = -1600; x < 1600; x += 160) ctx.fillRect(x, -1600, 5, 3200);
  ctx.restore();

  // Logo
  ctx.textAlign = 'center';
  ctx.fillStyle = color.brand;
  ctx.font = font(64);
  ctx.fillText('badie', W / 2, 112);

  // 角色窗
  const [ax, ay, aw, ah] = [192, 165, 696, 800];
  const outline: [number, number][] = [[42, 0], [334, 0], [362, 24], [aw, 24], [aw, ah], [0, ah], [0, 40]];
  ctx.save();
  ctx.translate(ax, ay);
  ctx.save();
  ctx.shadowColor = rgba(color.glow, 0.6);
  ctx.shadowBlur = 110;
  const frame = ctx.createLinearGradient(0, 0, aw * 0.4, ah);
  frame.addColorStop(0, mix(color.glow, '#ffffff', 0.1));
  frame.addColorStop(1, mix(color.glow, base, 0.62));
  ctx.fillStyle = frame;
  polygon(ctx, outline);
  ctx.fill();
  ctx.restore();

  const [wx, wy, ww, wh] = [43, 53, aw - 86, ah - 96];
  const pane = ctx.createLinearGradient(0, wy, 0, wy + wh);
  pane.addColorStop(0, mix(color.glow, '#ffffff', 0.45));
  pane.addColorStop(1, mix(color.glow, base, 0.35));
  ctx.save();
  ctx.beginPath();
  ctx.rect(wx, wy, ww, wh);
  ctx.clip();
  ctx.fillStyle = pane;
  ctx.fillRect(wx, wy, ww, wh);
  ctx.drawImage(card.art, wx + 40, wy + 27, 533, 622);
  // 拟声字
  ctx.save();
  ctx.translate(wx + ww - 24, wy + 110);
  ctx.rotate((-10 * Math.PI) / 180);
  ctx.textAlign = 'right';
  ctx.font = font(84);
  ctx.lineJoin = 'round';
  ctx.lineWidth = 8;
  ctx.strokeStyle = base;
  ctx.strokeText(archetypeInfo[card.archetype].sound, 0, 0);
  ctx.fillStyle = card.archetype === 'cannon' ? '#ffffff' : card.archetype === 'allround' ? gold : lime;
  ctx.fillText(archetypeInfo[card.archetype].sound, 0, 0);
  ctx.restore();
  ctx.restore();

  // 竖排 BADIE · 年份
  ctx.save();
  ctx.translate(14, 160);
  ctx.rotate(Math.PI / 2);
  ctx.textAlign = 'left';
  ctx.fillStyle = soft;
  ctx.font = font(21);
  spaced(ctx, 5);
  ctx.fillText(`BADIE · ${new Date().getFullYear()}`, 0, 0);
  spaced(ctx, 0);
  ctx.restore();
  ctx.restore();

  // 打法面板
  const [tx, ty, tw, th] = [160, 896, 760, 256];
  const panel = ctx.createLinearGradient(0, ty, 0, ty + th);
  panel.addColorStop(0, rgba(mix(color.glow, base, 0.45), 0.94));
  panel.addColorStop(1, rgba(mix(color.glow, base, 0.75), 0.96));
  ctx.fillStyle = panel;
  polygon(ctx, [[tx, ty], [tx + tw * 0.58, ty], [tx + tw * 0.62, ty - 4], [tx + tw, ty], [tx + tw, ty + th * 0.82], [tx + tw * 0.94, ty + th], [tx, ty + th]]);
  ctx.fill();
  ctx.textAlign = 'center';
  ctx.fillStyle = '#ffffff';
  drawFit(ctx, card.styleName, W / 2, ty + 108, tw - 60, 80);
  ctx.font = font(28, 700);
  ctx.fillStyle = mix(color.glow, '#ffffff', 0.8);
  wrapLines(ctx, card.line, tw - 80, 2, card.locale).forEach((line, i) => ctx.fillText(line, W / 2, ty + 158 + i * 38));

  // 六格数据
  const [top, second, third] = topAxes(card.scores);
  const tiles: { label: string; value: string; small?: string; icon: IconName }[] = [
    { label: card.text.levelStatus, value: card.label, small: card.levelName, icon: 'hex' },
    { label: card.text.bestShot, value: card.bestShot, icon: 'racket' },
    { label: card.axisNames[top], value: String(axisLevel(card.scores[top])), icon: top },
    { label: card.axisNames[second], value: String(axisLevel(card.scores[second])), icon: second },
    card.next
      ? { label: card.next.title, value: card.next.skill, icon: 'next' }
      : { label: card.axisNames[third], value: String(axisLevel(card.scores[third])), icon: third },
    { label: card.text.bestPartner, value: card.partner, icon: 'pair' },
  ];
  const [gx, gy, tileW, tileH, gap] = [117, 1179, 412, 144, 21];
  tiles.forEach((tile, i) => {
    const x = gx + (i % 2) * (tileW + gap);
    const y = gy + Math.floor(i / 2) * (tileH + gap);
    ctx.save();
    ctx.translate(x, y);
    polygon(ctx, [[16, 0], [tileW - 16, 0], [tileW, 17], [tileW, tileH - 17], [tileW - 16, tileH], [16, tileH], [0, tileH - 17], [0, 17]]);
    const fill = ctx.createLinearGradient(0, 0, tileW, tileH);
    fill.addColorStop(0, 'rgba(255,255,255,0.10)');
    fill.addColorStop(1, 'rgba(255,255,255,0.03)');
    ctx.fillStyle = fill;
    ctx.fill();
    ctx.strokeStyle = rgba(soft, 0.35);
    ctx.lineWidth = 3;
    ctx.stroke();
    ctx.clip();
    ctx.globalAlpha = 0.22;
    icon(ctx, tile.icon, tileW - 150, tileH - 128, 140, '#ffffff');
    ctx.globalAlpha = 1;
    ctx.textAlign = 'left';
    ctx.fillStyle = soft;
    spaced(ctx, 2);
    drawFit(ctx, tile.label, 27, 44, tileW - 54, 21);
    spaced(ctx, 0);
    ctx.fillStyle = '#ffffff';
    const value = fitText(ctx, tile.value, tile.small ? 140 : tileW - 70, 56);
    ctx.fillText(value, 27, 112);
    if (tile.small) {
      const after = 27 + ctx.measureText(value).width + 12;
      drawFit(ctx, tile.small, after, 110, tileW - after - 30, 32, 800);
    }
    ctx.restore();
  });

  // 话题和落款
  ctx.textAlign = 'center';
  ctx.fillStyle = '#ffffff';
  drawFit(ctx, card.text.hashtag, W / 2, 1770, 900, 36);
  ctx.fillStyle = soft;
  drawFit(ctx, card.text.noSignup, W / 2, 1822, 900, 32);
  ctx.fillStyle = '#ffffff';
  drawFit(ctx, card.text.footer, W / 2, 1868, 900, 38);
}

/** 等 Nunito 加载好再画（没加载好 canvas 会用系统字体） */
export async function fontsReady() {
  try {
    await Promise.all([document.fonts.load(font(40)), document.fonts.load(font(40, 700))]);
    await document.fonts.ready;
  } catch {
    // 字体加载失败就用系统字体
  }
}

export function loadArt(archetype: Archetype) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = `/cards/${archetype}.svg`;
  });
}

/** 画成 PNG */
export async function renderCard(size: CardSize, card: CardInput) {
  const [width, height] = cardSizes[size];
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d')!;
  (size === 'post' ? drawPost : drawStory)(ctx, card);
  return new Promise<Blob>((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('toBlob'))), 'image/png'));
}
