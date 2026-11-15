// 等级卡片：在浏览器里用 canvas 画，不经过服务器。
// 一张 4:5 的卡（1080×1350），有正面和背面：页面上只显示一张，点一下翻面，分享的是正在看的那一面。
// 所有打法用同一套颜色（黑、米白、柠檬绿），靠人物剪影和背后的英文大字区分。
// 剪影在 public/cards/<打法>.png（透明底、纯色、按人物裁好），换图直接换文件
import { axes, axisLevel, type Archetype, type Axis } from './assessment';

export type CardFace = 'front' | 'back';
export const cardSize: [number, number] = [1080, 1350];

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
  scores: Record<Axis, number>;
  axisNames: Record<Axis, string>;
  /** 离 5 级还差 → 反手后场 */
  next?: { title: string; skill: string };
  /** 背面的几行（偏好、空闲时间、最佳搭档），只放知道的 */
  rows: { label: string; value: string }[];
  text: { playStyle: string; bestShot: string; quiz: string; footer: string };
  art: HTMLImageElement;
  /** 头像；没有或不想印就不传 */
  avatar?: HTMLImageElement;
};

const ink = '#17140f';
const cream = '#f2efe7';
const gray = '#9a948a';
const lime = '#d4f33f';
const stack = '"Nunito Variable", ui-rounded, system-ui, "PingFang SC", "Hiragino Sans", "Apple SD Gothic Neo", "Noto Sans CJK SC", sans-serif';
const font = (size: number, weight = 900) => `${weight} ${size}px ${stack}`;

/** 人物区里重复的大字：装饰，用英文 */
export const ghostWord: Record<Archetype, string> = { cannon: 'SMASH', net: 'NET', wall: 'WALL', quick: 'SPRING', engine: 'MOTOR', captain: 'TACTICS', allround: 'ALL-ROUND', rookie: 'ROOKIE' };

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

/** 图片等比放进 w×h 的框里，水平居中、贴着底边 */
function contain(ctx: CanvasRenderingContext2D, image: HTMLImageElement, x: number, y: number, w: number, h: number) {
  const scale = Math.min(w / image.naturalWidth, h / image.naturalHeight);
  const [dw, dh] = [image.naturalWidth * scale, image.naturalHeight * scale];
  ctx.drawImage(image, x + (w - dw) / 2, y + h - dh, dw, dh);
}

/** 头像：圆形，外面一圈卡片底色和一圈柠檬绿 */
function drawAvatar(ctx: CanvasRenderingContext2D, image: HTMLImageElement | undefined, cx: number, cy: number, r: number) {
  if (!image) return;
  for (const [radius, color] of [[r + 7, ink], [r + 3, lime]] as const) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.save();
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.clip();
  const side = Math.min(image.naturalWidth, image.naturalHeight);
  ctx.drawImage(image, (image.naturalWidth - side) / 2, (image.naturalHeight - side) / 2, side, side, cx - r, cy - r, r * 2, r * 2);
  ctx.restore();
}

/** 地区 · 4+ 中级 · 自评（只放知道的） */
const subline = (card: CardInput, withLevel: boolean) =>
  [card.region?.toUpperCase(), withLevel ? `${card.label} ${card.levelName}` : undefined, card.status].filter(Boolean).join(' · ');

/** 卡片底和一圈细边；里面按 540×675 的坐标画（导出时放大一倍） */
function frame(ctx: CanvasRenderingContext2D, draw: (w: number, h: number) => void) {
  const [w, h] = [cardSize[0] / 2, cardSize[1] / 2];
  ctx.save();
  ctx.scale(2, 2);
  ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = ink;
  ctx.fillRect(0, 0, w, h);
  draw(w, h);
  ctx.strokeStyle = 'rgba(255,255,255,0.14)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.roundRect(5, 5, w - 10, h - 10, 18);
  ctx.stroke();
  ctx.restore();
}

// MARK: 正面：人物区（大字、剪影、等级徽章、单双打），下面是头像、名字、打法和最强一拍

