import { useEffect, type ReactNode } from 'react';
import { Icon } from './icons';
import { Link } from './router';
import { useLive, type InboxCounts } from './supabase';
import { Toasts } from './ui';

export const sections = [
  { path: '/app/play/', label: 'Play', short: 'Play', icon: 'play' },
  { path: '/app/games/', label: 'My games', short: 'Games', icon: 'games' },
  { path: '/app/messages/', label: 'Messages', short: 'Messages', icon: 'chat' },
  { path: '/app/courts/', label: 'Courts', short: 'Courts', icon: 'courts' },
  { path: '/app/me/', label: 'Me', short: 'Me', icon: 'me' },
] as const;

function Logo({ small }: { small?: boolean }) {
  return (
    <a href="/" className={`flex items-center gap-2 font-black ${small ? 'text-xl' : 'text-2xl'}`}>
      <span className={`sticker grid place-items-center bg-lime text-on-accent ${small ? 'size-8 rounded-lg! text-sm' : 'size-9 rounded-xl!'}`}>B</span>
      Badie
    </a>
  );
}

/** 未读数只挂在“消息”上：聊天 + 通知 + 好友申请 */
function Badge({ count, small }: { count: number; small?: boolean }) {
  if (!count) return null;
  return (
    <span className={`grid place-items-center rounded-full border-2 border-stroke bg-pink font-black text-on-accent tabular-nums ${small ? 'absolute -top-1 -right-1 h-5 min-w-5 px-1 text-[0.65rem]' : 'ml-auto h-6 min-w-6 px-1.5 text-xs'}`}>
      {count > 99 ? '99+' : count}
    </span>
  );
}

export function Shell({ path, children }: { path: string; children: ReactNode }) {
  // 球群算在“约球”下面
  const current = sections.find((s) => path.startsWith(s.path) || (s.icon === 'play' && path.startsWith('/app/groups/')));
  const { data: counts, refresh } = useLive<InboxCounts>('inbox_counts');
  // 换页时（比如刚看完消息）马上更新未读数
  useEffect(() => void refresh(), [path, refresh]);
  const unread = counts ? counts.messages + counts.updates + counts.requests : 0;
  const label = (s: (typeof sections)[number], text: string) => (s.icon === 'chat' && unread ? `${text}, ${unread} unread` : text);
  return (
    <div className="min-h-dvh bg-canvas lg:grid lg:grid-cols-[15rem_1fr]">
      <a href="#main" className="button sr-only z-50 focus:not-sr-only focus:fixed focus:top-3 focus:left-3">Skip to content</a>

      <aside className="hidden border-r-2 border-stroke/15 lg:sticky lg:top-0 lg:flex lg:h-dvh lg:flex-col lg:gap-8 lg:px-4 lg:py-6">
        <div className="px-2"><Logo /></div>
        <nav aria-label="App">
          <ul className="grid gap-1">
            {sections.map((s) => (
              <li key={s.path}>
                <Link
                  to={s.path}
                  aria-current={current === s ? 'page' : undefined}
                  aria-label={label(s, s.label)}
                  className="flex min-h-11 items-center gap-3 rounded-[var(--r-control)] border-2 border-transparent px-3 font-extrabold text-ink-secondary transition-colors duration-[var(--dur-1)] hover:bg-surface hover:text-ink aria-[current=page]:border-stroke aria-[current=page]:bg-lime aria-[current=page]:text-on-accent"
                >
                  <Icon name={s.icon} />
                  {s.label}
                  {s.icon === 'chat' && <Badge count={unread} />}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </aside>

      <div className="min-w-0 pb-[calc(4.5rem+env(safe-area-inset-bottom))] lg:pb-0">
        <header className="flex items-center justify-between border-b-2 border-stroke/15 px-[var(--gutter)] py-3 lg:hidden">
          <Logo small />
          <span className="eyebrow">{current?.label}</span>
        </header>
        {/* key 让每次换页都重新播放进场动画 */}
        <main id="main" key={current?.path} className="page animate-enter py-6 lg:py-10">
          {children}
        </main>
      </div>

      <nav aria-label="App" className="fixed inset-x-0 bottom-0 z-20 border-t-2 border-stroke bg-surface pb-[env(safe-area-inset-bottom)] lg:hidden">
        <ul className="grid grid-cols-5">
          {sections.map((s) => (
            <li key={s.path}>
              <Link
                to={s.path}
                aria-current={current === s ? 'page' : undefined}
                aria-label={label(s, s.short)}
                className="group flex min-h-14 flex-col items-center justify-center gap-0.5 text-xs font-extrabold text-ink-tertiary transition-colors aria-[current=page]:text-ink"
              >
                <span className="relative grid h-7 w-12 place-items-center rounded-full transition-colors duration-[var(--dur-1)] group-aria-[current=page]:bg-lime group-aria-[current=page]:text-on-accent">
                  <Icon name={s.icon} className="size-5" />
                  {s.icon === 'chat' && <Badge count={unread} small />}
                </span>
                {s.short}
              </Link>
            </li>
          ))}
        </ul>
      </nav>

      <Toasts />
    </div>
  );
}
