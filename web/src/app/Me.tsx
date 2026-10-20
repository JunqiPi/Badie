import { useEffect, useState, type ReactNode, type SubmitEvent } from 'react';
import { gapText, tier } from './assessment';
import { SUPPORT_EMAIL } from './Contact';
import { currentLocale, t } from './i18n';
import { Icon } from './icons';
import { Avatar, Divider, IconButton, LargeTitle, LevelBadge, Notice, Row, ScreenHeader, StatTile, Tag } from './kit';
import { nicknameProblem } from './Onboarding';
import { passwordProblem } from './password';
import { disablePush, enablePush, pushState, type PushState } from './push';
import { Link } from './router';
import { problem, supabase, useLive, type Friend, type PlayerCard, type PlayRecord, type Profile } from './supabase';
import { Button, Field, PasswordInput, toast } from './ui';
import { AdminLink } from './Verification';

const verifiedText = { tournament: 'Tournament verified', national: 'Ranking verified', bwf: 'BWF verified' } as const;

/** 我的（iOS 的 ProfileView）：身份卡、场次和履约、本月胜率、菜单 */
export function Me({ profile }: { profile: Profile; onChange: (p: Profile) => void }) {
  const { data: card } = useLive<PlayerCard | null>('player_card', { args: { p_user: profile.id }, every: 300_000 });
  const { data: record } = useLive<PlayRecord>('my_record', { every: 300_000 });
  const { data: friends } = useLive<{ friends: Friend[]; requests: Friend[] }>('my_friends', { every: 120_000 });
  const total = record ? record.games_played + record.no_shows + record.late_cancels : 0;
  const reliability = record && total ? Math.round((record.games_played / total) * 100) : 100;

  return (
    <div className="grid gap-6">
      <LargeTitle title={t('Me')}>
        <IconButton icon="gear" label={t('Settings')} to="/settings/" />
      </LargeTitle>

      {!profile.assessed_at && (
        <Notice icon="list" action={{ label: t('Take the quiz'), to: '/level-quiz/' }}>
          {t('You haven’t taken the level quiz yet, so you’re matched as level 3.')}
        </Notice>
      )}

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start lg:gap-8">
        <div className="grid min-w-0 gap-6">
          <section aria-label={t('My profile')} className="sticker grid gap-4 bg-lavender p-5 text-on-accent sm:p-6">
            {/* 很窄的屏幕上名字和标签换到头像下面 */}
            <div className="flex flex-wrap items-center gap-4">
              <span className="relative shrink-0">
                <span aria-hidden="true" className="absolute inset-0 translate-x-[3px] translate-y-1 rounded-full bg-[#17140f]" />
                <Avatar id={profile.id} name={profile.nickname} photo={profile.avatar_path} size={76} className="relative" />
              </span>
              <div className="grid min-w-0 flex-1 basis-40 gap-1.5">
                <h2 className="truncate text-title2">{profile.nickname}</h2>
                <ul className="flex flex-wrap gap-1.5">
                  <li><LevelBadge rating={profile.rating} /></li>
                  {card?.reliable && <li><Tag icon="reliable" tint="mint">{t('Reliable')}</Tag></li>}
                  {card?.new_player && <li><Tag icon="sparkle" tint="butter">{t('New player · calibrating')}</Tag></li>}
                  {profile.verified_kind && <li><Tag icon="verified" tint="lime">{t(verifiedText[profile.verified_kind])}</Tag></li>}
                </ul>
              </div>
            </div>
            <p className="text-subhead">{profile.assessed_at ? tier(profile.rating).summary : t('Take the 2-minute level quiz so you’re matched with the right players.')}</p>
            <Link to="/settings/" className="button bg-white! text-[#17140f]!">{t('Edit Profile')}</Link>
          </section>

          <div className="grid grid-cols-3 gap-2.5">
            <StatTile stacked icon="games" tint="peach" value={record?.games_played ?? '–'} label={t('Games')} />
            <StatTile stacked icon="reliable" tint="mint" value={record ? `${reliability}%` : '–'} label={t('Reliability')} />
            <StatTile stacked icon="users" tint="sky" value={friends?.friends.length ?? '–'} label={t('Friends')} />
          </div>

          {record && <WinRate record={record} />}
          {record && <Attendance record={record} />}
        </div>

        <aside className="grid min-w-0 gap-6" aria-label={t('More')}>
          <nav aria-label={t('Me')} className="sticker grid px-4 py-1">
            <Row icon="users" tint="lavender" title={t('My friends')} value={friends?.friends.length} badge={friends?.requests.length} to="/messages/?tab=friends" />
            <Divider />
            <Row icon="list" tint="lime" title={t('Level guide')} value={`Lv.${tier(profile.rating).label}`} to="/levels/" />
            <Divider />
            <Row icon="history" tint="peach" title={t('Past games')} to="/games/?tab=ended" />
            <Divider />
            <Row icon="trophy" tint="butter" title={t('Leaderboard')} to="/rankings/" />
            <Divider />
            <Row icon="challenge" tint="pink" title={t('Challenges')} to="/challenges/" />
            <Divider />
            <Row icon="heart" tint="pink" title={t('Venues & favorites')} to="/courts/" />
            <Divider />
            <Row icon="verified" tint="mint" title={t('Level verification')} value={profile.verified_kind ? t('Verified') : undefined} to="/verification/" />
            <Divider />
            <Row icon="gear" tint="muted" title={t('Settings')} to="/settings/" />
          </nav>
          <AdminLink />
        </aside>
      </div>
    </div>
  );
}

