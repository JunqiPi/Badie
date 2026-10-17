import { useState, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { nicknameProblem } from './Onboarding';
import { Link } from './router';
import { supabase, type Profile } from './supabase';
import { Button, Field, PageHeader, toast } from './ui';

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
    if (error) return toast('Couldn’t save your nickname. Try again.', 'error');
    onChange(data as Profile);
    toast('Saved');
  }

  return (
    <div className="max-w-xl">
      <PageHeader eyebrow="Me" title={profile.nickname}>{email}</PageHeader>

      <form onSubmit={save} noValidate className="tile grid gap-4 bg-surface p-6">
        <Field label="Nickname" hint="2–12 characters. No phone numbers or links." error={changed ? problem : undefined}>
          {(props) => (
            <input {...props} maxLength={12} value={nickname} onChange={(e) => setNickname(e.target.value)} className="field h-12" />
          )}
        </Field>
        <Button busy={busy} disabled={!changed || Boolean(problem)} className="justify-self-start">Save</Button>
      </form>

      <Level profile={profile} />

      <Button variant="quiet" onClick={() => supabase!.auth.signOut()} className="mt-8">Sign out</Button>
    </div>
  );
}

function Level({ profile }: { profile: Profile }) {
  const level = tier(profile.rating);
  const retakeAt = profile.assessed_at ? new Date(new Date(profile.assessed_at).getTime() + 90 * 86400000) : undefined;
  return (
    <section aria-labelledby="level" className="tile mt-6 grid gap-3 bg-surface p-6">
      <p id="level" className="eyebrow">Level</p>
      <p>
        <span className="display text-5xl">{level.label}</span> <span className="text-lg font-black">{level.name}</span>
      </p>
      <p className="text-ink-secondary">
        {profile.assessed_at ? level.summary : 'You haven’t taken the level quiz yet, so you’re matched as level 3.'}
      </p>
      {!retakeAt || retakeAt.getTime() <= Date.now() ? (
        <Link to="/app/level/" className="button justify-self-start">{profile.assessed_at ? 'Retake the quiz' : 'Take the level quiz'}</Link>
      ) : (
        <p className="text-sm text-ink-tertiary">You can retake the quiz from {retakeAt.toLocaleDateString('en-US', { month: 'long', day: 'numeric' })}.</p>
      )}
    </section>
  );
}
