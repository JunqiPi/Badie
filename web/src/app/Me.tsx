import { useEffect, useState, type SubmitEvent } from 'react';
import { gapText, tier } from './assessment';
import { DONATIONS_OPEN, SUPPORT_EMAIL } from './Contact';
import { MyCard, ProfileProgress, useMyCourts } from './EditProfile';
import { currentLocale, t } from './i18n';
import { Icon } from './icons';
import { Divider, Group, IconButton, LargeTitle, LevelBadge, Notice, Row, ScreenHeader, StatTile } from './kit';
import { passwordProblem } from './password';
import { disablePush, enablePush, pushState, type PushState } from './push';
import { Link } from './router';
import { cleanPhotoFolder, friendLink, problem, supabase, winPercent, suspendedText, useLive, type Friend, type MyStrikes, type PlayerCard, type PlayRecord, type Profile, type Strike } from './supabase';
import { day } from './time';
import { Button, Field, PasswordInput, toast } from './ui';
import { AdminLink } from './Verification';

/** 我的（iOS 的 ProfileView）：我的卡片（和发现页同一张）、编辑资料、资料 N/5、场次和到场、本月胜率、菜单 */
export function Me({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const { data: card } = useLive<PlayerCard | null>('player_card', { args: { p_user: profile.id }, every: 300_000 });
  const { data: record } = useLive<PlayRecord>('my_record', { every: 300_000 });
  const { data: friends } = useLive<{ friends: Friend[]; requests: Friend[] }>('my_friends', { every: 120_000 });
  const courts = useMyCourts();
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

      <MissedGames />

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start lg:gap-8">
        <div className="grid min-w-0 gap-6">
          {/* 最上面是我的卡片（别人在发现页刷到的样子），点一下看预览 */}
          <section aria-label={t('My profile')} className="grid gap-3">
            <Link to="/me/edit/?tab=preview" aria-label={t('My card')} className="press grid aspect-[4/5] max-h-[32rem] rounded-[var(--radius-card)]">
              <MyCard profile={profile} card={card} courts={courts} />
            </Link>
            <div className="flex flex-wrap gap-2.5">
              <Link to="/me/edit/" className="button flex-1 basis-36">{t('Edit profile')}</Link>
              {profile.assessment && <Link to="/level-quiz/result/" className="button button-quiet flex-1 basis-36">{t('Share level card')}</Link>}
            </div>
            {courts && <ProfileProgress profile={profile} courts={courts} />}
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
          <FriendLink profile={profile} onChange={onChange} />
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
          <nav aria-label={t('Help')} className="sticker grid px-4 py-1">
            <Row icon="question" tint="sky" title={t('Help & feedback')} to="/contact/" />
            {DONATIONS_OPEN && <Divider />}
            {DONATIONS_OPEN && <Row icon="heart" tint="peach" title={t('Support Badie')} to="/support/" />}
          </nav>
          <AdminLink />
        </aside>
      </div>
    </div>
  );
}

const strikeStatus: Record<Strike['status'], string> = {
  active: '', appealed: 'Appeal under review', upheld: 'Appeal declined', overturned: 'Removed after appeal',
};

/** 爽约记录：180 天内第 1 次警告、第 2 次 7 天不能约球、第 3 次永久；48 小时内可以申诉 */
function MissedGames() {
  const { data, refresh } = useLive<MyStrikes>('my_strikes', { every: 300_000 });
  const unseen = data?.strikes.some((s) => !s.seen);
  useEffect(() => { if (unseen) void supabase!.rpc('mark_strikes_seen'); }, [unseen]);
  if (!data || data.strikes.length === 0) return null;
  return (
    <section aria-labelledby="missed" className="sticker grid gap-3 bg-pink p-5 text-on-accent">
      <h2 id="missed" className="text-headline">
        {data.suspended_until ? suspendedText(data.suspended_until)
          : t('{n} missed game in 180 days|{n} missed games in 180 days', { n: data.recent })}
      </h2>
      <p className="text-footnote">{t('Second missed game in 180 days: no games for 7 days. Third: no more games. The count resets after 180 days without one.')}</p>
      <ul className="grid gap-2">
        {data.strikes.map((s) => <StrikeRow key={s.id} strike={s} onDone={refresh} />)}
      </ul>
    </section>
  );
}