/** 本月胜率：满 5 场显示百分比，不够就显示进度 */
function WinRate({ record }: { record: PlayRecord }) {
  const minimum = 5;
  return (
    <section aria-labelledby="win-rate" className="sticker grid gap-3 p-5">
      <h2 id="win-rate" className="text-headline">{t('Win rate this month')}</h2>
      {record.games >= minimum ? (
        <p className="flex items-baseline gap-2">
          <span className="text-[2.75rem] leading-none font-black tabular-nums">{Math.round((record.wins / record.games) * 100)}%</span>
          <span className="text-footnote font-bold text-ink-secondary">{t('{wins}W {losses}L', { wins: record.wins, losses: record.losses })}</span>
        </p>
      ) : (
        <>
          <p className="text-subhead font-bold">{t('{n} confirmed this month. Win rate shows from {minimum} games.', { n: record.games, minimum })}</p>
          <Progress value={record.games / minimum} />
        </>
      )}
      {record.games > 0 && (
        <p className="text-footnote font-bold text-ink-secondary">
          {t('{n} confirmed game|{n} confirmed games', { n: record.games })} · {t('{n} opponent|{n} opponents', { n: record.opponents })} · {gapText(record.gap)}
        </p>
      )}
      <p className="flex gap-1.5 text-caption text-ink-tertiary">
        <Icon name="info" className="mt-px size-3.5" />
        {t('Only games confirmed by both sides count. Resets on the 1st of each month; up to 3 games per opponent per month.')}
      </p>
    </section>
  );
}

/** 履约记录：完成、爽约、临时取消 */
function Attendance({ record }: { record: PlayRecord }) {
  const good = record.no_shows === 0 && record.late_cancels <= 1;
  return (
    <section className="sticker flex items-start gap-3 p-5">
      <span className={`grid size-11 shrink-0 place-items-center rounded-[13px] border-2 border-stroke text-on-accent ${good ? 'bg-mint' : 'bg-pink'}`}>
        <Icon name={good ? 'reliable' : 'shield'} className="size-5" />
      </span>
      <div className="min-w-0">
        <h2 className="text-headline">{good ? t('Attendance · Good') : t('Attendance · Needs care')}</h2>
        <p className="text-footnote font-bold text-ink-secondary">
          {t('{played} played · {noShows} no-shows · {late} late cancellations', { played: record.games_played, noShows: record.no_shows, late: record.late_cancels })}
        </p>
        <p className="text-caption text-ink-secondary">{t('Leaving within 2 hours of start counts as a late cancellation.')}</p>
      </div>
    </section>
  );
}

const Progress = ({ value }: { value: number }) => (
  <span className="block h-3 overflow-hidden rounded-full border-2 border-stroke bg-surface-muted" role="progressbar" aria-valuenow={Math.round(value * 100)} aria-valuemin={0} aria-valuemax={100}>
    <span className="block h-full bg-lime" style={{ width: `${Math.min(100, value * 100)}%` }} />
  </span>
);

