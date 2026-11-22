// 收款记录（/groups/<球群>/payments/），只有组织者：谁还欠着（按人合起来，一次标已付）、开过的每一场收齐了没有、导出成表格。
// 点进某一场（/groups/<球群>/payments/<场次>/）是当晚页同一个“收款”
import { useState } from 'react';
import { money, priceText, type Ledger, type LedgerSession, type NightState } from './club';
import { t } from './i18n';
import { Icon } from './icons';
import { Empty, IconButton, ScreenHeader, SectionTitle, Tag } from './kit';
import { Payments } from './Night';
import { Link } from './router';
import { problem, supabase, useLive } from './supabase';
import { dayName, hours } from './time';
import { Button, Skeleton, toast } from './ui';

export function LedgerPage({ id }: { id: string }) {
  const { data, failed, refresh } = useLive<Ledger>('group_ledger', { args: { p_group: id }, every: 60_000 });
  // 往前翻的几页
  const [earlier, setEarlier] = useState<LedgerSession[]>([]);
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState<string>();

  if (data === undefined) {
    if (failed) return <Empty icon="lock" tint="butter" title={t('Only organizers can do this.')} action={{ label: t('Back'), to: `/groups/${id}/` }} />;
    return <Skeleton className="mx-auto h-96 max-w-2xl" />;
  }
  const owed = data.owed ?? [];
  const total = owed.reduce((sum, p) => sum + p.amount, 0);
  const sessions = [...data.sessions, ...earlier];
  const more = !done && data.sessions.length === 20;

  async function loadEarlier() {
    setBusy('more');
    const { data: page, error } = await supabase!.rpc('group_ledger', { p_group: id, p_before: sessions.at(-1)!.starts_at });
    setBusy(undefined);
    if (error) return toast(problem(error), 'error');
    setEarlier([...earlier, ...(page as Ledger).sessions]);
    if ((page as Ledger).sessions.length < 20) setDone(true);
  }

  async function markPaid(signups: string[], key: string) {
    setBusy(key);
    const { error } = await supabase!.rpc('mark_signups_paid', { p_signups: signups, p_paid: true });
    setBusy(undefined);
    if (error) return toast(problem(error), 'error');
    toast(t('Marked as paid.'));
    refresh();
  }

  async function exportRows() {
    setBusy('export');
    const { data: rows, error } = await supabase!.rpc('group_ledger_rows', { p_group: id });
    setBusy(undefined);
    if (error) return toast(problem(error), 'error');
    download(rows as LedgerRow[]);
  }

  return (
    <div className="mx-auto grid w-full max-w-2xl gap-6">
      <ScreenHeader title={t('Payments')} back={`/groups/${id}/`}>
        {sessions.length > 0 && <IconButton icon="share" label={t('Export')} onClick={exportRows} />}
      </ScreenHeader>

      {sessions.length === 0 ? (
        <Empty icon="coins" tint="mint" title={t('No past sessions yet.')}>{t('Each session shows up here once it starts.')}</Empty>
      ) : (
        <>
          <section aria-labelledby="owed" className="grid gap-2">
            <SectionTitle id="owed" title={t('Still owed')} detail={total > 0 ? money(total) : undefined} />
            {owed.length === 0 ? (
              <p className="sticker flex items-center gap-2 p-4 font-bold"><Icon name="checkCircle" className="size-5" />{t('Everyone has paid.')}</p>
            ) : (
              <ul className="sticker grid divide-y-[1.5px] divide-divider px-4">
                {owed.map((p) => {
                  const key = p.id ?? `guest:${p.name}`;
                  return (
                    <li key={key} className="flex min-h-16 items-center gap-3 py-2">
                      <div className="min-w-0 flex-1">
                        <p className="flex flex-wrap items-center gap-1.5">
                          {p.id ? <Link to={`/players/${p.id}/`} className="font-bold hover:underline">{p.name}</Link> : <span className="font-bold">{p.name}</span>}
                          {p.guest && <Tag tint="mint">{t('Guest')}</Tag>}
                        </p>
                        <p className="text-footnote font-bold text-ink-secondary tabular-nums">
                          {t('{n} session|{n} sessions', { n: p.sessions })} · {money(p.amount)}
                        </p>
                      </div>
                      <Button variant="quiet" className="button-sm" busy={busy === key} disabled={Boolean(busy)} onClick={() => markPaid(p.signups, key)}>
                        {t('Mark paid')}
                      </Button>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>

          <section aria-labelledby="past" className="grid gap-2">
            <SectionTitle id="past" title={t('Past sessions')} />
            <ul className="grid gap-2">
              {sessions.map((s) => {
                const amount = priceText(s.amount);
                const all = s.owes > 0 && s.paid >= s.owes;
                return (
                  <li key={s.id}>
                    <Link to={`/groups/${id}/payments/${s.id}/`} className="sticker lift flex items-center gap-3 p-4">
                      <div className="min-w-0 flex-1">
                        <p className="font-black">{dayName(s.starts_at, s.tz)} · {hours(s.starts_at, s.ends_at, s.tz)}</p>
                        <p className="truncate text-footnote font-bold text-ink-secondary">
                          {[amount ?? t('No amount set'), s.venue].join(' · ')}
                        </p>
                      </div>
                      {s.owes > 0 && (
                        <Tag icon={all ? 'check' : undefined} tint={all ? 'mint' : 'butter'}>{t('Paid {n}/{total}', { n: s.paid, total: s.owes })}</Tag>
                      )}
                      <Icon name="chevronRight" className="size-4 shrink-0" />
                    </Link>
                  </li>
                );
              })}
            </ul>
            {more && <Button variant="quiet" busy={busy === 'more'} onClick={loadEarlier}>{t('Show earlier sessions')}</Button>}
          </section>
        </>
      )}
    </div>
  );
}

/** 收款记录里的某一场：和当晚页的“收款”一样（改金额、点已付、不用付、提醒） */
export function LedgerSessionPage({ group, id }: { group: string; id: string }) {
  const { data: n } = useLive<NightState | null>('night_state', { args: { p_session: id }, every: 600_000 });
  if (n === undefined) return <Skeleton className="mx-auto h-96 max-w-2xl" />;
  if (n === null || n.role !== 'organizer') {
    return <Empty icon="lock" tint="butter" title={t('Only organizers can do this.')} action={{ label: t('Back'), to: `/groups/${group}/` }} />;
  }
  return (
    <div className="mx-auto grid w-full max-w-2xl gap-4 pb-24">
      <div className="grid gap-1">
        <ScreenHeader title={`${dayName(n.starts_at, n.tz)} · ${hours(n.starts_at, n.ends_at, n.tz)}`} back={`/groups/${group}/payments/`} />
        <p className="text-center text-footnote font-bold text-ink-secondary lg:text-left">{n.group} · {n.venue}</p>
      </div>
      <Payments n={n} />
    </div>
  );
}

// MARK: 导出

interface LedgerRow {
  starts_at: string;
  tz: string | null;
  venue: string;
  name: string;
  guest: boolean;
  amount: number | null;
  owes: boolean;
  paid_at: string | null;
  paid_self: boolean;
}

/** 球馆当地的日期和时间，表格里好排序：2026-11-18、19:00 */
const local = (iso: string, tz: string | null) => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz ?? undefined, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(iso));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '';
  return { date: `${get('year')}-${get('month')}-${get('day')}`, time: `${get('hour')}:${get('minute')}` };
};

const cell = (value: string | number) => {
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
};

function download(rows: LedgerRow[]) {
  const head = [t('Date'), t('Time'), t('Court'), t('Name'), t('Guest'), t('Amount'), t('Paid'), t('Marked by them')];
  const lines = rows.map((r) => {
    const at = local(r.starts_at, r.tz);
    const paid = r.paid_at ? local(r.paid_at, r.tz).date : r.owes ? '' : t('Doesn’t need to pay');
    return [at.date, at.time, r.venue, r.name, r.guest ? t('Guest') : '', r.amount ?? '', paid, r.paid_self ? t('Marked by them') : ''];
  });
  // 带 BOM，Excel 打开中文不乱码
  const csv = '﻿' + [head, ...lines].map((line) => line.map(cell).join(',')).join('\r\n');
  const link = document.createElement('a');
  link.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  link.download = `badie-payments-${local(new Date().toISOString(), null).date}.csv`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 10_000);
}
