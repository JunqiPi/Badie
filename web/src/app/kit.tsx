// 设计系统组件：和 iOS 的 DesignSystem（Surfaces / Buttons / Identity / Feedback / Shapes）一一对应，
// 样式变量在 styles/global.css。类名都写全，Tailwind 只生成源码里原样出现过的类
import type { ReactNode } from 'react';
import { tier } from './assessment';
import { t } from './i18n';
import { Icon, Shuttlecock, type IconName } from './icons';
import { Link } from './router';
import { avatarUrl } from './supabase';

export type Tint = 'lime' | 'lavender' | 'peach' | 'pink' | 'sky' | 'butter' | 'mint' | 'surface' | 'muted';

export const fill: Record<Tint, string> = {
  lime: 'bg-lime text-on-accent',
  lavender: 'bg-lavender text-on-accent',
  peach: 'bg-peach text-on-accent',
  pink: 'bg-pink text-on-accent',
  sky: 'bg-sky text-on-accent',
  butter: 'bg-butter text-on-accent',
  mint: 'bg-mint text-on-accent',
  surface: 'bg-surface text-ink',
  muted: 'bg-surface-muted text-ink',
};

/** 头像和贴纸的调色板：按用户 id 稳定取色 */
const palette: Tint[] = ['lavender', 'sky', 'peach', 'mint', 'butter', 'pink'];
export function paletteTint(id: string): Tint {
  let hash = 0;
  for (const char of id) hash = (hash * 31 + char.charCodeAt(0)) | 0;
  return palette[Math.abs(hash) % palette.length];
}

/** 按钮或链接：有 to 就是站内链接，有 href 就是外链，否则是按钮 */
type Action = { to?: string; href?: string; onClick?: () => void };

function Pressable({ to, href, onClick, className, label, children }: Action & { className: string; label?: string; children: ReactNode }) {
  if (to) return <Link to={to} className={className} aria-label={label}>{children}</Link>;
  if (href) return <a href={href} className={className} aria-label={label}>{children}</a>;
  return <button type="button" onClick={onClick} className={className} aria-label={label}>{children}</button>;
}

// MARK: 图标

const tileSizes = {
  sm: ['size-[34px] rounded-[10px]', 'size-4'],
  md: ['size-11 rounded-[13px]', 'size-5'],
  lg: ['size-[52px] rounded-[16px]', 'size-6'],
  xl: ['size-16 rounded-[19px]', 'size-7'],
} as const;

/** 彩色图标格（iOS 的 IconTile） */
export function IconTile({ icon, tint = 'lime', size = 'md', className = '' }: { icon: IconName; tint?: Tint; size?: keyof typeof tileSizes; className?: string }) {
  const [box, glyph] = tileSizes[size];
  return (
    <span aria-hidden="true" className={`grid shrink-0 place-items-center border-2 border-stroke ${box} ${fill[tint]} ${className}`}>
      <Icon name={icon} className={glyph} />
    </span>
  );
}

/** 红色数字角标（读屏不读，数量写在按钮的名字里） */
export function CountBadge({ count, className = '' }: { count: number; className?: string }) {
  if (count <= 0) return null;
  return (
    <span aria-hidden="true" className={`grid h-5 min-w-5 place-items-center rounded-full border-2 border-canvas bg-danger-fill px-1 text-[11px] leading-none font-black text-white tabular-nums ${className}`}>
      {count > 99 ? '99+' : count}
    </span>
  );
}

/** 44px 方形图标按钮（iOS 的 IconButton），可带角标 */
export function IconButton({ icon, label, badge = 0, tint = 'surface', ...action }: Action & { icon: IconName; label: string; badge?: number; tint?: Tint }) {
  return (
    <Pressable {...action} label={label} className={`lift relative grid size-11 shrink-0 place-items-center rounded-[14px] border-2 border-stroke shadow-low ${fill[tint]}`}>
      <Icon name={icon} className="size-5" />
      <CountBadge count={badge} className="absolute -top-2 -right-2" />
    </Pressable>
  );
}

// MARK: 身份