// MARK: 设置

const policies = [
  ['similar', 'Players within 1 level'],
  ['everyone', 'Anyone in my country'],
  ['friends', 'Friends only'],
  ['nobody', 'No one'],
] as const;

type Toggles = Pick<Profile, 'discoverable' | 'show_as_regular' | 'allow_message_requests' | 'show_on_boards' | 'challenge_policy' | 'email_alerts'>;

/** 设置（iOS 的 SettingsView）：资料、隐私、约战、等级、账号 */
export function Settings({ profile, email, onChange }: { profile: Profile; email?: string; onChange: (p: Profile) => void }) {
  async function save(patch: Partial<Toggles>) {
    onChange({ ...profile, ...patch });
    const { data, error } = await supabase!.from('profiles').update(patch).eq('id', profile.id).select().single();
    if (error) {
      onChange(profile);
      return toast(t('Couldn’t save. Try again.'), 'error');
    }
    onChange(data as Profile);
    toast(t('Saved'));
  }

  return (
    <div className="mx-auto grid max-w-2xl gap-6">
      <ScreenHeader title={t('Settings')} back="/me/" />
      <Nickname profile={profile} email={email} onChange={onChange} />

      <Group title={t('Notifications')}>
        <PushSettings />
        <Switch checked={profile.email_alerts} onChange={(v) => save({ email_alerts: v })} title={t('Email me about matches')}
                text={t('Match offers, confirmations and cancellations also go to {email}.', { email: email ?? t('your email') })} />
      </Group>

      <Group title={t('Who can find me')}>
        <Switch checked={profile.discoverable} onChange={(v) => save({ discoverable: v })} title={t('Let players find me by nickname')}
                text={t('They see your nickname and level, and can send a friend request.')} />
        <Divider />
        <Switch checked={profile.show_as_regular} onChange={(v) => save({ show_as_regular: v })} title={t('Show me as a regular at my courts')}
                text={t('Players who starred the same court see your nickname, level and the court. Never when you play or where you are.')} />
        <Divider />
        <Switch checked={profile.allow_message_requests} onChange={(v) => save({ allow_message_requests: v })} title={t('Allow message requests from my groups')}
                text={t('When off, only friends can message you. Game and group chats still work.')} />
        <Divider />
        <Switch checked={profile.show_on_boards} onChange={(v) => save({ show_on_boards: v })} title={t('Show me on leaderboards')}
                text={t('Weekly and court boards show your nickname, level and games.')} />
      </Group>

      <Group title={t('Who can challenge me')}>
        <div role="radiogroup" aria-label={t('Who can challenge me')} className="flex flex-wrap gap-2 py-3">
          {policies.map(([value, label]) => (
            <button key={value} type="button" role="radio" aria-checked={profile.challenge_policy === value} onClick={() => save({ challenge_policy: value })} className="toggle">
              {t(label)}
            </button>
          ))}
        </div>
      </Group>

      <Level profile={profile} />
      <Group title={t('Level verification')}>
        <Row icon="verified" tint="mint" title={t('Verify a high level')} subtitle={t('Tournament results, a national ranking or a BWF profile.')} to="/verification/" />
      </Group>

      <PasswordSettings email={email} />

      <Group title={t('Help')}>
        <Row icon="mail" tint="sky" title={t('Contact us')} subtitle={SUPPORT_EMAIL} to="/contact/" />
      </Group>

      <Group title={t('Account')}>
        <Row icon="signOut" tint="muted" title={t('Sign out')} onClick={() => disablePush().catch(() => {}).finally(() => supabase!.auth.signOut())} />
        <Divider />
        <DeleteAccount avatar={profile.avatar_path} />
      </Group>

      <p className="flex justify-center gap-4 text-footnote font-bold">
        <Link to="/privacy/" className="link">{t('Privacy Policy')}</Link>
        <Link to="/terms/" className="link">{t('Terms of Service')}</Link>
      </p>
    </div>
  );
}

function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="grid gap-2">
      <h2 className="px-1 text-footnote font-bold text-ink-secondary">{title}</h2>
      <div className="sticker grid px-4">{children}</div>
    </section>
  );
}

