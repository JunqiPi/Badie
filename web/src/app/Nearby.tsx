import { useEffect, useRef, type ReactNode } from 'react';
import { t } from './i18n';
import { Icon } from './icons';
import { Avatar, LevelBadge, Tag } from './kit';
import { Link } from './router';
import { tagText, type InviteUser } from './supabase';
import { freeSummary, slotLabel, toMinutes, type UsualTime } from './usual';

// 附近的人：卡片上的空闲时间，和几个页面共用的半屏、小卡片

/** 底部弹出的半屏（手机）/ 居中的小窗（桌面）。onClose：Esc、点外面、程序关掉都会调 */
export function Sheet({ open, onClose, labelledBy, children }: { open: boolean; onClose: () => void; labelledBy: string; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (open && !ref.current?.open) ref.current?.showModal();
    else if (!open && ref.current?.open) ref.current.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      aria-labelledby={labelledBy}
      onClose={onClose}
      onClick={(event) => event.target === event.currentTarget && event.currentTarget.close()}
      className="m-0 mt-auto max-h-[90dvh] w-full max-w-none bg-transparent p-0 text-ink open:animate-sheet sm:m-auto sm:max-w-md sm:open:animate-pop"
    >
      {open && (
        <div className="grid max-h-[90dvh] gap-4 overflow-y-auto rounded-t-[28px] border-2 border-b-0 border-stroke bg-canvas px-5 pt-5 pb-[calc(1.25rem+env(safe-area-inset-bottom))] sm:rounded-[28px] sm:border-b-2 sm:shadow-card">
          {children}
        </div>
      )}
    </dialog>
  );
}

/** 空闲时间按星期（周一在前）和开始时间排 */
export const sortUsual = (times: UsualTime[] | null | undefined) =>
  [...(times ?? [])].sort((a, b) => (a.weekday + 5) % 7 - (b.weekday + 5) % 7 || toMinutes(a.start) - toMinutes(b.start));

/** 卡片上 TA 的空闲时间：最多 2 个柠檬绿小胶囊，多了 +N。点一个就约那段时间；没有 onPick（自己的卡片）就只显示 */
export function UsualChips({ times, onPick }: { times: UsualTime[] | null | undefined; onPick?: (slot: UsualTime) => void }) {
  const sorted = sortUsual(times);
  if (!sorted.length) return null;
  const more = sorted.length - 2;
  const chip = 'grid min-h-9 place-items-center rounded-full border-2 border-stroke bg-lime px-3 text-footnote font-black whitespace-nowrap text-on-accent';
  return (
    <ul className="flex flex-wrap items-center gap-1.5" aria-label={t('Usually free')}>
      {sorted.slice(0, 2).map((slot) => (
        <li key={`${slot.weekday}-${slot.start}`}>
          {onPick ? (
            <button type="button" onClick={() => onPick(slot)} aria-label={t('Invite for {time}', { time: slotLabel(slot) })} className={`press ${chip}`}>
              {slotLabel(slot)}
            </button>
          ) : <span className={chip}>{slotLabel(slot)}</span>}
        </li>
      ))}
      {more > 0 && <li className={chip}>+{more}</li>}
    </ul>
  );
}

/** 资料上的一行：“常有空：工作日晚上 · 周末下午” */
export function FreeLine({ times }: { times: UsualTime[] | null | undefined }) {
  const summary = freeSummary(times);
  if (!summary) return null;
  return (
    <p className="flex items-center gap-2 text-subhead font-bold">
      <Icon name="calendar" className="size-4 shrink-0" />
      {t('Usually free: {times}', { times: summary })}
    </p>
  );
}

/** 小卡片：头像、名字、等级、靠谱 */
export function MiniCard({ user }: { user: InviteUser }) {
  return (
    <Link to={`/players/${user.id}/`} className="sticker press flex items-center gap-3 p-3">
      <Avatar id={user.id} name={user.nickname} photo={user.avatar} size={48} />
      <span className="grid min-w-0 flex-1 gap-1">
        <span className="flex min-w-0 font-bold">
          <span className="truncate">{user.nickname}</span>
          {user.tag != null && <span className="shrink-0 text-ink-tertiary">&nbsp;{tagText(user.tag)}</span>}
        </span>
        <span className="flex flex-wrap gap-1.5">
          <LevelBadge rating={user.rating} compact />
          {(user.recent_no_shows ?? 0) === 0 && <Tag icon="reliable" tint="mint">{t('Reliable')}</Tag>}
        </span>
      </span>
      <Icon name="chevronRight" className="size-4 text-ink-tertiary" />
    </Link>
  );
}
