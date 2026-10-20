import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { IconTile, LargeTitle } from './kit';
import { Link } from './router';
import { toast } from './ui';

export const SUPPORT_EMAIL = 'support@badie.rsvp';

/** 常见问题自己就能办，比等回信快 */
const shortcuts: { icon: IconName; title: string; text: string; to?: string; action?: string }[] = [
  { icon: 'shield', title: 'Someone made you feel unsafe', text: 'Open their profile and tap Report. Reports go straight to us, and you can block them there too.' },
  { icon: 'lock', title: 'Can’t sign in', text: 'On the sign-in page, tap “Forgot password?” and we’ll email you a code to set a new one.', to: '/signin/', action: 'Sign in' },
  { icon: 'trash', title: 'Delete your account', text: 'Go to Settings and tap Delete account. It removes your profile, games and messages.', to: '/settings/', action: 'Settings' },
  { icon: 'pin', title: 'Court details are wrong', text: 'Email us the link to the court’s page and what’s changed.' },
];

/** 联系我们：App Store 要求的支持页面，也是网站和 App 里“联系我们”打开的地方 */
export function Contact() {
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
