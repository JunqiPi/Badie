import { useEffect, useState, type AnchorHTMLAttributes } from 'react';

const listeners = new Set<() => void>();

export function navigate(to: string, replace = false) {
  history[replace ? 'replaceState' : 'pushState'](null, '', to);
  listeners.forEach((notify) => notify());
}

export function usePath() {
  const [path, setPath] = useState(location.pathname);
  useEffect(() => {
    const update = () => setPath(location.pathname);
    listeners.add(update);
    addEventListener('popstate', update);
    return () => {
      listeners.delete(update);
      removeEventListener('popstate', update);
    };
  }, []);
  return path;
}

export function Link({ to, ...props }: AnchorHTMLAttributes<HTMLAnchorElement> & { to: string }) {
  return (
    <a
      href={to}
      onClick={(event) => {
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
        event.preventDefault();
        navigate(to);
      }}
      {...props}
    />
  );
}
