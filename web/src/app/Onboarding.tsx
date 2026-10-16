import { useState, type SubmitEvent } from 'react';
import { supabase, type Profile } from './supabase';

const regionNames = new Intl.DisplayNames(['en'], { type: 'region' });
const countries = ['US', 'CA', 'GB', 'AU', 'NZ', 'SG', 'MY', 'HK', 'TW', 'JP', 'KR', 'IN', 'ID', 'TH', 'VN', 'PH', 'DE', 'FR', 'DK', 'CN']
  .map((code) => ({ code, name: code === 'HK' ? 'Hong Kong' : (regionNames.of(code) ?? code) }))
  .sort((a, b) => a.name.localeCompare(b.name));
function guessCountry() {
  try {
    const region = new Intl.Locale(navigator.language).maximize().region;
    if (countries.some((c) => c.code === region)) return region!;
  } catch {
    // 有些浏览器给的语言标签不合法（如 "C"），按首发市场处理
  }
  return 'US';
}

export function Onboarding({ userId, onDone }: { userId: string; onDone: (profile: Profile) => void }) {
  const [nickname, setNickname] = useState('');
  const [country, setCountry] = useState(guessCountry);
  const [error, setError] = useState<string>();
  const valid = nickname.trim().length >= 2 && nickname.trim().length <= 12;

  async function save(event: SubmitEvent) {
    event.preventDefault();
    const { data, error } = await supabase!
      .from('profiles')
      .insert({ id: userId, nickname: nickname.trim(), country_code: country })
      .select()
      .single();
    if (error) setError(error.message);
    else onDone(data as Profile);
  }

  return (
    <div className="mx-auto grid min-h-screen max-w-md content-center px-5">
      <form onSubmit={save} className="sticker grid gap-4 p-6">
        <div>
          <p className="eyebrow">Welcome</p>
          <h1 className="display mt-2 text-4xl">What should players call you?</h1>
        </div>
        <label className="grid gap-1 font-extrabold">
          Nickname
          <input
            required
            maxLength={12}
            value={nickname}
            onChange={(e) => setNickname(e.target.value)}
            className="tile h-12 bg-surface px-4 font-bold outline-none focus:border-lavender"
          />
          <span className="text-sm font-bold text-ink-tertiary">2–12 characters. No phone numbers or links.</span>
        </label>
        <label className="grid gap-1 font-extrabold">
          Where do you play?
          <select value={country} onChange={(e) => setCountry(e.target.value)} className="tile h-12 bg-surface px-3 font-bold">
            {countries.map((c) => (
              <option key={c.code} value={c.code}>{c.name}</option>
            ))}
          </select>
        </label>
        {error && <p role="alert" className="text-sm font-bold text-danger">{error}</p>}
        <button disabled={!valid} className="button disabled:opacity-50">Continue</button>
      </form>
    </div>
  );
}
