import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import { currentLocale, languages, setLocale, startLocale, t, useLocale, type Locale } from './i18n';
import { Icon, type IconName } from './icons';
import { Avatar, CountBadge, IconTile, Wordmark, type Tint } from './kit';
import { Link, navigate } from './router';
import { supabase, type InboxCounts, type Profile } from './supabase';
import { Toasts } from './ui';

/** 顶层的几个 tab：每个都是真正的页面。球馆只在桌面顶栏里，手机上和 iOS 一样从首页进 */
const tabs: { to: string; label: string; icon: IconName; active: IconName; match: RegExp; desktopOnly?: boolean }[] = [
  { to: '/', label: 'Home', icon: 'homeOutline', active: 'home', match: /^\/(play\/|notifications\/)?$/ },
  { to: '/games/', label: 'Games', icon: 'ticketOutline', active: 'games', match: /^\/(games|rooms|groups|join|challenges|rankings)\// },
  { to: '/courts/', label: 'Courts', icon: 'pin', active: 'pin', match: /^\/courts\//, desktopOnly: true },
  { to: '/messages/', label: 'Messages', icon: 'chatsOutline', active: 'chats', match: /^\/messages\// },
  { to: '/me/', label: 'Me', icon: 'meOutline', active: 'me', match: /^\/(me|settings|verification|levels|level-quiz|admin)\// },
];

/** 没登录时点了要账号的东西：先登录，登录完回到这里 */
export const signInFirst = (next: string) => `/signin/?next=${encodeURIComponent(next)}`;

export function Shell({ path, me, guest, counts, children }: { path: string; me: Profile | null; guest: boolean; counts?: InboxCounts; children: ReactNode }) {
  const menu = useRef<HTMLDialogElement>(null);
  const current = tabs.find((tab) => tab.match.test(path));
  const messages = counts ? counts.messages + counts.requests : 0;
  const badge = (tab: (typeof tabs)[number]) => (tab.to === '/messages/' ? messages : 0);
  const name = (tab: (typeof tabs)[number]) => (badge(tab) ? t('{label}, {n} unread', { label: t(tab.label), n: badge(tab) }) : t(tab.label));
  const openMenu = () => menu.current?.showModal();
  // 聊天页和 iOS 一样不显示底部标签栏，输入框贴着屏幕底边
  const chatting = /^\/messages\/(game|group|dm)\//.test(path);

  return (
    <div className={`min-h-dvh bg-canvas ${chatting ? 'max-lg:[--tabbar:0px]' : ''}`}>
      <a href="#main" className="button sr-only z-50 focus:not-sr-only focus:fixed focus:top-3 focus:left-3">{t('Skip to content')}</a>

      <header className="sticky top-0 z-30 bg-bar text-on-bar">
        <div className="page flex h-16 items-center gap-2 lg:gap-6">
          <Link to="/" aria-label={t('Badie home')} className="press -ml-1 rounded-lg px-1">
            <Wordmark inverse className="text-[1.6rem]" />
          </Link>
          <nav aria-label={t('Main')} className="hidden lg:block">
            <ul className="flex gap-1">
              {tabs.map((tab) => (
                <li key={tab.to}>
                  <Link
                    to={tab.to}
                    aria-current={current === tab ? 'page' : undefined}
                    aria-label={name(tab)}
                    className="relative flex h-10 items-center gap-2 rounded-full px-4 text-subhead font-bold text-on-bar/80 transition-colors duration-[var(--dur-1)] hover:bg-on-bar/10 hover:text-on-bar aria-[current=page]:bg-lime aria-[current=page]:text-on-accent"
                  >
                    <Icon name={current === tab ? tab.active : tab.icon} className="size-5" />
                    {t(tab.label)}
                    <CountBadge count={badge(tab)} className="border-bar!" />
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
          <div className="ml-auto flex items-center gap-2">
            <LanguageSwitch />
            {me ? (
              <>
                <Link
                  to="/notifications/"
                  aria-label={counts?.updates ? t('Notifications, {n} unread', { n: counts.updates }) : t('Notifications')}
                  className="press relative grid size-10 place-items-center rounded-full text-on-bar hover:bg-on-bar/10"
                >
                  <Icon name="bell" className="size-5" />
                  <CountBadge count={counts?.updates ?? 0} className="absolute -top-0.5 -right-0.5 border-bar!" />
                </Link>
                <Link to="/me/" aria-label={t('My profile')} className="press hidden rounded-full lg:block">
                  <Avatar id={me.id} name={me.nickname} photo={me.avatar_path} size={38} className="border-on-bar!" />
                </Link>
              </>
            ) : guest && !path.startsWith('/signin/') && (
              <Link to={signInFirst(path)} className="flex h-10 items-center rounded-full px-3 text-subhead font-bold text-on-bar hover:bg-on-bar/10">
                {t('Sign in')}
              </Link>
            )}
            <button type="button" onClick={openMenu} className="button button-sm hidden border-lime! shadow-none! lg:inline-flex">
              <Icon name="plus" className="size-4" />
              {t('Set up a game')}
            </button>
          </div>
        </div>
      </header>

      {/* key 让每次换 tab 都重新播放进场动画 */}
      <main id="main" key={current?.to ?? path} className="page animate-enter pt-5 pb-[calc(var(--tabbar)+1.5rem)] lg:pt-8 lg:pb-16">
        {children}
      </main>
      <Footer />

      {!chatting && <TabBar current={current?.to} badge={badge} name={name} onCreate={openMenu} />}
      <CreateMenu dialog={menu} signedIn={Boolean(me)} />
      <Toasts />
    </div>
  );
}

/** 静态页面（球馆目录）用的同一套外壳：自己查登录状态，链接是普通的整页跳转 */
export function SiteShell({ path, children }: { path: string; children?: ReactNode }) {
  const [me, setMe] = useState<Profile | null>();
  const locale = useLocale();
  // 静态页面的文字也跟着界面语言变（页面是英文生成的，搜索引擎看英文）
  useEffect(translateStatic, [locale]);
  useEffect(() => {
    startLocale();
    supabase?.auth.getSession().then(async ({ data }) => {
      if (!data.session) return setMe(null);
      const { data: profile } = await supabase!.from('profiles').select().eq('id', data.session.user.id).maybeSingle();
      setMe((profile as Profile | null) ?? null);
    });
  }, []);
  return <Shell path={path} me={me ?? null} guest={me === null}>{children}</Shell>;
}

/**
 * 静态页面里要翻译的文字：<span data-t="{n} courts" data-n="12">12 courts</span>；
 * data-t-placeholder / data-t-label 翻译输入框提示和读屏名字。数字按界面语言加千位分隔。
 * data-region="us" 的国家名用浏览器自带的译名（英文保持原样）
 */
function translateStatic() {
  for (const element of document.querySelectorAll<HTMLElement>('[data-t]')) {
    const { t: key, ...rest } = element.dataset;
    const params = Object.fromEntries(
      Object.entries(rest).filter(([name]) => !name.startsWith('t')).map(([name, value = '']) => [name, /^\d+$/.test(value) ? Number(value).toLocaleString(currentLocale()) : value]),
    );
    element.textContent = t(key!, params);
  }
  for (const element of document.querySelectorAll<HTMLElement>('[data-t-placeholder]')) element.setAttribute('placeholder', t(element.dataset.tPlaceholder!));
  for (const element of document.querySelectorAll<HTMLElement>('[data-t-label]')) element.setAttribute('aria-label', t(element.dataset.tLabel!));
  const short = new Intl.DisplayNames([currentLocale()], { type: 'region', style: 'short' });
  const full = new Intl.DisplayNames([currentLocale()], { type: 'region' });
  for (const element of document.querySelectorAll<HTMLElement>('[data-region]')) {
    element.dataset.english ??= element.textContent ?? '';
    const code = element.dataset.region!.toUpperCase();
    // 短名最自然（香港、美国），但有的语言短名是缩写（AS、UK），那就用全名
    const name = short.of(code) ?? '';
    element.textContent = currentLocale() === 'en' ? element.dataset.english : /[.॰]|^[A-Z]+$/.test(name) ? (full.of(code) ?? name) : name;
  }
}

/** 页脚：真正的页面链接（不是本页的锚点） */
function Footer() {
  const columns: [string, [string, string][]][] = [
    ['Play', [['Home', '/'], ['Quick Match', '/play/'], ['Nearby games', '/rooms/'], ['Regular games', '/groups/']]],
    ['Courts', [['Nearby venues', '/courts/'], ['Level Chart', '/levels/'], ['Leaderboard', '/rankings/']]],
    ['Badie', [['About Badie', '/about/'], ['Me', '/me/'], ['Privacy Policy', '/privacy/'], ['Terms of Service', '/terms/']]],
  ];
  return (
    <footer className="hidden border-t-2 border-stroke/10 lg:block">
      <div className="page grid grid-cols-[2fr_1fr_1fr_1fr] gap-8 py-10 text-footnote">
        <div className="grid content-start gap-2">
          <Wordmark className="text-[1.5rem]" />
          <p className="max-w-xs text-ink-secondary">{t('A free app for finding badminton partners at your level and courts near you.')}</p>
        </div>
        {columns.map(([title, links]) => (
          <nav key={title} aria-label={t(title)} className="grid content-start gap-1.5">
            <p className="font-bold">{t(title)}</p>
            {links.map(([label, to]) => <Link key={to} to={to} className="text-ink-secondary hover:text-ink hover:underline">{t(label)}</Link>)}
          </nav>
        ))}
      </div>
    </footer>
  );
}

/** 手机底部的悬浮标签栏（iOS 的 FloatingTabBar）：中间是柠檬绿的“约球”按钮 */
function TabBar({ current, badge, name, onCreate }: {
  current?: string;
  badge: (tab: (typeof tabs)[number]) => number;
  name: (tab: (typeof tabs)[number]) => string;
  onCreate: () => void;
}) {
  const mobile = tabs.filter((tab) => !tab.desktopOnly);
  const item = (tab: (typeof tabs)[number]) => (
    <li key={tab.to} className="flex-1">
      <Link
        to={tab.to}
        aria-current={current === tab.to ? 'page' : undefined}
        aria-label={name(tab)}
        className="press group flex min-h-14 flex-col items-center justify-center gap-0.5 text-[11px] font-bold text-ink-tertiary aria-[current=page]:text-ink"
      >
        <span className="relative">
          <Icon name={current === tab.to ? tab.active : tab.icon} className="size-6" />
          <CountBadge count={badge(tab)} className="absolute -top-2 -right-3" />
        </span>
        {t(tab.label)}
        <span aria-hidden="true" className="size-[5px] rounded-full group-aria-[current=page]:bg-ink" />
      </Link>
    </li>
  );
  return (
    <nav aria-label={t('Main')} className="fixed inset-x-0 bottom-0 z-30 px-4 pb-[calc(0.5rem+env(safe-area-inset-bottom))] lg:hidden">
      {/* 标签栏后面用画布色铺满、上沿渐隐，滚动的内容不会从四周露出来 */}
      <div aria-hidden="true" className="absolute inset-x-0 -top-9 bottom-0 bg-linear-to-b from-canvas/0 via-canvas to-canvas" />
      <ul className="sticker relative flex h-[68px] items-center rounded-dock! px-2 shadow-dock!">
        {item(mobile[0])}
        {item(mobile[1])}
        <li className="flex flex-1 justify-center">
          <button
            type="button"
            onClick={onCreate}
            aria-label={t('Set up a game')}
            className="-mt-9 grid size-[62px] place-items-center rounded-full border-2 border-stroke bg-lime text-on-accent shadow-dock transition-transform duration-[var(--dur-1)] active:scale-92"
          >
            <Icon name="plus" className="size-7" />
          </button>
        </li>
        {item(mobile[2])}
        {item(mobile[3])}
      </ul>
    </nav>
  );
}

const createOptions: { to: string; icon: IconName; tint: Tint; title: string; subtitle: string }[] = [
  { to: '/play/', icon: 'bolt', tint: 'lime', title: 'Quick Match', subtitle: 'Auto-find buddies by level, time and distance' },
  { to: '/rooms/new/', icon: 'court', tint: 'peach', title: 'Start a game', subtitle: 'Have a court and need players, or playing with friends? Open it to others' },
  { to: '/groups/', icon: 'group', tint: 'sky', title: 'Regular games · Groups', subtitle: 'Same time and venue weekly. One-tap sign-up, auto-waitlist' },
  { to: '/join/', icon: 'hash', tint: 'lavender', title: 'Enter room code / group ID', subtitle: '6-digit room code or group code from a friend' },
];

/** “约一场”菜单：手机上是底部弹出的面板，桌面上是居中的对话框 */
function CreateMenu({ dialog, signedIn }: { dialog: React.RefObject<HTMLDialogElement | null>; signedIn: boolean }) {
  const go = (to: string) => {
    dialog.current?.close();
    navigate(signedIn ? to : signInFirst(to));
  };
  return (
    <dialog
      ref={dialog}
      aria-labelledby="create-title"
      // 点到面板外面（遮罩）就关掉
      onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
      className="m-0 mt-auto w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet lg:m-auto lg:max-w-lg lg:open:animate-pop"
    >
      <div className="rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas px-5 pt-3 pb-[calc(1.5rem+env(safe-area-inset-bottom))] lg:rounded-[28px] lg:border-b-2 lg:p-6 lg:shadow-card">
        <div aria-hidden="true" className="mx-auto mb-3 h-1.5 w-10 rounded-full bg-ink/20 lg:hidden" />
        <div className="mb-4 flex items-center justify-between">
          <h2 id="create-title" className="text-title">{t('Set up a game')}</h2>
          <form method="dialog">
            <button className="press grid size-10 place-items-center rounded-full hover:bg-surface-muted" aria-label={t('Close')}>
              <Icon name="x" className="size-5" />
            </button>
          </form>
        </div>
        <ul className="grid gap-3">
          {createOptions.map((o) => (
            <li key={o.to}>
              <button type="button" onClick={() => go(o.to)} className="sticker lift flex w-full items-center gap-4 p-4 text-left">
                <IconTile icon={o.icon} tint={o.tint} size="lg" />
                <span className="min-w-0 flex-1">
                  <span className="block text-headline">{t(o.title)}</span>
                  <span className="block text-footnote text-ink-secondary">{t(o.subtitle)}</span>
                </span>
                <Icon name="chevronRight" className="size-4 text-ink-tertiary" />
              </button>
            </li>
          ))}
        </ul>
      </div>
    </dialog>
  );
}

/** 语言切换：在最外层的顶栏里。第一次打开按浏览器语言，选过就记住 */
export function LanguageSwitch() {
  const locale = useLocale();
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const name = languages.find(([code]) => code === locale)?.[1];

  // 打开时焦点落在当前语言上；点菜单外面就关
  useEffect(() => {
    if (!open) return;
    box.current?.querySelector<HTMLElement>('[aria-selected="true"]')?.focus();
    const close = (event: PointerEvent) => box.current?.contains(event.target as Node) || setOpen(false);
    document.addEventListener('pointerdown', close);
    return () => document.removeEventListener('pointerdown', close);
  }, [open]);

  function pick(code: Locale) {
    setLocale(code, true);
    setOpen(false);
    button.current?.focus();
  }

  // 上下键、Home / End 移动，Esc 关掉回到按钮
  function onKeyDown(event: KeyboardEvent<HTMLUListElement>) {
    const options = [...event.currentTarget.querySelectorAll<HTMLElement>('[role="option"]')];
    const index = options.indexOf(document.activeElement as HTMLElement);
    const next = ({ ArrowDown: index + 1, ArrowUp: index - 1, Home: 0, End: options.length - 1 } as Record<string, number>)[event.key];
    if (next !== undefined) {
      event.preventDefault();
      options[(next + options.length) % options.length].focus();
    } else if (event.key === 'Escape') {
      setOpen(false);
      button.current?.focus();
    } else if (event.key === 'Tab') {
      setOpen(false);
    }
  }

  return (
    <div ref={box} className="relative">
      <button
        ref={button}
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={`${t('Language')}: ${name}`}
        onClick={() => setOpen(!open)}
        onKeyDown={(event) => ['ArrowDown', 'ArrowUp'].includes(event.key) && (event.preventDefault(), setOpen(true))}
        className="flex h-10 items-center gap-1.5 rounded-full px-2.5 text-footnote font-bold text-on-bar transition-colors hover:bg-on-bar/10 aria-expanded:bg-on-bar/15 sm:px-3"
      >
        <Icon name="globe" className="size-5" />
        <span className="hidden sm:inline">{name}</span>
        <Icon name="chevronDown" className={`hidden size-3 transition-transform sm:block ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && (
        <ul role="listbox" aria-label={t('Language')} onKeyDown={onKeyDown} className="sticker absolute top-full right-0 z-50 mt-2 grid w-56 origin-top-right animate-pop gap-0.5 p-1.5 text-ink">
          {languages.map(([code, label]) => (
            <li
              key={code}
              role="option"
              aria-selected={code === locale}
              tabIndex={-1}
              lang={code}
              onClick={() => pick(code)}
              onKeyDown={(event) => ['Enter', ' '].includes(event.key) && (event.preventDefault(), pick(code))}
              className="flex min-h-11 cursor-pointer items-center justify-between gap-3 rounded-[12px] px-3 font-bold outline-none hover:bg-surface-muted focus-visible:bg-surface-muted focus-visible:ring-3 focus-visible:ring-focus aria-selected:bg-lime aria-selected:text-on-accent"
            >
              {label}
              {code === locale && <Icon name="check" className="size-4" />}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** 页面加载数据前的整页转圈 */
export function Loading({ text }: { text?: string }) {
  return (
    <p role="status" className="grid min-h-[50dvh] place-items-center font-bold text-ink-secondary">
      <span className="flex items-center gap-3">
        <span aria-hidden="true" className="size-5 animate-spin rounded-full border-[3px] border-current border-t-transparent" />
        {text ?? <span className="sr-only">{t('Loading…')}</span>}
      </span>
    </p>
  );
}