/** 头像：有照片显示照片，否则彩色底 + 名字首字 */
export function Avatar({ id, name, photo, size = 44, className = '' }: { id: string; name: string; photo?: string | null; size?: number; className?: string }) {
  const style = { width: size, height: size, fontSize: size * 0.42 };
  const border = size >= 56 ? 'border-[2.5px]' : 'border-2';
  if (photo) return <img src={avatarUrl(photo)} alt="" width={size} height={size} style={style} className={`shrink-0 rounded-full ${border} border-stroke object-cover ${className}`} />;
  return (
    <span aria-hidden="true" style={style} className={`grid shrink-0 place-items-center rounded-full ${border} border-stroke font-black ${fill[paletteTint(id)]} ${className}`}>
      {[...name.trim()][0]?.toUpperCase() ?? '?'}
    </span>
  );
}

/** 重叠头像（最多 4 个，多的显示 +n） */
export function AvatarStack({ people, size = 32, max = 4 }: { people: { id: string; nickname: string }[]; size?: number; max?: number }) {
  const extra = people.length - max;
  return (
    <span className="flex" aria-label={people.map((p) => p.nickname).join(', ')} role="img">
      {people.slice(0, max).map((p, i) => (
        <span key={p.id} style={{ marginLeft: i ? -size * 0.32 : 0, zIndex: max - i }} className="relative">
          <Avatar id={p.id} name={p.nickname} size={size} />
        </span>
      ))}
      {extra > 0 && (
        <span aria-hidden="true" style={{ width: size, height: size, fontSize: size * 0.36, marginLeft: -size * 0.32 }}
              className="grid place-items-center rounded-full border-2 border-stroke bg-surface-muted font-black text-ink">
          +{extra}
        </span>
      )}
    </span>
  );
}

/** 等级徽章：墨色底、柠檬绿字（iOS 的 LevelBadge） */
export function LevelBadge({ rating, named = true, compact = false }: { rating: number; named?: boolean; compact?: boolean }) {
  const level = tier(rating);
  return (
    <span className={`inline-flex shrink-0 items-center rounded-[7px] bg-[#17140f] font-black whitespace-nowrap text-lime ${compact ? 'px-1.5 py-px text-[10px]' : 'px-2 py-0.5 text-caption'}`}>
      Lv.{level.label}{named && ` ${level.name}`}
    </span>
  );
}

/** 小标签（新球友、靠谱、已认证……） */
export function Tag({ icon, tint = 'surface', children }: { icon?: IconName; tint?: Tint; children: ReactNode }) {
  return (
    <span className={`chip ${fill[tint]}`}>
      {icon && <Icon name={icon} className="size-3" />}
      {children}
    </span>
  );
}

// MARK: 选择

/** 分段控件（iOS 的 SegmentedSticker）：选中项是墨色胶囊 */
export function Segmented<T extends string>({ options, value, onChange, label }: {
  options: { value: T; label: string; badge?: number }[];
  value: T;
  onChange: (value: T) => void;
  label: string;
}) {
  return (
    <div role="group" aria-label={label} className="flex gap-1 rounded-[16px] border-2 border-stroke bg-surface p-1">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          aria-pressed={o.value === value}
          onClick={() => onChange(o.value)}
          className="flex min-h-10 flex-1 items-center justify-center gap-1.5 rounded-[12px] px-3 text-subhead font-bold text-ink-secondary transition-colors duration-[var(--dur-1)] hover:text-ink aria-pressed:bg-inverse aria-pressed:text-on-inverse"
        >
          {o.label}
          <CountBadge count={o.badge ?? 0} />
        </button>
      ))}
    </div>
  );
}

// MARK: 标题

/** Tab 根页面的大标题（iOS 的 LargeTitleHeader），右边放图标按钮 */
export function LargeTitle({ title, subtitle, children }: { title: string; subtitle?: string; children?: ReactNode }) {
  return (
    <header className="flex items-center gap-3">
      <div className="min-w-0 flex-1">
        {subtitle && <p className="text-subhead font-bold text-ink-secondary">{subtitle}</p>}
        <h1 className="text-display lg:text-[2.75rem]">{title}</h1>
      </div>
      {children && <div className="flex shrink-0 gap-2.5">{children}</div>}
    </header>
  );
}

/** 二级页面的标题栏（iOS 的 ScreenHeader）：返回按钮 + 居中标题 */
export function ScreenHeader({ title, back, children }: { title: string; back: string; children?: ReactNode }) {
  return (
    <header className="grid grid-cols-[2.75rem_1fr_auto] items-center gap-3 lg:grid-cols-[2.75rem_auto_1fr]">
      <IconButton icon="chevronLeft" label={t('Back')} to={back} />
      <h1 className="truncate text-center text-headline lg:text-left lg:text-title2">{title}</h1>
      <div className="flex min-w-[2.75rem] justify-end gap-2.5">{children}</div>
    </header>
  );
}

