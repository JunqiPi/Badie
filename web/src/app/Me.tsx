import { useState, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { currentLocale, t } from './i18n';
import { nicknameProblem } from './Onboarding';
import { Link } from './router';
import { problem, supabase, type Profile } from './supabase';
import { Button, Field, LanguagePicker, PageHeader, toast } from './ui';

export function Me({ profile, email, onChange }: { profile: Profile; email?: string; onChange: (p: Profile) => void }) {
  const [nickname, setNickname] = useState(profile.nickname);
  const [busy, setBusy] = useState(false);
  const problem = nicknameProblem(nickname);
  const changed = nickname.trim() !== profile.nickname;

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (problem || !changed) return;
    setBusy(true);
    const { data, error } = await supabase!.from('profiles').update({ nickname: nickname.trim() }).eq('id', profile.id).select().single();
    setBusy(false);
    if (error) return toast(t('Couldn’t save your nickname. Try again.'), 'error');
    onChange(data as Profile);
    toast(t('Saved'));
  }

  return (
    <div className="max-w-xl">
      <PageHeader eyebrow={t('Me')} title={profile.nickname}>{email}</PageHeader>

      <form onSubmit={save} noValidate className="tile grid gap-4 bg-surface p-6">
        <Field label={t('Nickname')} hint={t('2–12 characters. No phone numbers or links.')} error={changed ? problem : undefined}>
          {(props) => (
            <input {...props} maxLength={12} value={nickname} onChange={(e) => setNickname(e.target.value)} className="field h-12" />
          )}
        </Field>
        <Button busy={busy} disabled={!changed || Boolean(problem)} className="justify-self-start">{t('Save')}</Button>
      </form>

      <Level profile={profile} />
      <Settings profile={profile} onChange={onChange} />

      <div className="tile mt-6 bg-surface p-6"><LanguagePicker /></div>

      <Button variant="quiet" onClick={() => supabase!.auth.signOut()} className="mt-8">{t('Sign out')}</Button>

      <DeleteAccount />
    </div>
  );
}

/** 注销：先说清会删掉什么，再点一次才删 */
function DeleteAccount() {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  async function remove() {
    setBusy(true);
    const { error } = await supabase!.rpc('delete_account');
    if (error) {
      setBusy(false);
      return toast(problem(error), 'error');
    }
    toast(t('Your account was deleted.'));
    // 服务器上的登录已随账号删除，只需清掉本机的
    await supabase!.auth.signOut({ scope: 'local' });
  }

  return (
    <section aria-labelledby="delete-account" className="tile mt-10 grid gap-3 bg-surface p-6">
      <h2 id="delete-account" className="eyebrow">{t('Delete account')}</h2>
      <p className="text-sm text-ink-secondary">
        {t('This deletes your profile, friends, messages, reviews and game history, and can’t be undone. Upcoming games are cancelled and the other players are told. Groups you run go to the next organizer.')}
      </p>
      {confirming ? (
        <div className="flex flex-wrap gap-2">
          <Button variant="danger" busy={busy} onClick={remove}>{t('Yes, delete my account')}</Button>
          <Button variant="quiet" disabled={busy} onClick={() => setConfirming(false)}>{t('Cancel')}</Button>
        </div>
      ) : (
        <Button variant="quiet" onClick={() => setConfirming(true)} className="justify-self-start">{t('Delete account')}</Button>
      )}
    </section>
  );
}

function Level({ profile }: { profile: Profile }) {
  const level = tier(profile.rating);
  const retakeAt = profile.assessed_at ? new Date(new Date(profile.assessed_at).getTime() + 90 * 86400000) : undefined;
  return (
    <section aria-labelledby="level" className="tile mt-6 grid gap-3 bg-surface p-6">
      <p id="level" className="eyebrow">{t('Level')}</p>
      <p>
        <span className="display text-5xl">{level.label}</span> <span className="text-lg font-black">{level.name}</span>
      </p>
      <p className="text-ink-secondary">
        {profile.assessed_at ? level.summary : t('You haven’t taken the level quiz yet, so you’re matched as level 3.')}
      </p>
      {!retakeAt || retakeAt.getTime() <= Date.now() ? (
        <Link to="/app/level/" className="button justify-self-start">{profile.assessed_at ? t('Retake the quiz') : t('Take the level quiz')}</Link>
      ) : (
        <p className="text-sm text-ink-tertiary">
          {t('You can retake the quiz from {date}.', { date: retakeAt.toLocaleDateString(currentLocale(), { month: 'long', day: 'numeric' }) })}
        </p>
      )}
    </section>
  );
}

const policies = [
  ['similar', 'Players within 1 level'],
  ['everyone', 'Anyone in my country'],
  ['friends', 'Friends only'],
  ['nobody', 'No one'],
] as const;

/** 被搜到、上榜和约战设置：界面马上切换并保存，失败就切回去 */
function Settings({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  async function save(patch: Partial<Pick<Profile, 'discoverable' | 'show_as_regular' | 'allow_message_requests' | 'show_on_boards' | 'challenge_policy'>>) {
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
    <section aria-labelledby="settings" className="tile mt-6 grid gap-5 bg-surface p-6">
      <h2 id="settings" className="eyebrow">{t('Who can find me')}</h2>
      <label className="flex items-start gap-3">
        <input type="checkbox" checked={profile.discoverable} onChange={(e) => save({ discoverable: e.target.checked })} className="mt-1 size-5 accent-[var(--color-lime)]" />
        <span>
          <span className="block font-extrabold">{t('Let players find me by nickname')}</span>
          <span className="block text-sm text-ink-tertiary">{t('They see your nickname and level, and can send a friend request.')}</span>
        </span>
      </label>
      <label className="flex items-start gap-3">
        <input type="checkbox" checked={profile.show_as_regular} onChange={(e) => save({ show_as_regular: e.target.checked })} className="mt-1 size-5 accent-[var(--color-lime)]" />
        <span>
          <span className="block font-extrabold">{t('Show me as a regular at my courts')}</span>
          <span className="block text-sm text-ink-tertiary">{t('Players who starred the same court see your nickname, level and the court. Never when you play or where you are.')}</span>
        </span>
      </label>
      <label className="flex items-start gap-3">
        <input type="checkbox" checked={profile.allow_message_requests} onChange={(e) => save({ allow_message_requests: e.target.checked })} className="mt-1 size-5 accent-[var(--color-lime)]" />
        <span>
          <span className="block font-extrabold">{t('Allow message requests from my groups')}</span>
          <span className="block text-sm text-ink-tertiary">{t('When off, only friends can message you. Game and group chats still work.')}</span>
        </span>
      </label>
      <label className="flex items-start gap-3">
        <input type="checkbox" checked={profile.show_on_boards} onChange={(e) => save({ show_on_boards: e.target.checked })} className="mt-1 size-5 accent-[var(--color-lime)]" />
        <span>
          <span className="block font-extrabold">{t('Show me on leaderboards')}</span>
          <span className="block text-sm text-ink-tertiary">{t('Weekly and court boards show your nickname, level and games.')}</span>
        </span>
      </label>
      <label className="grid gap-1.5">
        <span className="font-extrabold">{t('Who can challenge me')}</span>
        <select value={profile.challenge_policy} onChange={(e) => save({ challenge_policy: e.target.value as Profile['challenge_policy'] })} className="field">
          {policies.map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
        </select>
      </label>
    </section>
  );
}