/** 设置或修改密码：用验证码、Google、Apple 登录过的人也可以加一个，之后用邮箱 + 密码登录 */
function PasswordSettings({ email }: { email?: string }) {
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    setBusy(true);
    setError(undefined);
    const problem = await passwordProblem(password);
    const { error } = problem ? { error: undefined } : await supabase!.auth.updateUser({ password });
    setBusy(false);
    if (problem) return setError(problem);
    if (error) return setError(error.code === 'same_password' ? t('That’s already your password. Choose a new one.') : t('Couldn’t save. Try again.'));
    setPassword('');
    toast(t('Password saved'));
  }

  return (
    <Group title={t('Password')}>
      <form onSubmit={save} className="grid gap-3 py-3.5">
        {/* 让钥匙串 / 密码管理器把新密码存到这个邮箱名下 */}
        {email && <input type="email" autoComplete="username" value={email} readOnly hidden />}
        <Field label={t('New password')} hint={t('Sign in with your email and this password. At least 8 characters.')} error={error}>
          {(props) => <PasswordInput {...props} autoComplete="new-password" value={password} onChange={setPassword} />}
        </Field>
        <Button busy={busy} className="justify-self-start">{t('Save password')}</Button>
      </form>
    </Group>
  );
}

/** 这台设备的推送：浏览器不支持就不显示；iPhone 要先添加到主屏幕；被拒过就告诉在哪里改 */
function PushSettings() {
  const [state, setState] = useState<PushState>();
  const [busy, setBusy] = useState(false);
  useEffect(() => void pushState().then(setState), []);

  async function toggle(on: boolean) {
    setBusy(true);
    try {
      if (on) setState(await enablePush());
      else await disablePush().then(() => setState('off'));
    } catch {
      toast(t('Couldn’t change notifications. Try again.'), 'error');
    }
    setBusy(false);
  }

  if (!state || state === 'unsupported') return null;
  return (
    <>
      {state === 'install' ? (
        <p className="py-3.5 text-footnote text-ink-secondary">{t('On iPhone, add Badie to your Home Screen first (Share → Add to Home Screen), then turn on notifications there.')}</p>
      ) : (
        <Switch checked={state === 'on'} disabled={busy || state === 'blocked'} onChange={toggle} title={t('Notifications on this device')}
                text={state === 'blocked' ? t('Notifications are blocked for this site. Allow them in your browser’s site settings.')
                  : t('Get a notification when you’re matched or a game changes.')} />
      )}
      <Divider />
    </>
  );
}

/** 开关（role=switch）：柠檬绿是开 */
function Switch({ checked, onChange, title, text, disabled }: { checked: boolean; onChange: (value: boolean) => void; title: string; text: string; disabled?: boolean }) {
  return (
    <label className="flex cursor-pointer items-start gap-3 py-3.5 has-disabled:cursor-not-allowed">
      <span className="min-w-0 flex-1">
        <span className="block font-bold">{title}</span>
        {/* 说明里可能有邮箱地址：太长时在任意处换行 */}
        <span className="block text-footnote text-ink-secondary wrap-anywhere">{text}</span>
      </span>
      <input type="checkbox" role="switch" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)}
             className="relative mt-0.5 disabled:opacity-50 h-7 w-12 shrink-0 cursor-pointer appearance-none rounded-full border-2 border-stroke bg-surface-muted transition-colors duration-[var(--dur-1)] before:absolute before:top-0.5 before:left-0.5 before:size-5 before:rounded-full before:border-2 before:border-stroke before:bg-white before:transition-transform before:duration-[var(--dur-2)] checked:bg-lime checked:before:translate-x-5" />
    </label>
  );
}