/** 分区标题：标题 + 灰色说明 + 右边的“全部”（说明太长时换到标题下面） */
export function SectionTitle({ title, detail, action, id }: { title: string; detail?: string; action?: Action & { label: string }; id?: string }) {
  return (
    <div className="grid grid-cols-[1fr_auto] items-baseline gap-x-2">
      <div className="flex min-w-0 flex-wrap items-baseline gap-x-2">
        <h2 id={id} className="text-title3">{title}</h2>
        {detail && <span className="text-footnote font-bold text-ink-secondary">{detail}</span>}
      </div>
      {action && (
        <Pressable {...action} className="press -my-2 flex min-h-11 shrink-0 items-center gap-0.5 text-footnote font-bold text-ink-secondary hover:text-ink">
          {action.label}
          <Icon name="chevronRight" className="size-3.5" />
        </Pressable>
      )}
    </div>
  );
}

// MARK: 内容块

/** 统计格（iOS 的 StatTile），可加图标和颜色；stacked = 图标在上（窄的格子） */
export function StatTile({ value, label, tint = 'surface', icon, stacked = false }: { value: ReactNode; label: string; tint?: Tint; icon?: IconName; stacked?: boolean }) {
  return (
    <div className={`tile flex min-w-0 gap-3 rounded-[14px]! px-3 py-3 ${stacked ? 'flex-col gap-1.5 lg:flex-row lg:items-center lg:gap-3' : 'items-center'} ${fill[tint]}`}>
      {icon && <IconTile icon={icon} tint="surface" size="sm" />}
      <div className="min-w-0">
        <p className="truncate text-[1.5rem] leading-tight font-black tabular-nums">{value}</p>
        <p className={`truncate text-caption ${tint === 'surface' ? 'text-ink-secondary' : ''}`}>{label}</p>
      </div>
    </div>
  );
}

/** 列表行：图标格 + 标题 + 说明 + 右边的箭头（iOS 的 MenuRow / InfoRow） */
export function Row({ icon, tint = 'lavender', title, subtitle, value, badge = 0, danger, children, ...action }: Action & {
  icon: IconName;
  tint?: Tint;
  title: ReactNode;
  subtitle?: ReactNode;
  value?: ReactNode;
  badge?: number;
  danger?: boolean;
  children?: ReactNode;
}) {
  const clickable = Boolean(action.to || action.href || action.onClick);
  const body = (
    <>
      <IconTile icon={icon} tint={tint} size="sm" />
      <span className="min-w-0 flex-1">
        <span className={`block font-bold ${danger ? 'text-danger' : ''}`}>{title}</span>
        {subtitle && <span className="block text-footnote text-ink-secondary">{subtitle}</span>}
      </span>
      <CountBadge count={badge} />
      {value && <span className="shrink-0 text-footnote font-bold text-ink-secondary">{value}</span>}
      {children}
      {clickable && <Icon name="chevronRight" className="size-3.5 text-ink-tertiary" />}
    </>
  );
  const className = 'flex min-h-14 w-full items-center gap-3 py-2.5 text-left';
  if (!clickable) return <div className={className}>{body}</div>;
  return <Pressable {...action} className={`${className} press rounded-[12px] transition-colors hover:bg-surface-muted/60 -mx-2 px-2 w-[calc(100%+1rem)]`}>{body}</Pressable>;
}

/** 卡片里的分割线 */
export const Divider = () => <hr className="h-[1.5px] border-0 bg-divider" />;

/** 横幅（iOS 的 NoticeBanner）：色块 + 图标 + 一句话 + 小按钮 */
export function Notice({ icon, tint = 'butter', children, action }: { icon: IconName; tint?: Tint; children: ReactNode; action?: Action & { label: string } }) {
  return (
    <div className={`tile flex items-center gap-3 rounded-[16px]! p-3 ${fill[tint]}`}>
      <Icon name={icon} className="size-5" />
      <p className="min-w-0 flex-1 text-footnote font-bold">{children}</p>
      {action && <Pressable {...action} className="button button-sm button-quiet shrink-0">{action.label}</Pressable>}
    </div>
  );
}

