import { useEffect, useId, useState, type ButtonHTMLAttributes, type ReactNode } from 'react';
import { currentLocale, languages, setLocale, t, type Locale } from './i18n';

// 类名要写全：Tailwind 只生成在源码里原样出现过的类
const variants = { quiet: 'button-quiet', danger: 'button-danger' };

/** 按钮：busy 时显示转圈并禁用，防止重复提交 */
export function Button({ busy, variant, className = '', children, disabled, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & {
  busy?: boolean;
  variant?: keyof typeof variants;
}) {
  return (
    <button
      {...props}
      disabled={disabled || busy}
      aria-busy={busy || undefined}
      className={`button ${variant ? variants[variant] : ''} ${className}`}
    >
      {busy && <span aria-hidden="true" className="size-4 animate-spin rounded-full border-2 border-current border-t-transparent" />}
      {children}
    </button>
  );
}

/** 表单项：标签、说明和错误通过 aria-describedby 连到输入框上 */
export function Field({ label, hint, error, children }: {
  label: string;
  hint?: string;
  error?: string;
  children: (props: { id: string; 'aria-describedby'?: string; 'aria-invalid'?: true }) => ReactNode;
}) {
  const id = useId();
  const describedBy = [hint && `${id}-hint`, error && `${id}-error`].filter(Boolean).join(' ') || undefined;
  return (
    <div className="grid gap-1.5">
      <label htmlFor={id} className="font-extrabold">{label}</label>
      {children({ id, 'aria-describedby': describedBy, 'aria-invalid': error ? true : undefined })}
      {hint && !error && <p id={`${id}-hint`} className="text-sm font-semibold text-ink-tertiary">{hint}</p>}
      {error && <p id={`${id}-error`} className="text-sm font-bold text-danger">{error}</p>}
    </div>
  );
}

/** 页面标题：每个页面同样的层级和间距 */
/** eyebrow 是所在的版块；和标题一样时省略 */
export function PageHeader({ eyebrow, title, children }: { eyebrow?: string; title: string; children?: ReactNode }) {
  return (
    <header className="mb-8">
      {eyebrow && <p className="eyebrow mb-2">{eyebrow}</p>}
      <h1 className="display text-[clamp(2.5rem,6vw,3.75rem)]">{title}</h1>
      {children && <div className="mt-3 max-w-prose text-lg text-ink-secondary">{children}</div>}
    </header>
  );
}

export function EmptyState({ title, children, action }: { title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="tile grid justify-items-start gap-3 bg-surface p-6">
      <p className="text-lg font-black">{title}</p>
      {children && <div className="max-w-prose text-ink-secondary">{children}</div>}
      {action}
    </div>
  );
}

export function Skeleton({ className = '' }: { className?: string }) {
  return <div aria-hidden="true" className={`skeleton ${className}`} />;
}

type Toast = { id: number; text: string; tone: 'info' | 'error' };
const toastListeners = new Set<(toasts: Toast[]) => void>();
let toasts: Toast[] = [];

/** 操作结果提示：屏幕阅读器会读出来，4 秒后自动消失 */
export function toast(text: string, tone: Toast['tone'] = 'info') {
  const item = { id: Date.now() + Math.random(), text, tone };
  toasts = [...toasts, item];
  toastListeners.forEach((notify) => notify(toasts));
  setTimeout(() => {
    toasts = toasts.filter((t) => t.id !== item.id);
    toastListeners.forEach((notify) => notify(toasts));
  }, 4000);
}

export function Toasts() {
  const [items, setItems] = useState(toasts);
  useEffect(() => {
    toastListeners.add(setItems);
    return () => void toastListeners.delete(setItems);
  }, []);
  return (
    <div aria-live="polite" className="pointer-events-none fixed inset-x-0 bottom-[calc(5rem+env(safe-area-inset-bottom))] z-50 grid justify-items-center gap-2 px-4 lg:bottom-6">
      {items.map((t) => (
        <p
          key={t.id}
          role={t.tone === 'error' ? 'alert' : 'status'}
          className={`sticker animate-pop max-w-md px-4 py-3 font-bold ${t.tone === 'error' ? 'bg-pink text-on-accent' : ''}`}
        >
          {t.text}
        </p>
      ))}
    </div>
  );
}

/** 界面语言：选了就记住（只存在这个浏览器里） */
export function LanguagePicker({ className = '' }: { className?: string }) {
  return (
    <label className={`flex items-center gap-2 text-sm font-bold text-ink-secondary ${className}`}>
      <span>{t('Language')}</span>
      <select value={currentLocale()} onChange={(e) => setLocale(e.target.value as Locale, true)} className="field min-h-10 w-auto py-1">
        {languages.map(([code, name]) => <option key={code} value={code}>{name}</option>)}
      </select>
    </label>
  );
}
