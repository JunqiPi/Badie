// 装到手机上：iPhone 去 App Store；安卓把网站添加到主屏幕（网站本身就能装：manifest.webmanifest + sw.js + 网页推送）。
// Chrome 给了安装提示（beforeinstallprompt）就直接弹系统的安装框，没给就打开一个说明怎么加的面板
import { useEffect, useRef, useState, useSyncExternalStore, type RefObject } from 'react';
import { APP_STORE_URL } from './Contact';
import { t } from './i18n';
import { Icon } from './icons';
import { IconTile } from './kit';

type InstallPrompt = Event & { prompt: () => Promise<void>; userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }> };

// 安装提示可能在 React 挂上之前就来了：模块一加载就开始听
let deferred: InstallPrompt | null = null;
let installed = false;
const listeners = new Set<() => void>();
const notify = () => listeners.forEach((listener) => listener());
if (typeof window !== 'undefined') {
  window.addEventListener('beforeinstallprompt', (event) => {
    // 不要 Chrome 自己的小横幅，用页面上的按钮
    event.preventDefault();
    deferred = event as InstallPrompt;
    notify();
  });
  window.addEventListener('appinstalled', () => {
    deferred = null;
    installed = true;
    notify();
  });
}
const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => void listeners.delete(listener);
};

export type Device = 'ios' | 'android' | 'desktop';

