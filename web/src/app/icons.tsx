const paths: Record<string, string> = {
  courts: 'M4 5h16v14H4zM12 5v14M4 12h16',
  play: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM9 8l7 4-7 4z',
  games: 'M4 6h16M4 12h16M4 18h10',
  chat: 'M4 5h16v11H9l-5 4z',
  me: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c1-4 4-6 8-6s7 2 8 6',
  star: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z',
  pin: 'M12 21s-7-6.2-7-11a7 7 0 1 1 14 0c0 4.8-7 11-7 11zM12 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
};

export function Icon({ name, className = 'size-5' }: { name: keyof typeof paths; className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinejoin="round" strokeLinecap="round" aria-hidden="true">
      <path d={paths[name]} />
    </svg>
  );
}
