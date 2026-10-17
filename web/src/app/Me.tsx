import { useState, type SubmitEvent } from 'react';
import { nicknameProblem } from './Onboarding';
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

      <Button variant="quiet" onClick={() => supabase!.auth.signOut()} className="mt-8">Sign out</Button>
    </div>
  );
}