/** iPad 的 Safari 默认报自己是 Mac，靠触屏认出来 */
export function device(): Device {
  if (typeof navigator === 'undefined') return 'desktop';
  const ua = navigator.userAgent;
  if (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'ios';
  return /Android/.test(ua) ? 'android' : 'desktop';
}

/** 已经是从主屏幕打开的（像 App 一样，没有地址栏） */
export const standalone = () =>
  matchMedia('(display-mode: standalone)').matches || (navigator as Navigator & { standalone?: boolean }).standalone === true;

/** 安卓上还没装：要不要给“添加到主屏幕” */
function useAndroidInstallable() {
  const done = useSyncExternalStore(subscribe, () => installed);
  return device() === 'android' && !standalone() && !done;
}

/** “添加到主屏幕”按钮：有安装提示就弹系统的安装框，没有就打开说明面板。onDone：装了、拒了或者关了面板 */
export function AddToHomeButton({ className = 'button', onDone }: { className?: string; onDone?: () => void }) {
  const sheet = useRef<HTMLDialogElement>(null);
  async function add() {
    const prompt = deferred;
    if (!prompt) return sheet.current?.showModal();
    // 一个安装提示只能用一次
    deferred = null;
    await prompt.prompt();
    await prompt.userChoice.catch(() => undefined);
    onDone?.();
  }
  return (
    <>
      <button type="button" onClick={add} className={className}>{t('Add to home screen')}</button>
      <InstallSheet dialog={sheet} onClose={onDone} />
    </>
  );
}

/** 首页、关于页的“装到手机上”：iPhone 给 App Store，安卓给添加到主屏幕，电脑上两个都说。放在一排按钮（flex-wrap）里 */
export function GetTheApp({ className = 'button button-quiet', noteClassName = 'text-footnote text-ink-secondary' }: { className?: string; noteClassName?: string }) {
  const android = useAndroidInstallable();
  const kind = device();
  if (kind === 'android') return android ? <AddToHomeButton className={className} /> : null;
  return (
    <>
      <a href={APP_STORE_URL} className={className}>{t('Get the iPhone app')}</a>
      {kind === 'desktop' && <p className={`basis-full ${noteClassName}`}>{t('On Android, open badie.rsvp in Chrome and add it to your home screen.')}</p>}
    </>
  );
}

/** 怎么添加到主屏幕：Chrome 和三星浏览器各一句，用三星浏览器的排在前面 */
function InstallSheet({ dialog, onClose }: { dialog: RefObject<HTMLDialogElement | null>; onClose?: () => void }) {
  const browsers = [
    { name: 'Chrome', text: t('Tap ⋮ at the top right, then Add to home screen (or Install app).') },
    { name: 'Samsung Internet', text: t('Tap ≡ at the bottom, then Add page to → Home screen.') },
  ];
  if (typeof navigator !== 'undefined' && /SamsungBrowser/.test(navigator.userAgent)) browsers.reverse();
  return (
    <dialog
      ref={dialog}
      aria-labelledby="install-title"
      onClose={onClose}
      onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
      className="m-0 mt-auto w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet lg:m-auto lg:max-w-lg lg:open:animate-pop"
    >
      <div className="grid gap-4 rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas px-5 pt-3 pb-[calc(1.5rem+env(safe-area-inset-bottom))] lg:rounded-[28px] lg:border-b-2 lg:p-6 lg:shadow-card">
        <div aria-hidden="true" className="mx-auto h-1.5 w-10 rounded-full bg-ink/20 lg:hidden" />
        <div className="flex items-start justify-between gap-3">
          <div className="grid gap-1">
            <h2 id="install-title" className="text-title2">{t('Add Badie to your home screen')}</h2>
            <p className="text-subhead text-ink-secondary">{t('It opens like an app and can send you notifications.')}</p>
          </div>
          <form method="dialog">
            <button className="press grid size-10 place-items-center rounded-full hover:bg-surface-muted" aria-label={t('Close')}>
              <Icon name="x" className="size-5" />
            </button>
          </form>
        </div>
        <ul className="grid gap-3">
          {browsers.map((b) => (
            <li key={b.name} className="sticker grid gap-1 p-4">
              <p className="text-headline">{b.name}</p>
              <p className="text-subhead">{b.text}</p>
            </li>
          ))}
        </ul>
      </div>
    </dialog>
  );
}

const ASKED = 'badie.installAsked';
const VISITS = 'badie.visits';

/** 这台设备上第几次打开（同一个标签页里换页不算） */
function countVisit() {
  try {
    if (!sessionStorage.getItem(VISITS)) {
      sessionStorage.setItem(VISITS, '1');
      localStorage.setItem(VISITS, String(Number(localStorage.getItem(VISITS) ?? 0) + 1));
    }
    return Number(localStorage.getItem(VISITS));
  } catch {
    return 0;
  }
}
function asked() {
  try {
    return localStorage.getItem(ASKED) === '1';
  } catch {
    return true;
  }
}
function rememberAsked() {
  try {
    localStorage.setItem(ASKED, '1');
  } catch {}
}

/** 登录后的安卓浏览器（不是从主屏幕打开的）：第二次打开时在标签栏上面提一次，点过“以后再说”或者加过就不再出现 */
export function InstallNudge() {
  const android = useAndroidInstallable();
  const [shown, setShown] = useState(false);
  useEffect(() => {
    if (android && countVisit() >= 2 && !asked()) setShown(true);
  }, [android]);
  if (!android || !shown) return null;
  const close = () => {
    rememberAsked();
    setShown(false);
  };
  return (
    <aside
      aria-labelledby="install-nudge"
      className="sticker fixed inset-x-4 bottom-[calc(var(--tabbar)+0.75rem)] z-40 mx-auto grid max-w-md animate-pop gap-3 p-4 lg:hidden"
    >
      <div className="flex items-center gap-3">
        <IconTile icon="home" tint="lime" />
        <div className="min-w-0">
          <p id="install-nudge" className="text-headline">{t('Add Badie to your home screen')}</p>
          <p className="text-footnote text-ink-secondary">{t('It opens like an app and can send you notifications.')}</p>
        </div>
      </div>
      <div className="flex flex-wrap gap-2">
        <AddToHomeButton className="button button-sm" onDone={close} />
        <button type="button" onClick={close} className="button button-sm button-quiet">{t('Not now')}</button>
      </div>
    </aside>
  );
}