function Nickname({ profile, email, onChange }: { profile: Profile; email?: string; onChange: (p: Profile) => void }) {
  const [nickname, setNickname] = useState(profile.nickname);
  const [busy, setBusy] = useState(false);
  const issue = nicknameProblem(nickname);
  const changed = nickname.trim() !== profile.nickname;

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (issue || !changed) return;
    setBusy(true);
    const { data, error } = await supabase!.from('profiles').update({ nickname: nickname.trim() }).eq('id', profile.id).select().single();
    setBusy(false);
    if (error) return toast(t('Couldn’t save your nickname. Try again.'), 'error');
    onChange(data as Profile);
    toast(t('Saved'));
  }

  return (
    <form onSubmit={save} noValidate className="sticker grid gap-4 p-5">
      <div className="flex items-center gap-3">
        <Avatar id={profile.id} name={nickname || profile.nickname} photo={profile.avatar_path} size={56} />
        <div className="min-w-0">
          <p className="text-headline">{t('Profile')}</p>
          {email && <p className="text-footnote text-ink-secondary wrap-anywhere">{email}</p>}
        </div>
      </div>
      <Field label={t('Nickname')} hint={t('2–12 characters. No phone numbers or links.')} error={changed ? issue : undefined}>
        {(props) => <input {...props} maxLength={12} value={nickname} onChange={(e) => setNickname(e.target.value)} className="field" />}
      </Field>
      <p className="text-caption text-ink-tertiary">{t('Add or change your photo in the iPhone app.')}</p>
      <Button busy={busy} disabled={!changed || Boolean(issue)} className="justify-self-start">{t('Save')}</Button>
    </form>
  );
}

function Level({ profile }: { profile: Profile }) {
  const level = tier(profile.rating);
  const retakeAt = profile.assessed_at ? new Date(new Date(profile.assessed_at).getTime() + 90 * 86400000) : undefined;
  return (
    <section aria-labelledby="level" className="sticker grid gap-3 p-5">
      <h2 id="level" className="text-footnote font-bold text-ink-secondary">{t('Level')}</h2>
      <p className="flex items-center gap-2"><LevelBadge rating={profile.rating} /></p>
      <p className="text-subhead text-ink-secondary">
        {profile.assessed_at ? level.summary : t('You haven’t taken the level quiz yet, so you’re matched as level 3.')}
      </p>
      {!retakeAt || retakeAt.getTime() <= Date.now() ? (
        <Link to="/level-quiz/" className="button justify-self-start">{profile.assessed_at ? t('Retake the quiz') : t('Take the level quiz')}</Link>
      ) : (
        <p className="text-footnote text-ink-tertiary">
          {t('You can retake the quiz from {date}.', { date: retakeAt.toLocaleDateString(currentLocale(), { month: 'long', day: 'numeric' }) })}
        </p>
      )}
    </section>
  );
}

/** 注销：先说清会删掉什么，再点一次才删 */
function DeleteAccount({ avatar }: { avatar: string | null }) {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  // 用 Apple 登录过：网页拿不到 Apple 的授权码去撤销，告诉用户可以在 Apple 账户里自己停用（Apple 的建议）
  const [apple, setApple] = useState(false);
  useEffect(() => {
    if (confirming) supabase!.auth.getSession().then(({ data }) => setApple(Boolean(data.session?.user.app_metadata.providers?.includes('apple'))));
  }, [confirming]);

  async function remove() {
    setBusy(true);
    // 照片文件先删掉（账号删了以后就没权限删了）
    if (avatar) await supabase!.storage.from('avatars').remove([avatar]);
    const { error } = await supabase!.rpc('delete_account');
    if (error) {
      setBusy(false);
      return toast(problem(error), 'error');
    }
    toast(t('Your account was deleted.'));
    // 服务器上的登录已随账号删除，只需清掉本机的
    await supabase!.auth.signOut({ scope: 'local' });
  }

  if (!confirming) return <Row icon="trash" tint="pink" title={t('Delete account')} danger onClick={() => setConfirming(true)} />;
  return (
    <div className="grid gap-3 py-3.5" role="alert">
      <p className="text-footnote text-ink-secondary">
        {t('This deletes your profile, friends, messages, reviews and game history, and can’t be undone. Upcoming games are cancelled and the other players are told. Groups you run go to the next organizer.')}
      </p>
      {apple && <p className="text-footnote text-ink-secondary">{t('You signed in with Apple. To also stop using Apple for Badie, go to your Apple Account settings → Sign in with Apple.')}</p>}
      <div className="flex flex-wrap gap-2">
        <Button variant="danger" busy={busy} onClick={remove}>{t('Yes, delete my account')}</Button>
        <Button variant="quiet" disabled={busy} onClick={() => setConfirming(false)}>{t('Cancel')}</Button>
      </div>
    </div>
  );
}
