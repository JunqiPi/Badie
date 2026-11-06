import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import { t } from './i18n';
import { Button } from './ui';

const MAX_ZOOM = 4;

/** 选完照片：拖动、缩放（双指、滚轮或滑块）（iOS 的 AvatarCropSheet）。
 *  头像是圆框，裁成 320×320；卡片背景是 3:4 的竖框，裁成 600×800。确定后把 JPEG 交给 onDone */
export function AvatarCrop({ image, card = false, onDone, onCancel }: {
  image: ImageBitmap;
  card?: boolean;
  onDone: (jpeg: Blob) => void;
  onCancel: () => void;
}) {
  const [width, height] = card ? [600, 800] : [320, 320];
  // 偏移、尺寸都以框的宽度为 1；框高 = 1 / aspect
  const aspect = width / height;
  const dialog = useRef<HTMLDialogElement>(null);
  const frame = useRef<HTMLDivElement>(null);
  const preview = useRef<HTMLCanvasElement>(null);
  const [side, setSide] = useState(0);
  const [zoom, setZoom] = useState(1);
  // 偏移按方框边长的比例存：窗口变大变小时位置不变
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const pinch = useRef<{ distance: number; zoom: number }>(null);

  useEffect(() => {
    dialog.current?.showModal();
    const box = frame.current!;
    const observer = new ResizeObserver(() => setSide(box.clientWidth));
    observer.observe(box);
    return () => observer.disconnect();
  }, []);

  /** 照片正好盖满整个框时的倍数 */
  const base = () => Math.max(1 / image.width, 1 / aspect / image.height);

  /** 照片始终盖住整个框，拖不出空白 */
  function clamp(next: { x: number; y: number }, z = zoom) {
    const scale = base() * z;
    const maxX = Math.max(0, (image.width * scale - 1) / 2);
    const maxY = Math.max(0, (image.height * scale - 1 / aspect) / 2);
    return { x: Math.min(maxX, Math.max(-maxX, next.x)), y: Math.min(maxY, Math.max(-maxY, next.y)) };
  }

  const setZoomClamped = (z: number) => {
    const next = Math.min(MAX_ZOOM, Math.max(1, z));
    setZoom(next);
    setOffset((o) => clamp(o, next));
  };

  /** 框里要用的那一块（照片的像素坐标） */
  function cropRect() {
    const scale = base() * zoom;
    const w = 1 / scale;
    const h = 1 / aspect / scale;
    const cx = image.width / 2 - offset.x / scale;
    const cy = image.height / 2 - offset.y / scale;
    return { x: cx - w / 2, y: cy - h / 2, w, h };
  }

  // 预览：直接画到方框里的画布上
  useEffect(() => {
    const canvas = preview.current;
    if (!canvas || !side) return;
    const ratio = devicePixelRatio || 1;
    canvas.width = Math.round(side * ratio);
    canvas.height = Math.round((side / aspect) * ratio);
    const context = canvas.getContext('2d')!;
    const r = cropRect();
    context.drawImage(image, r.x, r.y, r.w, r.h, 0, 0, canvas.width, canvas.height);
  }, [side, zoom, offset, image]);

  function down(event: ReactPointerEvent<HTMLDivElement>) {
    event.currentTarget.setPointerCapture(event.pointerId);
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.current.size === 2) {
      const [a, b] = [...pointers.current.values()];
      pinch.current = { distance: Math.hypot(a.x - b.x, a.y - b.y), zoom };
    }
  }
  function move(event: ReactPointerEvent<HTMLDivElement>) {
    const last = pointers.current.get(event.pointerId);
    if (!last || !side) return;
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.current.size === 2 && pinch.current) {
      const [a, b] = [...pointers.current.values()];
      setZoomClamped(pinch.current.zoom * (Math.hypot(a.x - b.x, a.y - b.y) / pinch.current.distance));
    } else if (pointers.current.size === 1) {
      setOffset((o) => clamp({ x: o.x + (event.clientX - last.x) / side, y: o.y + (event.clientY - last.y) / side }));
    }
  }
  function up(event: ReactPointerEvent<HTMLDivElement>) {
    pointers.current.delete(event.pointerId);
    if (pointers.current.size < 2) pinch.current = null;
  }

  async function finish() {
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d')!;
    // JPEG 没有透明：透明的 PNG 先铺白底，不然是黑的
    context.fillStyle = '#fff';
    context.fillRect(0, 0, width, height);
    const r = cropRect();
    context.drawImage(image, r.x, r.y, r.w, r.h, 0, 0, width, height);
    // 服务器每张最多 256 KB：太大就再压一压
    for (const quality of [0.85, 0.7, 0.55, 0.4]) {
      const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
      if (blob && blob.size <= 250_000) return onDone(blob);
    }
    onCancel();
  }

  return (
    <dialog
      ref={dialog}
      aria-labelledby="crop-title"
      onCancel={(event) => {
        event.preventDefault();
        onCancel();
      }}
      className="m-0 mt-auto w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet sm:m-auto sm:max-w-md sm:open:animate-pop"
    >
      <div className="grid gap-4 rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas px-5 pt-5 pb-[calc(1.5rem+env(safe-area-inset-bottom))] sm:rounded-[28px] sm:border-b-2 sm:p-6 sm:shadow-card">
        <h2 id="crop-title" className="text-title3">{card ? t('Adjust card background') : t('Adjust photo')}</h2>
        <div
          ref={frame}
          onPointerDown={down}
          onPointerMove={move}
          onPointerUp={up}
          onPointerCancel={up}
          onWheel={(event) => setZoomClamped(zoom * (event.deltaY < 0 ? 1.08 : 1 / 1.08))}
          style={{ aspectRatio: `${width} / ${height}`, maxWidth: `min(20rem, ${50 * aspect}dvh)` }}
          className="relative mx-auto w-full cursor-grab touch-none overflow-hidden rounded-[16px] border-2 border-stroke bg-surface-muted select-none active:cursor-grabbing"
        >
          <canvas ref={preview} aria-hidden="true" className="absolute inset-0 size-full" />
          {/* 头像：圆圈外面压暗 */}
          {!card && <span aria-hidden="true" className="pointer-events-none absolute inset-0 rounded-full border-2 border-white shadow-[0_0_0_100vmax_rgb(0_0_0/0.45)]" />}
        </div>
        <label className="grid gap-1.5">
          <span className="text-footnote font-bold text-ink-secondary">{t('Zoom')}</span>
          <input type="range" min={1} max={MAX_ZOOM} step={0.01} value={zoom} onChange={(e) => setZoomClamped(Number(e.target.value))}
                 className="w-full accent-[var(--color-lime)]" />
        </label>
        <p className="text-footnote text-ink-secondary">{t('Pinch to zoom, drag to move')}</p>
        <div className="grid grid-cols-2 gap-3">
          <Button type="button" variant="quiet" onClick={onCancel}>{t('Cancel')}</Button>
          <Button type="button" onClick={() => void finish()}>{t('Use')}</Button>
        </div>
      </div>
    </dialog>
  );
}

/** 解码选的照片（按拍摄方向转正）；太大的先缩到长边 1600 像素，裁剪时不卡 */
export async function decode(file: File): Promise<ImageBitmap> {
  const bitmap = await createImageBitmap(file);
  const longest = Math.max(bitmap.width, bitmap.height);
  if (longest <= 1600) return bitmap;
  const ratio = 1600 / longest;
  const smaller = await createImageBitmap(bitmap, { resizeWidth: Math.round(bitmap.width * ratio), resizeHeight: Math.round(bitmap.height * ratio), resizeQuality: 'high' });
  bitmap.close();
  return smaller;
}
