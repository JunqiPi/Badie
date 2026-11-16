// 装到手机上：iPhone 去 App Store；安卓有安装包时下载安装包（从网站直接下载，见 androidApp.ts），
// 没有时把网站添加到主屏幕（网站本身就能装：manifest.webmanifest + sw.js + 网页推送）。
// Chrome 给了安装提示（beforeinstallprompt）就直接弹系统的安装框，没给就打开一个说明怎么加的面板
import { Children, useEffect, useId, useRef, useState, useSyncExternalStore, type ReactNode, type RefObject } from 'react';
import { ANDROID_APK, androidApp, androidPage, androidSteps, megabytes } from './androidApp';
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
export function AddToHomeButton({ className = 'button', label = t('Add to home screen'), onDone }: { className?: string; label?: string; onDone?: () => void }) {
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
      <button type="button" onClick={add} className={className}>{label}</button>
      <InstallSheet dialog={sheet} onClose={onDone} />
    </>
  );
}

/**
 * 首页、关于页的“装到手机上”，放在一排按钮（flex-wrap）里：iPhone 给 App Store；
 * 安卓有安装包就下载安装包（“添加到主屏幕”退成下面一行小字），没有就添加到主屏幕；电脑上两个都给
 */
export function GetTheApp({ className = 'button button-quiet', noteClassName = 'text-footnote text-ink-secondary' }: { className?: string; noteClassName?: string }) {
  const android = useAndroidInstallable();
  const kind = device();
  if (kind === 'android') {
    if (androidApp) {
      return (
        <>
          <AndroidDownload className={className} />
          {android && (
            <div className={`basis-full ${noteClassName}`}>
              <AddToHomeButton className="link font-bold" label={t('Or add the website to your home screen')} />
            </div>
          )}
        </>
      );
    }
    return android ? <AddToHomeButton className={className} /> : null;
  }
  return (
    <>
      <a href={APP_STORE_URL} className={className}>{t('Get the iPhone app')}</a>
      {kind === 'desktop' &&
        (androidApp ? (
          <a href={androidPage()} className={className}>{t('Get the Android app')}</a>
        ) : (
          <p className={`basis-full ${noteClassName}`}>{t('On Android, open badie.rsvp in Chrome and add it to your home screen.')}</p>
        ))}
    </>
  );
}

/** 下载安卓安装包：点了开始下载，同时打开“怎么装”的面板 */
export function AndroidDownload({ className = 'button', onDone }: { className?: string; onDone?: () => void }) {
  const sheet = useRef<HTMLDialogElement>(null);
  return (
    <>
      <a href={ANDROID_APK} download="badie.apk" onClick={() => sheet.current?.showModal()} className={className}>
        {t('Download the Android app')}
      </a>
      <AndroidInstallSheet dialog={sheet} onClose={onDone} />
    </>
  );
}

function AndroidInstallSheet({ dialog, onClose }: { dialog: RefObject<HTMLDialogElement | null>; onClose?: () => void }) {
  // 首页的按钮和登录后的提示可能同时在页面上：标题的 id 各用各的
  const title = useId();
  return (
    <BottomSheet dialog={dialog} onClose={onClose} labelledBy={title}>
      <div className="grid gap-1">
        <h2 id={title} className="text-title2">{t('Install the Android app')}</h2>
        {androidApp && (
          <p className="text-subhead text-ink-secondary">
            {t('Version {version} · {size} MB', { version: androidApp.versionName, size: megabytes(androidApp.size) })}
          </p>
        )}
      </div>
      <ol className="grid gap-3">
        {androidSteps(t).map((step, i) => (
          <li key={step} className="sticker flex items-start gap-3 p-4">
            <span className="grid size-7 shrink-0 place-items-center rounded-full bg-[#17140f] text-footnote font-black text-lime">{i + 1}</span>
            <p className="text-subhead">{step}</p>
          </li>
        ))}
      </ol>
      <p className="text-footnote text-ink-secondary">{t('Sign in with the same account you use on the website or iPhone.')}</p>
    </BottomSheet>
  );
}

