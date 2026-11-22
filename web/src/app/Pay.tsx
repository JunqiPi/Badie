// 收款：付钱的人看到的付款半屏（球群页、访客报名页）、访客的付款页（/pay/<凭证>/，提醒邮件里的链接）、
// “我的 → 收款方式”。钱不经过 Badie，这里只给链接
import { useEffect, useState, type SubmitEvent } from 'react';
import { copyText, deviceTokens, money, type Due, type GuestPayment, type Handles } from './club';
import { t } from './i18n';
import { Icon } from './icons';
import { Empty, Group, Tag } from './kit';
import { Sheet } from './Nearby';
import { problem, supabase, useLive } from './supabase';
import { day, hours } from './time';
import { Button, Field, Skeleton, toast } from './ui';

/** 转账备注：“Badie · LABC · Wed, Nov 18” */
export const payNote = (group: string, startsAt: string, tz: string | null) => `Badie · ${group} · ${day(startsAt, tz)}`;

/** Venmo / Cash App / PayPal 的链接，金额和备注预先填好（没填金额就只打开收款人） */
function payLinks(handles: Handles, amount: number | null, note: string) {
  const sum = amount === null ? '' : String(amount);
  return [
    handles.venmo && { name: 'Venmo', handle: `@${handles.venmo}`,
      href: `https://venmo.com/${handles.venmo}?txn=pay${sum && `&amount=${sum}`}&note=${encodeURIComponent(note)}` },
    handles.cashapp && { name: 'Cash App', handle: `$${handles.cashapp}`, href: `https://cash.app/$${handles.cashapp}${sum && `/${sum}`}` },
    handles.paypal && { name: 'PayPal', handle: `paypal.me/${handles.paypal}`, href: `https://paypal.me/${handles.paypal}${sum && `/${sum}USD`}` },
  ].filter((x): x is { name: string; handle: string; href: string } => Boolean(x));
}

type PayInfo = { to: string; amount: number | null; handles: Handles; note: string; when: string; paid: boolean };

/** 付款的内容：付给谁、多少钱、各个 App 的按钮、Zelle 复制、“我付了” */
function PayPanel({ info, titleId, busy, onPaid, canUndo }: { info: PayInfo; titleId: string; busy: boolean; onPaid: (paid: boolean) => void; canUndo: boolean }) {
  const links = payLinks(info.handles, info.amount, info.note);
  const row = 'sticker flex min-h-14 items-center gap-3 px-4 py-2';
  return (
    <>
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <h2 id={titleId} className="text-title3">{t('Pay {name}', { name: info.to })}</h2>
          <p className="text-footnote font-bold text-ink-secondary">{info.when}</p>
        </div>
        {info.amount !== null && <span className="text-[2rem] leading-none font-black tabular-nums">{money(info.amount)}</span>}
      </div>
      {(links.length > 0 || info.handles.zelle) ? (
        <ul className="grid gap-2.5">
          {links.map((l) => (
            <li key={l.name}>
              <a href={l.href} target="_blank" rel="noreferrer" className={`${row} lift`}>
                <span className="flex-1 font-black">{l.name}</span>
                <span className="truncate text-footnote font-bold text-ink-secondary">{l.handle}</span>
                <Icon name="arrowRight" className="size-4" />
              </a>
            </li>
          ))}
          {info.handles.zelle && (
            <li className={row}>
              <span className="min-w-0 flex-1">
                <span className="block font-black">Zelle</span>
                <span className="block truncate text-footnote font-bold text-ink-secondary">{info.handles.zelle}</span>
              </span>
              <Button variant="quiet" className="button-sm" onClick={() => copyText(info.handles.zelle!, t('Copied'))}>
                <Icon name="copy" className="size-4" />{t('Copy')}
              </Button>
            </li>
          )}
        </ul>
      ) : (
        <p className="text-subhead text-ink-secondary">{t('{name} hasn’t added a way to pay yet. Pay them in person.', { name: info.to })}</p>
      )}
      <p className="text-footnote text-ink-secondary">{t('Note: {note}', { note: info.note })}</p>
      {info.paid ? (
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Tag icon="check" tint="mint">{t('Paid')}</Tag>
          {canUndo && <button type="button" className="link text-footnote" disabled={busy} onClick={() => onPaid(false)}>{t('I haven’t paid yet')}</button>}
        </div>
      ) : (
        <Button className="button-lg" busy={busy} onClick={() => onPaid(true)}>{t('I paid')}</Button>
      )}
    </>
  );
}

