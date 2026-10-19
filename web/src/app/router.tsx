import { useEffect, useState, type AnchorHTMLAttributes } from 'react';

const listeners = new Set<() => void>();

// 静态页面（球馆目录）上没有 App，链接都是普通的整页跳转；App 加载后才在页面里切换
let spa = false;
export const enableSpa = () => void (spa = true);
/** 球馆目录（总页、国家、城市、球馆）和隐私政策、用户协议是静态页面，要整页打开 */
const isStatic = (to: string) => /^\/(courts|privacy|terms)\//.test(to);

export function navigate(to: string, replace = false) {
  if (!spa || isStatic(to)) return location[replace ? 'replace' : 'assign'](to);
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
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0 || !spa || isStatic(to)) return;
        event.preventDefault();
        navigate(to);
      }}
      {...props}
    />
  );
}