function StrikeRow({ strike, onDone }: { strike: Strike; onDone: () => void }) {
  const [open, setOpen] = useState(false);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);

  async function appeal(event: SubmitEvent) {
    event.preventDefault();
    setBusy(true);
    const { error } = await supabase!.rpc('appeal_strike', { p_strike: strike.id, p_text: text });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    setOpen(false);
    toast(t('Appeal sent. We’ll reply within 24 hours.'));
    onDone();
  }

  return (
    <li className="grid gap-2 rounded-[12px] bg-white/70 p-3 text-[#17140f]">
      <div className="flex flex-wrap items-center justify-between gap-2 text-footnote">
        <span className="font-bold">{day(strike.game_starts_at, strike.tz)}{strike.venue && ` · ${strike.venue}`}</span>
        {strikeStatus[strike.status] && <span>{t(strikeStatus[strike.status])}</span>}
        {strike.can_appeal && !open && <Button className="button-sm" variant="quiet" onClick={() => setOpen(true)}>{t('Appeal')}</Button>}
      </div>
      {open && (
        <form onSubmit={appeal} noValidate className="grid gap-2">
          <Field label={t('What happened?')} hint={t('For example: you were there but forgot to check in.')}>
            {(props) => <textarea {...props} rows={3} maxLength={500} value={text} onChange={(e) => setText(e.target.value)} className="field" />}
          </Field>
          <div className="flex gap-2">
            <Button className="button-sm" busy={busy} disabled={text.trim().length < 5}>{t('Send appeal')}</Button>
            <Button type="button" className="button-sm" variant="quiet" onClick={() => setOpen(false)}>{t('Cancel')}</Button>
          </div>
        </form>
      )}
    </li>
  );
}

