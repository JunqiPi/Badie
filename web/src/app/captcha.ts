import { useEffect, useRef, useState } from 'react';

// Cloudflare Turnstile：防机器人批量注册 / 刷验证码邮件。没配置 site key（本地开发、CI）时不启用
const siteKey = import.meta.env.PUBLIC_TURNSTILE_SITE_KEY as string | undefined;

type Turnstile = {
  render: (el: HTMLElement, options: Record<string, unknown>) => string;
  reset: (id: string) => void;
  remove: (id: string) => void;
};
declare global {
  interface Window { turnstile?: Turnstile }
}

let script: Promise<void> | undefined;
const load = () =>
  (script ??= new Promise((resolve, reject) => {
    const el = document.createElement('script');
    el.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    el.async = true;
    el.onload = () => resolve();
    el.onerror = () => reject(new Error('Turnstile failed to load'));
    document.head.append(el);
  }));

/** 返回要挂载的容器、当前 token（一次性，用完要 reset） */
export function useCaptcha() {
  const container = useRef<HTMLDivElement>(null);
  const widget = useRef<string>(undefined);
  const [token, setToken] = useState<string>();
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!siteKey || !container.current) return;
    let cancelled = false;
    load()
      .then(() => {
        if (cancelled || !container.current) return;
        widget.current = window.turnstile!.render(container.current, {
          sitekey: siteKey,
          appearance: 'interaction-only',
          callback: setToken,
          'expired-callback': () => setToken(undefined),
          'error-callback': () => setToken(undefined),
        });
      })
      .catch(() => setFailed(true));
    return () => {
      cancelled = true;
      if (widget.current) window.turnstile?.remove(widget.current);
    };
  }, []);

  return {
    container,
    token,
    enabled: Boolean(siteKey),
    ready: !siteKey || Boolean(token),
    failed,
    reset() {
      setToken(undefined);
      if (widget.current) window.turnstile?.reset(widget.current);
    },
  };
}
