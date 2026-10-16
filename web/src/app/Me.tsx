import { useState, type SubmitEvent } from 'react';
import { supabase, type Profile } from './supabase';

export function Me({ profile, email, onChange }: { profile: Profile; email?: string; onChange: (p: Profile) => void }) {
  const [nickname, setNickname] = useState(profile.nickname);
  const [saved, setSaved] = useState(false);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    const { data, error } = await supabase!.from('profiles').update({ nickname: nickname.trim() }).eq('id', profile.id).select().single();
    if (!error) {
      onChange(data as Profile);
      setSaved(true);
    }
  }

  return (
    <div className="max-w-xl">
      <p className="eyebrow">Me</p>
      <h1 className="display mt-2 text-5xl">{profile.nickname}</h1>
      {email && <p className="mt-2 font-bold text-ink-secondary">{email}</p>}

      <form onSubmit={save} className="tile mt-8 grid gap-3 bg-surface p-6">
        <label className="grid gap-1 font-extrabold">
          Nickname
          <input
            required
            minLength={2}
            maxLength={12}
            value={nickname}
            onChange={(e) => { setNickname(e.target.value); setSaved(false); }}
            className="tile h-12 bg-surface px-4 font-bold outline-none focus:border-lavender"
          />
        </label>
        <button className="button justify-self-start">{saved ? 'Saved' : 'Save'}</button>
      </form>

      <button onClick={() => supabase!.auth.signOut()} className="mt-8 font-extrabold text-danger underline">
        Sign out
      </button>
    </div>
  );
}
