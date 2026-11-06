import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import { t } from './i18n';
import { Button } from './ui';

const MAX_ZOOM = 4;

/** 选完照片：拖动、缩放（双指、滚轮或滑块），圆圈里的部分就是头像（iOS 的 AvatarCropSheet）。
 *  确定后裁成 size×size 的 JPEG 交给 onDone */
export function AvatarCrop({ image, size = 320, onDone, onCancel }: {
  image: ImageBitmap;
  size?: number;
  onDone: (jpeg: Blob) => void;
  onCancel: () => void;
}) {
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

  /** 短边正好铺满方框时的倍数 */
  const base = (length: number) => length / Math.min(image.width, image.height);

  /** 照片始终盖住整个方框，拖不出空白 */
  function clamp(next: { x: number; y: number }, z = zoom) {
    const scale = base(1) * z;
    const maxX = Math.max(0, (image.width * scale - 1) / 2);
    const maxY = Math.max(0, (image.height * scale - 1) / 2);
    return { x: Math.min(maxX, Math.max(-maxX, next.x)), y: Math.min(maxY, Math.max(-maxY, next.y)) };
  }

  const setZoomClamped = (z: number) => {
    const next = Math.min(MAX_ZOOM, Math.max(1, z));
    setZoom(next);
    setOffset((o) => clamp(o, next));
  };

  /** 方框里要用的那一块（照片的像素坐标） */
  function cropRect() {
    const scale = base(1) * zoom;
    const length = 1 / scale;
    const cx = image.width / 2 - offset.x / scale;
    const cy = image.height / 2 - offset.y / scale;
    return { x: cx - length / 2, y: cy - length / 2, length };
  }

  // 预览：直接画到方框里的画布上
  useEffect(() => {
    const canvas = preview.current;
    if (!canvas || !side) return;
    const ratio = devicePixelRatio || 1;
    canvas.width = canvas.height = Math.round(side * ratio);
    const context = canvas.getContext('2d')!;
    const r = cropRect();
    context.drawImage(image, r.x, r.y, r.length, r.length, 0, 0, canvas.width, canvas.height);
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

  function finish() {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = size;
    const context = canvas.getContext('2d')!;
    // JPEG 没有透明：透明的 PNG 先铺白底，不然是黑的
    context.fillStyle = '#fff';
    context.fillRect(0, 0, size, size);
    const r = cropRect();
    context.drawImage(image, r.x, r.y, r.length, r.length, 0, 0, size, size);
    canvas.toBlob((blob) => (blob ? onDone(blob) : onCancel()), 'image/jpeg', 0.85);
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
        <h2 id="crop-title" className="text-title3">{t('Adjust photo')}</h2>
        <div
          ref={frame}
          onPointerDown={down}
          onPointerMove={move}
          onPointerUp={up}
          onPointerCancel={up}
          onWheel={(event) => setZoomClamped(zoom * (event.deltaY < 0 ? 1.08 : 1 / 1.08))}
          className="relative mx-auto aspect-square w-full max-w-[min(20rem,50dvh)] cursor-grab touch-none overflow-hidden rounded-[16px] border-2 border-stroke bg-surface-muted select-none active:cursor-grabbing"
        >
          <canvas ref={preview} aria-hidden="true" className="absolute inset-0 size-full" />
          {/* 圆圈外面压暗 */}
          <span aria-hidden="true" className="pointer-events-none absolute inset-0 rounded-full border-2 border-white shadow-[0_0_0_100vmax_rgb(0_0_0/0.45)]" />
        </div>
        <label className="grid gap-1.5">
          <span className="text-footnote font-bold text-ink-secondary">{t('Zoom')}</span>
          <input type="range" min={1} max={MAX_ZOOM} step={0.01} value={zoom} onChange={(e) => setZoomClamped(Number(e.target.value))}
                 className="w-full accent-[var(--color-lime)]" />
        </label>
        <p className="text-footnote text-ink-secondary">{t('Pinch to zoom, drag to move')}</p>
        <div className="grid grid-cols-2 gap-3">
          <Button type="button" variant="quiet" onClick={onCancel}>{t('Cancel')}</Button>
          <Button type="button" onClick={finish}>{t('Use')}</Button>
        </div>
      </div>
    </dialog>
  );
}
