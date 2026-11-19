// 比赛最终排名的分享图：和等级卡同一套样式（米白底、墨色字、柠檬绿），4:5（1080×1350），在浏览器里用 canvas 画
import { cardSize, fontsReady } from './levelCard';

const ink = '#17140f';
const cream = '#f2efe7';
const gray = '#7a746a';
const lime = '#d4f33f';
const stack = '"Nunito Variable", ui-rounded, system-ui, "PingFang SC", "Hiragino Sans", "Apple SD Gothic Neo", "Noto Sans CJK SC", sans-serif';
const font = (size: number, weight = 900) => `${weight} ${size}px ${stack}`;

/** 文字都由调用方翻译好再传进来 */
export type StandingsInput = {
  title: string;
  subtitle: string;
  championLabel: string;
  /** 第一行是冠军 */
  rows: { rank: string; name: string; record: string; diff: string }[];
  footer: string;
};

/** 放不下就截断加省略号 */
function fit(ctx: CanvasRenderingContext2D, text: string, maxWidth: number) {
  if (ctx.measureText(text).width <= maxWidth) return text;
  let cut = [...text];
  while (cut.length > 1 && ctx.measureText(`${cut.join('')}…`).width > maxWidth) cut = cut.slice(0, -1);
  return `${cut.join('')}…`;
}

function draw(ctx: CanvasRenderingContext2D, card: StandingsInput) {
  // 和等级卡一样按 540×675 的坐标画，导出时放大一倍
  const [w, h] = [cardSize[0] / 2, cardSize[1] / 2];
  ctx.scale(2, 2);
  ctx.fillStyle = cream;
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = ink;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.roundRect(12, 12, w - 24, h - 24, 18);
  ctx.stroke();

  ctx.fillStyle = ink;
  ctx.textAlign = 'left';
  ctx.font = font(30);
  ctx.fillText(fit(ctx, card.title, w - 80), 40, 70);
  ctx.fillStyle = gray;
  ctx.font = font(15, 800);
  ctx.fillText(fit(ctx, card.subtitle, w - 80), 40, 96);

  // 冠军：柠檬绿的块
  const [champion, ...rest] = card.rows;
  ctx.fillStyle = lime;
  ctx.beginPath();
  ctx.roundRect(36, 120, w - 72, 118, 16);
  ctx.fill();
  ctx.strokeStyle = ink;
  ctx.lineWidth = 2.5;
  ctx.stroke();
  ctx.fillStyle = ink;
  ctx.font = font(15, 800);
  ctx.fillText(card.championLabel, 58, 154);
  ctx.font = font(38);
  ctx.fillText(fit(ctx, champion?.name ?? '', w - 130), 58, 198);
  ctx.font = font(15, 800);
  ctx.fillText(champion ? `${champion.record} · ${champion.diff}` : '', 58, 224);

  // 其余名次：最多 11 行
  const shown = rest.slice(0, 11);
  const rowHeight = Math.min(34, 360 / Math.max(shown.length, 1));
  shown.forEach((row, i) => {
    const y = 270 + i * rowHeight + rowHeight * 0.7;
    if (i > 0) {
      ctx.fillStyle = 'rgba(23,20,15,0.12)';
      ctx.fillRect(40, y - rowHeight * 0.7, w - 80, 1.5);
    }
    ctx.fillStyle = ink;
    ctx.textAlign = 'left';
    ctx.font = font(18);
    ctx.fillText(row.rank, 44, y);
    ctx.font = font(18, 800);
    ctx.fillText(fit(ctx, row.name, w - 260), 92, y);
    ctx.textAlign = 'right';
    ctx.font = font(16, 800);
    ctx.fillText(row.record, w - 120, y);
    ctx.fillText(row.diff, w - 44, y);
  });

  ctx.textAlign = 'center';
  ctx.fillStyle = gray;
  ctx.font = font(13, 800);
  ctx.fillText(card.footer, w / 2, h - 34);
}

/** 画成 PNG */
export async function renderStandings(card: StandingsInput) {
  await fontsReady();
  const canvas = document.createElement('canvas');
  [canvas.width, canvas.height] = cardSize;
  draw(canvas.getContext('2d')!, card);
  return new Promise<Blob>((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('toBlob'))), 'image/png'));
}
