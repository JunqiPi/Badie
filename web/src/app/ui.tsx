import { useEffect, useId, useState, type ButtonHTMLAttributes, type ReactNode } from 'react';
import { Icon } from './icons';
import { t } from './i18n';
import { IconButton, IconTile } from './kit';

// 类名要写全：Tailwind 只生成在源码里原样出现过的类
const variants = { quiet: 'button-quiet', danger: 'button-danger', inverse: 'button-inverse' };

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
      <label htmlFor={id} className="text-footnote font-bold text-ink-secondary">{label}</label>
      {children({ id, 'aria-describedby': describedBy, 'aria-invalid': error ? true : undefined })}
      {hint && !error && <p id={`${id}-hint`} className="text-caption text-ink-tertiary">{hint}</p>}
      {error && <p id={`${id}-error`} className="text-caption font-bold text-danger">{error}</p>}
    </div>
  );
}

/** 密码输入框：右边“显示 / 隐藏”。autoComplete 用 current-password / new-password，浏览器和 iPhone 钥匙串才会自动填、生成强密码 */
export function PasswordInput({ value, onChange, autoComplete, ...props }: {
  id: string;
  value: string;
  onChange: (value: string) => void;
  autoComplete: 'current-password' | 'new-password';
  'aria-describedby'?: string;
  'aria-invalid'?: true;
}) {
  const [shown, setShown] = useState(false);
  return (
    <div className="relative">
      <input {...props} type={shown ? 'text' : 'password'} autoComplete={autoComplete} required minLength={autoComplete === 'new-password' ? 8 : undefined}
             value={value} onChange={(e) => onChange(e.target.value)} className="field pr-20" />
      <button type="button" onClick={() => setShown(!shown)} aria-label={shown ? t('Hide password') : t('Show password')} aria-controls={props.id}
              className="absolute inset-y-1.5 right-1.5 rounded-[10px] px-3 text-footnote font-bold text-ink-secondary hover:bg-surface-muted hover:text-ink">
        {shown ? t('Hide') : t('Show')}
      </button>
    </div>
  );
}

/** 二级页面的标题：返回按钮 + 大标题，下面一段说明 */
export function PageHeader({ back, eyebrow, title, children }: { back?: string; eyebrow?: string; title: string; children?: ReactNode }) {
  return (
    <header className="mb-6 grid gap-2">
      <div className="flex items-center gap-3">
        {back && <IconButton icon="chevronLeft" label={t('Back')} to={back} />}
        <div className="min-w-0">
          {eyebrow && <p className="text-subhead font-bold text-ink-secondary">{eyebrow}</p>}
          <h1 className="text-title lg:text-display">{title}</h1>
        </div>
      </div>
      {children && <div className="max-w-prose text-subhead text-ink-secondary">{children}</div>}
    </header>
  );
}

/** 空状态：歪一点的图标格 + 标题 + 说明 + 按钮 */
export function EmptyState({ title, children, action }: { title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="sticker grid justify-items-center gap-3 p-6 text-center">
      <IconTile icon="sparkle" tint="lavender" size="lg" className="-rotate-6" />
      <p className="text-title3">{title}</p>
      {children && <div className="max-w-prose text-subhead text-ink-secondary">{children}</div>}
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
    <div aria-live="polite" className="pointer-events-none fixed inset-x-0 bottom-[calc(var(--tabbar)+0.5rem)] z-50 grid justify-items-center gap-2 px-5 lg:top-20 lg:bottom-auto">
      {items.map((t) => (
        <p
          key={t.id}
          role={t.tone === 'error' ? 'alert' : 'status'}
          className={`animate-pop flex max-w-md items-center gap-2 rounded-[16px] border-2 border-stroke px-4 py-3 text-subhead font-bold text-on-accent shadow-low ${t.tone === 'error' ? 'bg-pink' : 'bg-lime'}`}
        >
          <Icon name={t.tone === 'error' ? 'warning' : 'checkCircle'} className="size-5" />
          {t.text}
        </p>
      ))}
    </div>
  );
}
