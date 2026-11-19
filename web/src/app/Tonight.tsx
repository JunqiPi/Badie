// 球员这边不加新页面，只借现有的位置：球群页的场次行（排场 / 看排场 / 付给… / 收款）和球局页最上面的“今晚”卡
import { useState } from 'react';
import { money, type MyTonight, type TonightSession } from './club';
import { t } from './i18n';
import { Icon } from './icons';
import { IconTile, Tag } from './kit';
import { PaySheet, payNote } from './Pay';
import { Link } from './router';
import { problem, supabase, useLive } from './supabase';
import { dayName, hours } from './time';
import { Button, toast } from './ui';

/** 场次行上的一个按钮：组织者 / 帮手“排场”，付钱的人“付给 Kevin · $12”，开始排场后“看排场”，结束后组织者“收款 · n 人没付” */
export function TonightAction({ tonight: s, group, tz, onChange }: { tonight: TonightSession; group: string; tz: string | null; onChange: () => void }) {
  const [paying, setPaying] = useState(false);
  if (s.can_run) {
    return <Link to={`/night/${s.id}/`} className="button button-lg w-full"><Icon name="court" className="size-5" />{t('Run courts')}</Link>;
  }
  if (s.pay) {
    const pay = s.pay;
    if (pay.paid) return <div><Tag icon="check" tint="mint">{t('Paid')}</Tag></div>;
    return (
      <>
        <Button variant="quiet" onClick={() => setPaying(true)}>
          <Icon name="coins" className="size-4" />
          {pay.amount === null ? t('Pay {name}', { name: pay.to }) : t('Pay {name} · {amount}', { name: pay.to, amount: money(pay.amount) })}
        </Button>
        <PaySheet open={paying} onClose={() => setPaying(false)} canUndo={pay.paid_self}
                  info={{ to: pay.to, amount: pay.amount, handles: pay.handles, paid: pay.paid, note: payNote(group, s.starts_at, tz),
                          when: `${group} · ${dayName(s.starts_at, tz)} ${hours(s.starts_at, s.ends_at, tz)}` }}
                  onPaid={async (paid) => {
                    const { error } = await supabase!.rpc('i_paid', { p_session: s.id, p_paid: paid });
                    if (error) return toast(problem(error), 'error');
                    if (paid) {
                      toast(t('Marked as paid.'));
                      setPaying(false);
                    }
                    onChange();
                  }} />
      </>
    );
  }
  if (s.board) return <Link to={`/live/${s.board}/`} className="button button-quiet"><Icon name="court" className="size-4" />{t('See courts')}</Link>;
  if (s.unpaid) {
    return <Link to={`/night/${s.id}/?tab=pay`} className="button button-quiet"><Icon name="coins" className="size-4" />{t('Payments · {n} unpaid', { n: s.unpaid })}</Link>;
  }
  return null;
}

/** 已经结束、不在“接下来的场次”里的当天场次（结束后 24 小时，组织者 7 天还要收款） */
export function PastTonight({ tonight, shown, group, tz, onChange }: {
  tonight: TonightSession[] | undefined;
  /** 球群页已经列出来的场次 */
  shown: string[];
  group: string;
  tz: string | null;
  onChange: () => void;
}) {
  const past = (tonight ?? []).filter((s) => !shown.includes(s.id) && (s.can_run || s.pay || s.board || s.unpaid));
  return past.map((s) => (
    <article key={s.id} className="sticker grid gap-3 p-4">
      <h3 className="text-headline">{dayName(s.starts_at, tz)} · {hours(s.starts_at, s.ends_at, tz)}</h3>
      <div className="flex flex-wrap gap-2"><TonightAction tonight={s} group={group} tz={tz} onChange={onChange} /></div>
    </article>
  ));
}

function tonightText(item: MyTonight) {
  if (item.status === 'court') return t('You’re on court {n}', { n: item.court ?? '' });
  if (item.status === 'next') return t('You’re up next');
  if (item.kind === 'night' && item.status === 'resting') return t('Resting · {n} game tonight|Resting · {n} games tonight', { n: item.games });
  if (item.kind === 'match' && item.round) return t('Your next game is in round {n}', { n: item.round });
  return t('Waiting · {n} game tonight|Waiting · {n} games tonight', { n: item.games });
}

/** 球局页最上面的“今晚”卡：今晚在排场里（到了）或者在打的比赛。没有就不显示 */
export function TonightCard() {
  const { data } = useLive<MyTonight[]>('my_tonight', { every: 30_000 });
  if (!data?.length) return null;
  return (
    <section aria-labelledby="tonight" className="grid gap-2">
      <h2 id="tonight" className="text-title3">{t('Tonight')}</h2>
      {data.map((item) => (
        <div key={item.kind === 'night' ? item.session_id : item.match_id} className="sticker flex flex-wrap items-center gap-3 p-4">
          <IconTile icon={item.kind === 'night' ? 'court' : 'trophy'} tint={item.status === 'court' || item.status === 'next' ? 'lime' : 'surface'} />
          <div className="min-w-0 flex-1">
            <p className="text-headline">{tonightText(item)}</p>
            <p className="truncate text-footnote font-bold text-ink-secondary">{item.name}</p>
          </div>
          <Link to={item.kind === 'night' ? `/live/${item.board_code}/` : `/matches/${item.match_id}/`} className="button button-sm button-quiet">
            {t('See all')}
          </Link>
        </div>
      ))}
    </section>
  );
}