/** 空状态（iOS 的 EmptyStateView）：歪一点的大图标格 + 标题 + 说明 + 按钮 */
export function Empty({ icon, tint = 'lavender', title, children, action, card = true }: {
  icon: IconName;
  tint?: Tint;
  title: string;
  children?: ReactNode;
  action?: Action & { label: string };
  card?: boolean;
}) {
  return (
    <div className={`grid justify-items-center gap-3 p-6 text-center ${card ? 'sticker' : ''}`}>
      <IconTile icon={icon} tint={tint} size="xl" className="-rotate-6" />
      <p className="text-title3">{title}</p>
      {children && <div className="max-w-sm text-subhead text-ink-secondary">{children}</div>}
      {action && <Pressable {...action} className="button mt-1">{action.label}</Pressable>}
    </div>
  );
}

/** 箭头按钮的内容：文字 + 右边的柠檬绿箭头块（iOS 的 ArrowButtonLabel） */
export function ArrowLabel({ children }: { children: ReactNode }) {
  return (
    <>
      <span className="flex-1 text-left">{children}</span>
      <span aria-hidden="true" className="-mr-2 grid size-10 place-items-center rounded-[12px] bg-lime text-on-accent">
        <Icon name="arrowRight" className="size-5" />
      </span>
    </>
  );
}

/** 虚线分割（票据中间） */
export const Dashed = () => <hr aria-hidden="true" className="border-0 border-t-2 border-dashed border-current opacity-70" />;

/** 爆炸星形徽章（VS、名次） */
export function Starburst({ children, tint = 'butter', size = 72 }: { children: ReactNode; tint?: Tint; size?: number }) {
  const points = Array.from({ length: 24 }, (_, i) => {
    const angle = (i * Math.PI) / 12 - Math.PI / 2;
    const r = i % 2 ? 39 : 50;
    return `${50 + Math.cos(angle) * r},${50 + Math.sin(angle) * r}`;
  }).join(' ');
  return (
    <span className="relative grid shrink-0 place-items-center text-on-accent" style={{ width: size, height: size }}>
      <svg viewBox="-2 -2 106 106" className="absolute inset-0" aria-hidden="true">
        <polygon points={points} transform="translate(2 3)" fill="var(--color-shadow)" />
        <polygon points={points} fill={`var(--color-${tint})`} stroke="var(--color-stroke)" strokeWidth="2" strokeLinejoin="round" />
      </svg>
      <span className="relative font-black" style={{ fontSize: size * 0.3 }}>{children}</span>
    </span>
  );
}

/** 文字标识 “badie.” */
export function Wordmark({ className = 'text-[1.75rem]', inverse = false }: { className?: string; inverse?: boolean }) {
  return (
    <span className={`inline-flex items-baseline font-black tracking-tight ${inverse ? 'text-on-bar' : 'text-ink'} ${className}`}>
      badie
      <span aria-hidden="true" className="ml-[0.04em] inline-block size-[0.3em] rounded-full border-[0.06em] border-stroke bg-lime" />
    </span>
  );
}


/** 欢迎页的插画（iOS 的 WelcomeCardFan）：三张展开的球友卡 + 羽毛球 + GO 星形 */
export function CardFan({ className = '' }: { className?: string }) {
  const cards: [string, number, Tint, number, Tint][] = [
    ['Mia', 6.67, 'lavender', -14, 'mint'],
    ['AJ', 4.33, 'peach', 0, 'butter'],
    ['Alex', 6, 'sky', 14, 'pink'],
  ];
  return (
    <div aria-hidden="true" className={`relative mx-auto h-[15rem] w-[22rem] max-w-full ${className}`}>
      {cards.map(([name, rating, tint, angle, avatar], i) => (
        <div
          key={name}
          style={{ ['--angle' as string]: `${angle}deg`, ['--x' as string]: `${(i - 1) * 78}px` }}
          className={`sticker fan-card absolute bottom-6 left-1/2 grid h-[168px] w-32 -translate-x-1/2 place-content-center justify-items-center gap-2 rounded-[22px]! ${fill[tint]} ${i === 1 ? 'z-10 mb-4' : ''}`}
        >
          <span className={`grid size-[54px] place-items-center rounded-full border-2 border-stroke text-[1.4rem] font-black ${fill[avatar]}`}>{[...t(name)][0]}</span>
          <span className="text-headline">{t(name)}</span>
          <LevelBadge rating={rating} />
        </div>
      ))}
      <Shuttlecock className="absolute top-0 right-2 size-16 rotate-[-24deg]" />
      <span className="absolute bottom-0 left-0"><Starburst tint="lime" size={64}>GO</Starburst></span>
    </div>
  );
}