export function drawFront(ctx: CanvasRenderingContext2D, card: CardInput) {
  frame(ctx, (w, h) => {
    const top = 392;
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(12, 12, w - 24, top - 12, [14, 14, 0, 0]);
    ctx.clip();
    ctx.fillStyle = cream;
    ctx.fillRect(0, 0, w, top);
    ctx.fillStyle = 'rgba(23,20,15,0.08)';
    ctx.font = font(128);
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    for (let i = 0; i < 4; i++) ctx.fillText(ghostWord[card.archetype], -6, -8 + i * 104);
    ctx.textBaseline = 'alphabetic';
    contain(ctx, card.art, 96, 30, w - 192, top - 46);
    ctx.restore();

    // 等级徽章
    ctx.fillStyle = ink;
    hexagon(ctx, 30, 30, 76, 86);
    ctx.fill();
    ctx.fillStyle = lime;
    ctx.textAlign = 'center';
    drawFit(ctx, card.label, 68, 84, 62, 32);

    // 单打、双打：偏好的那个填满
    ([['singles', 52], ['doubles', 108]] as const).forEach(([mode, cy]) => {
      const on = card.mode === mode;
      ctx.beginPath();
      ctx.arc(w - 52, cy, 21, 0, Math.PI * 2);
      ctx.fillStyle = on ? ink : cream;
      ctx.fill();
      ctx.lineWidth = 4;
      ctx.strokeStyle = ink;
      ctx.stroke();
      ctx.fillStyle = on ? cream : ink;
      for (const dx of mode === 'singles' ? [0] : [-6, 6]) {
        ctx.beginPath();
        ctx.arc(w - 52 + dx, cy, 5, 0, Math.PI * 2);
        ctx.fill();
      }
    });

    // BADIE 标
    ctx.fillStyle = ink;
    polygon(ctx, [[w / 2 - 66, top - 18], [w / 2 + 66, top - 18], [w / 2 + 78, top + 12], [w / 2 - 78, top + 12]]);
    ctx.fill();
    ctx.fillStyle = lime;
    ctx.font = font(20);
    ctx.textAlign = 'center';
    spaced(ctx, 5);
    ctx.fillText('BADIE', w / 2 + 2, top + 5);
    spaced(ctx, 0);

    // 头像压在人物区和信息区的交界上
    drawAvatar(ctx, card.avatar, 76, top + 2, 44);

    ctx.fillStyle = '#ffffff';
    drawFit(ctx, card.name ?? `${card.label} ${card.levelName}`, w / 2, top + 66, w - (card.avatar ? 250 : 60), 40);
    ctx.fillStyle = gray;
    spaced(ctx, 1);
    drawFit(ctx, subline(card, Boolean(card.name)), w / 2, top + 98, w - 60, 17, 800);
    spaced(ctx, 0);
    ctx.fillStyle = 'rgba(255,255,255,0.12)';
    ctx.fillRect(30, top + 122, w - 60, 1.5);

    // 左下：打法。说明最多两行，第二行的基线（top + 236）要离底边落款（h - 20）够远，不能叠在一起
    ctx.textAlign = 'left';
    ctx.fillStyle = gray;
    drawFit(ctx, card.text.playStyle, 30, top + 148, 270, 15, 800);
    ctx.fillStyle = '#ffffff';
    drawFit(ctx, card.styleName, 30, top + 194, 290, 44);
    ctx.font = font(15, 700);
    ctx.fillStyle = '#d6d1c8';
    wrapLines(ctx, card.line, 290, 2, card.locale).forEach((line, i) => ctx.fillText(line, 30, top + 218 + i * 18));

    // 右下：最强一拍
    ctx.textAlign = 'right';
    ctx.fillStyle = gray;
    drawFit(ctx, card.text.bestShot, w - 30, top + 148, 180, 15, 800);
    ctx.fillStyle = lime;
    drawFit(ctx, card.bestShot, w - 30, top + 190, 180, 28);

    footer(ctx, card.text.footer, w, h);
  });
}

// MARK: 背面：名字、知道的几行、离下一级还差什么、六项能力

