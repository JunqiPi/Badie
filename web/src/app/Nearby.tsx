import { useEffect, useRef, useState, type ReactNode } from 'react';
import { t } from './i18n';
import { Icon } from './icons';
import { Avatar, IconButton, LevelBadge, Tag } from './kit';
import { Link } from './router';
import { problem, supabase, tagText, type InviteUser, type NearbyPlayer } from './supabase';
import { Button, toast } from './ui';
import { freeSummary, slotLabel, toMinutes, type UsualTime } from './usual';

// 附近的人：卡片上的空闲时间、加球友，和几个页面共用的半屏、规则按钮

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

/** 标题旁的“?”：规则放在这里，页面上不写解释 */
export function RulesButton({ points }: { points: string[] }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <IconButton icon="question" label={t('How it works')} onClick={() => setOpen(true)} />
      <Sheet open={open} onClose={() => setOpen(false)} labelledBy="rules-title">
        <div className="flex items-center gap-3">
          <h2 id="rules-title" className="flex-1 text-title3">{t('How it works')}</h2>
          <IconButton icon="x" label={t('Close')} onClick={() => setOpen(false)} />
        </div>
        <ul className="grid gap-2 text-subhead">
          {points.map((p) => (
            <li key={p} className="flex gap-2"><span aria-hidden="true" className="mt-2 size-1.5 shrink-0 rounded-full bg-ink" />{p}</li>
          ))}
        </ul>
      </Sheet>
    </>
  );
}

/** 空闲时间按星期（周一在前）和开始时间排 */
export const sortUsual = (times: UsualTime[] | null | undefined) =>
  [...(times ?? [])].sort((a, b) => (a.weekday + 5) % 7 - (b.weekday + 5) % 7 || toMinutes(a.start) - toMinutes(b.start));

/** 卡片上 TA 的空闲时间：最多 4 个可点的小标签，多了 +N。点一个就约那段时间 */
export function UsualChips({ times, onPick }: { times: UsualTime[] | null | undefined; onPick: (slot: UsualTime) => void }) {
  const sorted = sortUsual(times);
  if (!sorted.length) return null;
  const more = sorted.length - 4;
  return (
    <ul className="flex flex-wrap items-center gap-1.5" aria-label={t('Usually free')}>
      <li aria-hidden="true"><Icon name="calendar" className="size-4 text-ink-secondary" /></li>
      {sorted.slice(0, 4).map((slot) => (
        <li key={`${slot.weekday}-${slot.start}`}>
          <button type="button" onClick={() => onPick(slot)} aria-label={t('Invite for {time}', { time: slotLabel(slot) })}
                  className="press min-h-9 rounded-full border-2 border-stroke bg-surface px-3 text-footnote font-bold hover:bg-lime">
            {slotLabel(slot)}
          </button>
        </li>
      ))}
      {more > 0 && <li className="text-footnote font-bold text-ink-secondary">+{more}</li>}
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

type FriendState = Pick<NearbyPlayer, 'is_friend' | 'friend_request'>;

/** 加球友 / 已申请 / 接受 / 发消息（用现有的好友申请，不占每天 10 个邀请） */
export function FriendButton({ id, state, onChange }: { id: string; state: FriendState; onChange: (state: FriendState) => void }) {
  const [busy, setBusy] = useState(false);
  if (state.is_friend) {
    return <Link to={`/messages/dm/${id}/`} className="button button-sm button-quiet"><Icon name="chat" className="size-4" />{t('Send a message')}</Link>;
  }
  if (state.friend_request === 'sent') {
    return <span className="flex min-h-11 items-center gap-1.5 text-footnote font-bold text-ink-secondary"><Icon name="check" className="size-4" />{t('Requested')}</span>;
  }
  async function add() {
    setBusy(true);
    const accept = state.friend_request === 'received';
    const { data, error } = accept
      ? await supabase!.rpc('respond_friend_request', { p_user: id, p_accept: true })
      : await supabase!.rpc('send_friend_request', { p_user: id });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    if (accept || data === 'friends') {
      onChange({ is_friend: true, friend_request: null });
      toast(t('You’re now friends'));
    } else {
      onChange({ is_friend: false, friend_request: 'sent' });
      toast(t('Friend request sent'));
    }
  }
  return (
    <Button className="button-sm" variant="quiet" busy={busy} onClick={add}>
      <Icon name="userPlus" className="size-4" />{state.friend_request === 'received' ? t('Accept') : t('Add friend')}
    </Button>
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
