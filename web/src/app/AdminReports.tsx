import { useState } from 'react';
import { t } from './i18n';
import { Avatar, Tag } from './kit';
import { Link } from './router';
import { problem, supabase, useLive } from './supabase';
import { day, relative } from './time';
import { Button, EmptyState, Skeleton, toast } from './ui';

interface ReportItem {
  id: number;
  reason: string;
  details: string | null;
  created_at: string;
  reporter: { id: string; nickname: string };
  reported: { id: string; nickname: string; avatar: string | null; suspended: boolean };
  open_reports: number;
  /** 被举报人最近 30 天在举报人看得到的会话里发的消息 */
  messages: { body: string; at: string }[];
}

type Action = 'dismiss' | 'reset_nickname' | 'clear_avatar' | 'suspend';

const reasonText: Record<string, string> = {
  harassment: 'Harassment or unwanted messages',
  scam: 'Asked for money or personal details',
  unsafe: 'Unsafe or aggressive play',
  fake: 'Fake profile or level',
  wrong_gender: 'Wrong gender on their profile',
  inappropriate: 'Inappropriate name, photo or messages',
  other: 'Something else',
};

/** 举报队列：用户协议写了 24 小时内处理。处理（不算驳回）会把这个人所有没处理的举报一起结案 */
export function ReportQueue() {
  const { data: queue, refresh } = useLive<ReportItem[]>('admin_report_queue', { every: 60_000 });
  return (
    <section aria-labelledby="reports" className="grid gap-4">
      <h2 id="reports" className="text-title2">{t('Reports')}</h2>
      {!queue ? <Skeleton className="h-40" /> : queue.length === 0 ? (
        <EmptyState title={t('No open reports')} />
      ) : (
        queue.map((item) => <Report key={item.id} item={item} onDone={refresh} />)
      )}
    </section>
  );
}

function Report({ item, onDone }: { item: ReportItem; onDone: () => void }) {
  const [busy, setBusy] = useState<Action>();
  const [confirmSuspend, setConfirmSuspend] = useState(false);
  // 超过 20 小时还没处理就标红，提醒 24 小时的承诺
  const overdue = Date.now() - new Date(item.created_at).getTime() > 20 * 3600000;

  async function resolve(action: Action) {
    setBusy(action);
    const { error } = await supabase!.rpc('admin_resolve_report', { p_report: item.id, p_action: action });
    setBusy(undefined);
    if (error) return toast(problem(error), 'error');
    toast(t('Done'));
    onDone();
  }

  return (
    <article className="sticker grid gap-3 p-5">
      <div className="flex items-center gap-3">
        <Avatar id={item.reported.id} name={item.reported.nickname} photo={item.reported.avatar} size={48} />
        <div className="min-w-0 flex-1">
          <Link to={`/players/${item.reported.id}/`} className="link font-bold">{item.reported.nickname}</Link>
          <p className="text-footnote text-ink-secondary">
            {t('Reported by {name}', { name: item.reporter.nickname })} · {relative(item.created_at)}
          </p>
        </div>
        {item.reported.suspended && <Tag tint="muted">{t('Suspended')}</Tag>}
        {overdue && <Tag tint="pink">{t('Due soon')}</Tag>}
      </div>
      <dl className="grid gap-1 text-footnote sm:grid-cols-[10rem_1fr]">
        <dt className="font-bold text-ink-tertiary">{t('Reason')}</dt>
        <dd>{t(reasonText[item.reason] ?? item.reason)}</dd>
        {item.details && (<><dt className="font-bold text-ink-tertiary">{t('Details')}</dt><dd className="break-words">{item.details}</dd></>)}
        {item.open_reports > 1 && (<><dt className="font-bold text-ink-tertiary">{t('Open reports')}</dt><dd>{item.open_reports}</dd></>)}
      </dl>
      {item.messages.length > 0 && (
        <details className="rounded-[12px] bg-surface-muted p-3 text-footnote">
          <summary className="cursor-pointer font-bold">{t('Their messages to the reporter ({n})', { n: item.messages.length })}</summary>
          <ul className="mt-2 grid gap-1.5">
            {item.messages.map((m, i) => (
              <li key={i} className="break-words"><span className="text-ink-tertiary">{day(m.at)}</span> {m.body}</li>
            ))}
          </ul>
        </details>
      )}
      <div className="flex flex-wrap gap-2">
        <Button variant="quiet" className="button-sm" busy={busy === 'reset_nickname'} disabled={Boolean(busy)} onClick={() => resolve('reset_nickname')}>
          {t('Reset nickname')}
        </Button>
        {item.reported.avatar && (
          <Button variant="quiet" className="button-sm" busy={busy === 'clear_avatar'} disabled={Boolean(busy)} onClick={() => resolve('clear_avatar')}>
            {t('Remove photo')}
          </Button>
        )}
        {confirmSuspend ? (
          <Button variant="danger" className="button-sm" busy={busy === 'suspend'} disabled={Boolean(busy)} onClick={() => resolve('suspend')}>
            {t('Yes, suspend the account')}
          </Button>
        ) : (
          <Button variant="quiet" className="button-sm" disabled={Boolean(busy)} onClick={() => setConfirmSuspend(true)}>{t('Suspend account')}</Button>
        )}
        <Button variant="quiet" className="button-sm" busy={busy === 'dismiss'} disabled={Boolean(busy)} onClick={() => resolve('dismiss')}>
          {t('Dismiss')}
        </Button>
      </div>
    </article>
  );
}

