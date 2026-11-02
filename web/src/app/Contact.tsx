import { useState, type SubmitEvent } from 'react';
import { currentLocale, t } from './i18n';
import { Icon, type IconName } from './icons';
import { IconTile, LargeTitle } from './kit';
import { Link } from './router';
import { problem, supabase } from './supabase';
import { Button, Field, toast } from './ui';

export const SUPPORT_EMAIL = 'support@badie.rsvp';
/** Ko-fi 主页；没填之前网站上不显示打赏按钮（iPhone 上用 App 内购打赏） */
export const DONATE_URL = '';

/** 常见问题自己就能办，比等回信快 */
const shortcuts: { icon: IconName; title: string; text: string; to?: string; action?: string }[] = [
  { icon: 'shield', title: 'Someone made you feel unsafe', text: 'Open their profile and tap Report. Reports go straight to us, and you can block them there too.' },
  { icon: 'lock', title: 'Can’t sign in', text: 'On the sign-in page, tap “Forgot password?” and we’ll email you a code to set a new one.', to: '/signin/', action: 'Sign in' },
  { icon: 'trash', title: 'Delete your account', text: 'Go to Settings and tap Delete account. It removes your profile, games and messages.', to: '/settings/', action: 'Settings' },
  { icon: 'pin', title: 'Court details are wrong', text: 'Email us the link to the court’s page and what’s changed.' },
];

/** 联系我们：App Store 要求的支持页面，也是网站和 App 里“联系我们”打开的地方。登录了可以直接在这里写反馈 */
export function Contact({ signedIn }: { signedIn: boolean }) {
  async function copy() {
    try {
      await navigator.clipboard.writeText(SUPPORT_EMAIL);
      toast(t('Email address copied.'));
    } catch {
      toast(SUPPORT_EMAIL);
    }
  }

  return (
    <div className="mx-auto grid max-w-3xl gap-6">
      <LargeTitle title={t('Contact us')} subtitle={t('Questions, bugs, ideas or a court we’re missing')} />

      {signedIn && <FeedbackForm />}

      <section className="sticker grid gap-4 bg-lime p-5 text-on-accent">
        <div className="flex items-center gap-3">
          <IconTile icon="mail" tint="surface" size="lg" className="-rotate-6" />
          <div className="min-w-0">
            <h2 className="text-title3">{t('Email us')}</h2>
            <p className="text-subhead font-bold break-all">{SUPPORT_EMAIL}</p>
          </div>
        </div>
        <p className="text-subhead">{t('We read every email and usually reply within a few days. Write in any language.')}</p>
        <div className="flex flex-wrap gap-2">
          <a href={`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent('Badie')}`} className="button button-inverse">
            <Icon name="send" className="size-5" />{t('Write an email')}
          </a>
          <button type="button" onClick={copy} className="button button-quiet">
            <Icon name="copy" className="size-5" />{t('Copy address')}
          </button>
        </div>
      </section>

      <section className="grid gap-3">
        <h2 className="text-title3">{t('Faster ways to get help')}</h2>
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {shortcuts.map((s) => (
            <li key={s.title} className="sticker grid content-start gap-2 p-5">
              <Icon name={s.icon} className="size-7" />
              <h3 className="text-headline">{t(s.title)}</h3>
              <p className="text-subhead text-ink-secondary">{t(s.text)}</p>
              {s.to && s.action && <Link to={s.to} className="link justify-self-start text-subhead font-bold">{t(s.action)}</Link>}
            </li>
          ))}
        </ul>
      </section>

      <p className="flex justify-center gap-4 text-footnote font-bold">
        <Link to="/privacy/" className="link">{t('Privacy Policy')}</Link>
        <Link to="/terms/" className="link">{t('Terms of Service')}</Link>
      </p>
    </div>
  );
}

const feedbackKinds = [
  ['bug', 'Something’s wrong', 'Which screen, what you did, what you saw'],
  ['idea', 'Idea', 'What you’d like and when you’d use it'],
  ['court', 'Court info', 'The court’s name and what’s wrong, or a court we’re missing'],
  ['other', 'Other', 'Anything you’d like to tell us'],
] as const;

/** 版本、系统、语言：排查问题用，发送前显示出来 */
function feedbackContext() {
  const os = navigator.userAgent.match(/iPhone OS [\d_]+|Android [\d.]+|Mac OS X [\d_.]+|Windows NT [\d.]+|Linux/)?.[0]?.replace(/_/g, '.') ?? '';
  return { app: 'web', platform: 'web', os, locale: currentLocale() };
}

function FeedbackForm() {
  const [kind, setKind] = useState<(typeof feedbackKinds)[number][0]>('bug');
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const context = feedbackContext();
  const [, label, hint] = feedbackKinds.find(([k]) => k === kind)!;

  async function send(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const { error } = await supabase!.rpc('submit_feedback', { p_kind: kind, p_body: text.trim(), p_context: context });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    setText('');
    toast(t('Got it. Thank you.'));
  }

  return (
    <form onSubmit={send} noValidate className="sticker grid gap-4 p-5">
      <div className="grid gap-1">
        <h2 className="text-title3">{t('Help & feedback')}</h2>
        <p className="text-subhead text-ink-secondary">{t('We read every message. Replies show up in your notifications.')}</p>
      </div>
      <div role="radiogroup" aria-label={t('Help & feedback')} className="flex flex-wrap gap-2">
        {feedbackKinds.map(([value, title]) => (
          <button key={value} type="button" role="radio" aria-checked={kind === value} onClick={() => setKind(value)} className="toggle">
            {t(title)}
          </button>
        ))}
      </div>
      <Field label={t(label)} hint={t('Also sent: {info}', { info: ['Badie web', context.os, context.locale].filter(Boolean).join(' · ') })}>
        {(props) => <textarea {...props} rows={5} maxLength={2000} value={text} onChange={(e) => setText(e.target.value)} placeholder={t(hint)} className="field" />}
      </Field>
      <Button className="justify-self-start" busy={busy} disabled={text.trim().length < 5}>
        <Icon name="send" className="size-5" />{t('Send')}
      </Button>
    </form>
  );
}

/** 支持 Badie：网站用 Ko-fi；iPhone 上在 App 里打赏（苹果规定 App 里只能用内购） */
export function Support() {
  return (
    <div className="mx-auto grid max-w-2xl gap-6">
      <LargeTitle title={t('Support Badie')} subtitle={t('Badie is free, with no ads. If it helps you, you can buy us a drink.')} />
      {DONATE_URL && (
        <a href={DONATE_URL} target="_blank" rel="noopener" className="sticker lift flex items-center gap-4 bg-butter p-5 text-on-accent">
          <IconTile icon="heart" tint="surface" size="lg" className="-rotate-6" />
          <span className="min-w-0 flex-1">
            <span className="block text-title3">{t('Tip on Ko-fi')}</span>
            <span className="block text-subhead">{t('Card or PayPal, any amount.')}</span>
          </span>
          <Icon name="chevronRight" className="size-5 shrink-0" />
        </a>
      )}
      <p className="text-subhead text-ink-secondary">{t('On iPhone, open the Badie app and go to Me → Support Badie.')}</p>
    </div>
  );
}