/** 底部弹出的面板（电脑上在中间）：标题行右边有关闭按钮，标题由 children 的第一块给 */
function BottomSheet({ dialog, onClose, labelledBy, children }: { dialog: RefObject<HTMLDialogElement | null>; onClose?: () => void; labelledBy: string; children: ReactNode }) {
  const [head, ...rest] = Children.toArray(children);
  return (
    <dialog
      ref={dialog}
      aria-labelledby={labelledBy}
      onClose={onClose}
      onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
      className="m-0 mt-auto w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet lg:m-auto lg:max-w-lg lg:open:animate-pop"
    >
      <div className="grid gap-4 rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas px-5 pt-3 pb-[calc(1.5rem+env(safe-area-inset-bottom))] lg:rounded-[28px] lg:border-b-2 lg:p-6 lg:shadow-card">
        <div aria-hidden="true" className="mx-auto h-1.5 w-10 rounded-full bg-ink/20 lg:hidden" />
        <div className="flex items-start justify-between gap-3">
          {head}
          <form method="dialog">
            <button className="press grid size-10 place-items-center rounded-full hover:bg-surface-muted" aria-label={t('Close')}>
              <Icon name="x" className="size-5" />
            </button>
          </form>
        </div>
        {rest}
      </div>
    </dialog>
  );
}

/** 怎么添加到主屏幕：Chrome 和三星浏览器各一句，用三星浏览器的排在前面 */
function InstallSheet({ dialog, onClose }: { dialog: RefObject<HTMLDialogElement | null>; onClose?: () => void }) {
  const browsers = [
    { name: 'Chrome', text: t('Tap ⋮ at the top right, then Add to home screen (or Install app).') },
    { name: 'Samsung Internet', text: t('Tap ≡ at the bottom, then Add page to → Home screen.') },
  ];
  if (typeof navigator !== 'undefined' && /SamsungBrowser/.test(navigator.userAgent)) browsers.reverse();
  const title = useId();
  return (
    <BottomSheet dialog={dialog} onClose={onClose} labelledBy={title}>
      <div className="grid gap-1">
        <h2 id={title} className="text-title2">{t('Add Badie to your home screen')}</h2>
        <p className="text-subhead text-ink-secondary">{t('It opens like an app and can send you notifications.')}</p>
      </div>
      <ul className="grid gap-3">
        {browsers.map((b) => (
          <li key={b.name} className="sticker grid gap-1 p-4">
            <p className="text-headline">{b.name}</p>
            <p className="text-subhead">{b.text}</p>
          </li>
        ))}
      </ul>
    </BottomSheet>
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

/**
 * 登录后的安卓浏览器：第二次打开时在标签栏上面提一次，点过“以后再说”、加过或者下载过就不再出现。
 * 有安装包时请他装 App（从主屏幕打开的网站也提），没有时请他把网站加到主屏幕
 */
export function InstallNudge() {
  const installable = useAndroidInstallable();
  const app = device() === 'android' && androidApp ? androidApp : null;
  const android = Boolean(app) || installable;
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
        <IconTile icon={app ? 'phone' : 'home'} tint="lime" />
        <div className="min-w-0">
          <p id="install-nudge" className="text-headline">{app ? t('Get the Android app') : t('Add Badie to your home screen')}</p>
          <p className="text-footnote text-ink-secondary">
            {app ? t('Same account as the website. {size} MB.', { size: megabytes(app.size) }) : t('It opens like an app and can send you notifications.')}
          </p>
        </div>
      </div>
      <div className="flex flex-wrap gap-2">
        {app ? <AndroidDownload className="button button-sm" onDone={close} /> : <AddToHomeButton className="button button-sm" onDone={close} />}
        <button type="button" onClick={close} className="button button-sm button-quiet">{t('Not now')}</button>
      </div>
    </aside>
  );
}