export function drawBack(ctx: CanvasRenderingContext2D, card: CardInput) {
  frame(ctx, (w, h) => {
    ctx.fillStyle = lime;
    hexagon(ctx, 30, 30, 60, 68);
    ctx.fill();
    ctx.fillStyle = ink;
    ctx.textAlign = 'center';
    drawFit(ctx, card.label, 60, 73, 50, 24);
    ctx.textAlign = 'left';
    ctx.fillStyle = '#ffffff';
    drawFit(ctx, card.name ?? card.styleName, 106, 62, w - (card.avatar ? 220 : 140), 30);
    ctx.fillStyle = gray;
    spaced(ctx, 1);
    drawFit(ctx, subline(card, true), 106, 90, w - (card.avatar ? 220 : 140), 15, 800);
    spaced(ctx, 0);
    drawAvatar(ctx, card.avatar, w - 62, 64, 30);

    // 浅色面板：行少时每行高一点
    const rows = card.rows.slice(0, 4);
    const rowHeight = rows.length > 3 ? 60 : 74;
    const gap = rows.length > 3 ? 8 : 10;
    const top = 128;
    const panel = rows.length * rowHeight + (rows.length - 1) * gap + 44;
    ctx.fillStyle = cream;
    ctx.beginPath();
    ctx.roundRect(24, top, w - 48, panel, 14);
    ctx.fill();
    rows.forEach((row, i) => {
      const y = top + 22 + i * (rowHeight + gap);
      ctx.fillStyle = '#e2ddd2';
      ctx.beginPath();
      ctx.roundRect(44, y, w - 88, rowHeight, 8);
      ctx.fill();
      ctx.textAlign = 'left';
      ctx.fillStyle = '#6f695e';
      drawFit(ctx, row.label, 62, y + rowHeight / 2 + 6, 130, 15, 800);
      ctx.textAlign = 'right';
      ctx.fillStyle = ink;
      drawFit(ctx, row.value, w - 62, y + rowHeight / 2 + 8, w - 250, 21);
    });

    let y = top + panel + 42;
    if (card.next) {
      ctx.textAlign = 'left';
      ctx.fillStyle = gray;
      drawFit(ctx, card.next.title, 30, y, 200, 15, 800);
      ctx.textAlign = 'right';
      ctx.fillStyle = lime;
      drawFit(ctx, card.next.skill, w - 30, y + 2, w - 250, 22);
      y += 26;
    }
    ctx.fillStyle = 'rgba(255,255,255,0.12)';
    ctx.fillRect(30, y, w - 60, 1.5);

    // 六项能力
    const col = (w - 60) / axes.length;
    axes.forEach((axis, i) => {
      const cx = 30 + col * i + col / 2;
      ctx.textAlign = 'center';
      ctx.fillStyle = gray;
      drawFit(ctx, card.axisNames[axis], cx, y + 46, col - 6, 14, 800);
      ctx.fillStyle = '#ffffff';
      const value = String(axisLevel(card.scores[axis]));
      ctx.font = font(56);
      condensed(ctx, value, cx - (ctx.measureText(value).width * 0.78) / 2, y + 118, 56);
    });

    footer(ctx, `${card.text.quiz} · ${card.text.footer}`, w, h);
  });
}

/** 底边的一行小字：网址（或“在 App Store 搜 Badie”） */
function footer(ctx: CanvasRenderingContext2D, text: string, w: number, h: number) {
  ctx.textAlign = 'center';
  ctx.fillStyle = gray;
  spaced(ctx, 3);
  drawFit(ctx, text, w / 2, h - 20, w - 80, 13, 800);
  spaced(ctx, 0);
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

/** 加载要画进卡片的图片（剪影、头像）。头像在别的域名上，要按跨域方式取，不然画完导不出图 */
export function loadImage(src: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.crossOrigin = 'anonymous';
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = src;
  });
}

export const loadArt = (archetype: Archetype) => loadImage(`/cards/${archetype}.png`);

/** 画成 PNG */
export async function renderCard(face: CardFace, card: CardInput) {
  const canvas = document.createElement('canvas');
  [canvas.width, canvas.height] = cardSize;
  const ctx = canvas.getContext('2d')!;
  (face === 'front' ? drawFront : drawBack)(ctx, card);
  return new Promise<Blob>((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('toBlob'))), 'image/png'));
}