/** 加球友链接：发给对方，打开就能加我（关了被搜到也可以）；重置后旧链接失效 */
function FriendLink({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const link = friendLink(profile.friend_code);

  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      toast(t('Link copied'));
    } catch {
      toast(link);
    }
  }

  async function reset() {
    setBusy(true);
    const { data, error } = await supabase!.rpc('reset_friend_code');
    setBusy(false);
    setConfirming(false);
    if (error) return toast(problem(error), 'error');
    onChange({ ...profile, friend_code: data as string });
    toast(t('New link ready'));
  }

  return (
    <section id="friend-link" aria-labelledby="friend-link-title" className="sticker grid gap-3 p-5">
      <div>
        <h2 id="friend-link-title" className="text-headline">{t('My friend link')}</h2>
        <p className="text-footnote text-ink-secondary">{t('Anyone with this link can add you.')}</p>
      </div>
      <p className="truncate rounded-[12px] bg-surface-muted px-3 py-2 font-mono text-footnote">{link}</p>
      {confirming ? (
        <div className="grid gap-2">
          <p className="text-footnote font-bold">{t('The old link stops working.')}</p>
          <div className="flex flex-wrap gap-2">
            <Button className="button-sm" variant="danger" busy={busy} onClick={reset}>{t('Reset link')}</Button>
            <Button className="button-sm" variant="quiet" onClick={() => setConfirming(false)}>{t('Cancel')}</Button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          <Button className="button-sm" onClick={copy}>{t('Copy link')}</Button>
          <Button className="button-sm" variant="quiet" onClick={() => setConfirming(true)}>{t('Reset link')}</Button>
        </div>
      )}
    </section>
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
          <span className="text-[2.75rem] leading-none font-black tabular-nums">{winPercent(record) ?? 0}%</span>
          <span className="text-footnote font-bold text-ink-secondary">{t('Won {won} of {played} games', { won: record.round_wins ?? record.wins, played: record.rounds ?? record.games })}</span>
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
        <h2 className="text-headline">{good ? t('Attendance · Good') : t('Attendance · Needs attention')}</h2>
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

type Toggles = Pick<Profile, 'discoverable' | 'show_as_regular' | 'show_searching' | 'allow_message_requests' | 'show_on_boards' | 'challenge_policy' | 'email_alerts' | 'gender'>;

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
      <Group title={t('Profile')}>
        <Row icon="pencil" tint="lavender" title={t('Edit profile')} subtitle={email && <span className="wrap-anywhere">{email}</span>} to="/me/edit/" />
      </Group>

      <Group title={t('Notifications')}>
        <PushSettings />
        <Switch checked={profile.email_alerts} onChange={(v) => save({ email_alerts: v })} title={t('Email me about matches')}
                text={t('Match offers, confirmations and cancellations also go to {email}.', { email: email ?? t('your email') })} />
      </Group>

      <Group title={t('Who can find me')}>
        <Switch checked={profile.show_searching} onChange={(v) => save({ show_searching: v })} title={t('Show me to nearby players when I’m looking for a game')}
                text={t('They see your nickname, photo, level and the time and courts you picked. Never your contact details.')} />
        <Divider />
        <Switch checked={profile.discoverable} onChange={(v) => save({ discoverable: v })} title={t('Let players find me by nickname')}
                text={t('They see your nickname and level, and can send a friend request.')} />
        <Divider />
        <Switch checked={profile.show_as_regular} onChange={(v) => save({ show_as_regular: v })} title={t('Show me as a regular at my courts')}
                text={t('Shows your card, level and free times in People nearby and to players who starred the same court. Never where you are.')} />
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
        <Row icon="question" tint="sky" title={t('Help & feedback')} subtitle={SUPPORT_EMAIL} to="/contact/" />
        {DONATIONS_OPEN && <Divider />}
        {DONATIONS_OPEN && <Row icon="heart" tint="peach" title={t('Support Badie')} to="/support/" />}
      </Group>

      <Group title={t('Account')}>
        <Row icon="signOut" tint="muted" title={t('Sign out')} onClick={() => disablePush().catch(() => {}).finally(() => supabase!.auth.signOut())} />
        <Divider />
        <DeleteAccount id={profile.id} photos={[profile.avatar_path, profile.card_photo_path]} />
      </Group>

      <p className="flex justify-center gap-4 text-footnote font-bold">
        <Link to="/privacy/" className="link">{t('Privacy Policy')}</Link>
        <Link to="/terms/" className="link">{t('Terms of Service')}</Link>
      </p>
    </div>
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
    const issue = await passwordProblem(password);
    const { error } = issue ? { error: undefined } : await supabase!.auth.updateUser({ password });
    setBusy(false);
    if (issue) return setError(issue);
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
function DeleteAccount({ id, photos }: { id: string; photos: (string | null)[] }) {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  // 用 Apple 登录过：网页拿不到 Apple 的授权码去撤销，告诉用户可以在 Apple 账户里自己停用（Apple 的建议）
  const [apple, setApple] = useState(false);
  useEffect(() => {
    if (confirming) supabase!.auth.getSession().then(({ data }) => setApple(Boolean(data.session?.user.app_metadata.providers?.includes('apple'))));
  }, [confirming]);

  async function remove() {
    setBusy(true);
    // 照片文件先删掉（账号删了以后就没权限删了）；先解除引用，注销失败也不会留下坏图
    if (photos.some(Boolean)) await Promise.all([supabase!.rpc('set_avatar', { p_path: null }), supabase!.rpc('set_card_photo', { p_path: null })]);
    await cleanPhotoFolder(id, []).catch(() => {});
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