interface AppealItem {
  id: number;
  level: number;
  appeal: string;
  appealed_at: string;
  user: { id: string; nickname: string };
  game: { id: string; starts_at: string; venue: string | null };
  reporters: string[];
}

/** 爽约申诉：维持（第 2、3 次从现在开始执行）或撤销（不再计入记录） */
export function StrikeAppeals() {
  const { data: queue, refresh } = useLive<AppealItem[]>('admin_strike_appeals', { every: 60_000 });
  const [busy, setBusy] = useState<string>();

  async function resolve(id: number, overturn: boolean) {
    setBusy(`${id}-${overturn}`);
    const { error } = await supabase!.rpc('admin_resolve_strike', { p_strike: id, p_overturn: overturn });
    setBusy(undefined);
    if (error) return toast(problem(error), 'error');
    toast(t('Done'));
    refresh();
  }

  return (
    <section aria-labelledby="appeals" className="grid gap-4">
      <h2 id="appeals" className="text-title2">{t('Missed game appeals')}</h2>
      {!queue ? <Skeleton className="h-24" /> : queue.length === 0 ? (
        <EmptyState title={t('No open appeals')} />
      ) : queue.map((item) => (
        <article key={item.id} className="sticker grid gap-3 p-5">
          <p>
            <Link to={`/players/${item.user.id}/`} className="link font-bold">{item.user.nickname}</Link>
            <span className="text-footnote text-ink-secondary"> · {t('Missed game {n} of 3', { n: item.level })} · {day(item.game.starts_at)}{item.game.venue && ` · ${item.game.venue}`}</span>
          </p>
          <p className="text-footnote text-ink-secondary">{t('Said they didn’t show up: {names}', { names: item.reporters.join(', ') })}</p>
          <p className="break-words rounded-[12px] bg-surface-muted p-3 text-footnote">{item.appeal}</p>
          <div className="flex flex-wrap gap-2">
            <Button className="button-sm" busy={busy === `${item.id}-true`} disabled={Boolean(busy)} onClick={() => resolve(item.id, true)}>{t('Remove it')}</Button>
            <Button className="button-sm" variant="quiet" busy={busy === `${item.id}-false`} disabled={Boolean(busy)} onClick={() => resolve(item.id, false)}>{t('Keep it')}</Button>
          </div>
        </article>
      ))}
    </section>
  );
}