/** 球群页上付钱的人点“付给 Kevin · $12”打开的半屏 */
export function PaySheet({ open, onClose, info, canUndo, onPaid }: {
  open: boolean;
  onClose: () => void;
  info: PayInfo;
  canUndo: boolean;
  onPaid: (paid: boolean) => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  return (
    <Sheet open={open} onClose={onClose} labelledBy="pay-title">
      <PayPanel info={info} titleId="pay-title" busy={busy} canUndo={canUndo} onPaid={async (paid) => {
        setBusy(true);
        await onPaid(paid);
        setBusy(false);
      }} />
    </Sheet>
  );
}

const guestInfo = (p: GuestPayment): PayInfo => ({
  to: p.to, amount: p.amount, handles: p.handles, paid: p.paid,
  note: payNote(p.group, p.starts_at, p.tz), when: `${p.group} · ${day(p.starts_at, p.tz)} ${hours(p.starts_at, p.ends_at, p.tz)} · ${p.venue}`,
});

async function guestPaid(token: string, paid: boolean) {
  const { error } = await supabase!.rpc('guest_i_paid', { p_token: token, p_paid: paid });
  if (error) toast(problem(error), 'error');
  else if (paid) toast(t('Marked as paid.'));
}

/** 我还没付的：按球群和收钱的人合起来，一张卡一个按钮，一次付清。group 给了就只看这个球群（球群页），不给就是所有球群（球局页） */
export function DuesCard({ group, onPaid }: { group?: string; onPaid?: () => void }) {
  const { data, refresh } = useLive<Due[]>('my_dues', { args: group ? { p_group: group } : {}, every: 120_000 });
  const [open, setOpen] = useState<string>();
  const piles = new Map<string, Due[]>();
  for (const due of data ?? []) {
    const key = `${due.group_id}:${due.to_id}`;
    piles.set(key, [...(piles.get(key) ?? []), due]);
  }
  if (!piles.size) return null;
  return [...piles].map(([key, dues]) => {
    const first = dues[0];
    const total = dues.reduce((sum, d) => sum + d.amount, 0);
    const dates = dues.map((d) => day(d.starts_at, d.tz)).join(', ');
    return (
      <section key={key} aria-label={t('You haven’t paid yet')} className="sticker grid gap-3 bg-butter p-4 text-on-accent">
        <div className="flex items-start gap-3">
          <div className="min-w-0 flex-1">
            <p className="text-headline">{t('You haven’t paid yet')}</p>
            <p className="text-footnote font-bold">{group ? dates : `${first.group} · ${dates}`}</p>
          </div>
          <span className="text-title2 font-black tabular-nums">{money(total)}</span>
        </div>
        <Button className="button-lg" onClick={() => setOpen(key)}>
          <Icon name="coins" className="size-5" />{t('Pay {name} · {amount}', { name: first.to, amount: money(total) })}
        </Button>
        <PaySheet open={open === key} onClose={() => setOpen(undefined)} canUndo={false}
                  info={{ to: first.to, amount: total, handles: first.handles, paid: false,
                          note: `Badie · ${first.group} · ${dates}`, when: `${first.group} · ${dates}` }}
                  onPaid={async (paid) => {
                    if (!paid) return;
                    for (const d of dues) {
                      const { error } = await supabase!.rpc('i_paid', { p_session: d.session_id, p_paid: true });
                      if (error) return toast(problem(error), 'error');
                    }
                    toast(t('Marked as paid.'));
                    setOpen(undefined);
                    await refresh();
                    onPaid?.();
                  }} />
      </section>
    );
  });
}

/** 访客报名页最上面：这台设备上报过名、要付钱的场次（开场后到结束后 24 小时）。group 是球群 id */
export function GuestPayCard({ group }: { group: string }) {
  const { data, refresh } = useLive<GuestPayment[]>('guest_payment', { args: { p_tokens: deviceTokens() }, every: 60_000 });
  const [open, setOpen] = useState<string>();
  const mine = (data ?? []).filter((p) => p.group_id === group);
  if (!mine.length) return null;
  return (
    <>
      {mine.map((p) => (
        <section key={p.token} className="sticker flex flex-wrap items-center gap-3 p-4">
          <div className="min-w-0 flex-1">
            <p className="font-black">{day(p.starts_at, p.tz)} · {hours(p.starts_at, p.ends_at, p.tz)}</p>
            <p className="text-footnote font-bold text-ink-secondary">{p.venue}</p>
          </div>
          {p.paid ? <Tag icon="check" tint="mint">{t('Paid')}</Tag> : (
            <Button className="button-sm" onClick={() => setOpen(p.token)}>
              {p.amount === null ? t('Pay {name}', { name: p.to }) : t('Pay {name} · {amount}', { name: p.to, amount: money(p.amount) })}
            </Button>
          )}
          <PaySheet open={open === p.token} onClose={() => setOpen(undefined)} info={guestInfo(p)} canUndo={p.paid_self} onPaid={async (paid) => {
            await guestPaid(p.token, paid);
            await refresh();
            if (paid) setOpen(undefined);
          }} />
        </section>
      ))}
    </>
  );
}

/** 提醒邮件里的付款链接：badie.rsvp/pay/<凭证>/，不用登录 */
export function GuestPayPage({ token }: { token: string }) {
  const { data, refresh } = useLive<GuestPayment[]>('guest_payment', { args: { p_tokens: [token] }, every: 60_000 });
  const [busy, setBusy] = useState(false);
  if (data === undefined) return <Skeleton className="mx-auto h-96 max-w-md" />;
  const p = data[0];
  if (!p) {
    return (
      <Empty icon="coins" tint="mint" title={t('Nothing to pay here')} action={{ label: t('Home'), to: '/' }}>
        {t('This link is more than 7 days old, or the organizer marked you as not needing to pay.')}
      </Empty>
    );
  }
  return (
    <section className="sticker mx-auto grid w-full max-w-md gap-4 p-5">
      <PayPanel info={guestInfo(p)} titleId="pay-page-title" busy={busy} canUndo={p.paid_self} onPaid={async (paid) => {
        setBusy(true);
        await guestPaid(token, paid);
        await refresh();
        setBusy(false);
      }} />
    </section>
  );
}

const handleFields = () => [
  ['venmo', t('Venmo username'), '@username'],
  ['cashapp', t('Cash App $cashtag'), '$cashtag'],
  ['paypal', t('PayPal.me username'), 'paypal.me/username'],
  ['zelle', t('Zelle email or phone number'), 'name@example.com'],
] as const;

/** 我的 → 收款方式（设置页里的一组）。都可以不填 */
export function PaymentHandles() {
  const { data } = useLive<Handles>('my_payment_handles', { every: 600_000 });
  const [draft, setDraft] = useState<Handles>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ field: string; text: string }>();
  const values = draft ?? data ?? {};

  // 从“填收款方式”过来的（/settings/#payment）：滚到这一组
  useEffect(() => {
    if (data && location.hash === '#payment') document.getElementById('payment')?.scrollIntoView();
  }, [Boolean(data)]);

  async function save(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const { error: failed } = await supabase!.rpc('set_payment_handles', {
      p_venmo: values.venmo ?? '', p_cashapp: values.cashapp ?? '', p_paypal: values.paypal ?? '', p_zelle: values.zelle ?? '',
    });
    setBusy(false);
    if (failed) {
      const field = failed.message.match(/^invalid_(venmo|cashapp|paypal|zelle)$/)?.[1];
      if (field) return setError({ field, text: problem(failed) });
      return toast(problem(failed), 'error');
    }
    setError(undefined);
    toast(t('Saved'));
  }

  return (
    <Group title={t('Payment methods')} id="payment">
      <form onSubmit={save} className="grid gap-4 py-4">
        <p className="text-footnote text-ink-secondary">{t('Players in your group sessions see these when they pay you. Zelle is never shown on public pages.')}</p>
        {handleFields().map(([key, label, placeholder]) => (
          <Field key={key} label={label} error={error?.field === key ? error.text : undefined}>
            {(props) => (
              <input {...props} className="field" value={values[key] ?? ''} placeholder={placeholder} autoComplete="off" autoCapitalize="none" spellCheck={false}
                     disabled={data === undefined} onChange={(e) => setDraft({ ...values, [key]: e.target.value })} />
            )}
          </Field>
        ))}
        <Button type="submit" variant="quiet" busy={busy} disabled={data === undefined}>{t('Save')}</Button>
      </form>
    </Group>
  );
}
