import type { ReactNode } from 'react';
import { Icon } from './icons';
import { Link } from './router';

export const sections = [
  { path: '/app/courts/', label: 'Courts', icon: 'courts' },
  { path: '/app/play/', label: 'Find partners', icon: 'play' },
  { path: '/app/games/', label: 'My games', icon: 'games' },
  { path: '/app/messages/', label: 'Messages', icon: 'chat' },
  { path: '/app/me/', label: 'Me', icon: 'me' },
] as const;

export function Shell({ path, children }: { path: string; children: ReactNode }) {
  const current = sections.find((s) => path.startsWith(s.path));
  return (
    <div className="min-h-screen lg:grid lg:grid-cols-[240px_1fr]">
      <aside className="hidden border-r-2 border-stroke/15 lg:flex lg:flex-col lg:gap-8 lg:px-5 lg:py-6">
        <a href="/" className="flex items-center gap-2 text-2xl font-black">
          <span className="sticker grid size-9 place-items-center rounded-xl! bg-lime text-on-accent">B</span>
          Badie
        </a>
        <nav aria-label="App">
          <ul className="space-y-1">
            {sections.map((s) => (
              <li key={s.path}>
                <Link
                  to={s.path}
                  aria-current={current === s ? 'page' : undefined}
                  className="flex items-center gap-3 rounded-xl px-3 py-2.5 font-extrabold text-ink-secondary hover:bg-surface hover:text-ink aria-[current=page]:border-2 aria-[current=page]:border-stroke aria-[current=page]:bg-lime aria-[current=page]:text-on-accent"
                >
                  <Icon name={s.icon} />
                  {s.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </aside>

      <div className="min-w-0 pb-24 lg:pb-0">
        <header className="flex items-center justify-between border-b-2 border-stroke/15 px-5 py-4 lg:hidden">
          <a href="/" className="flex items-center gap-2 text-xl font-black">
            <span className="sticker grid size-8 place-items-center rounded-lg! bg-lime text-sm text-on-accent">B</span>
            Badie
          </a>
          <span className="eyebrow">{current?.label}</span>
        </header>
        <main className="mx-auto max-w-6xl px-5 py-6 lg:px-10 lg:py-10">{children}</main>
      </div>

      <nav aria-label="App" className="fixed inset-x-0 bottom-0 z-20 border-t-2 border-stroke bg-surface lg:hidden">
        <ul className="grid grid-cols-5">
          {sections.map((s) => (
            <li key={s.path}>
              <Link
                to={s.path}
                aria-current={current === s ? 'page' : undefined}
                className="flex flex-col items-center gap-1 py-2.5 text-[11px] font-extrabold text-ink-tertiary aria-[current=page]:text-ink"
              >
                <Icon name={s.icon} className="size-6" />
                {s.label === 'Find partners' ? 'Play' : s.label === 'My games' ? 'Games' : s.label}
              </Link>
            </li>
          ))}
        </ul>
      </nav>
    </div>
  );
}
