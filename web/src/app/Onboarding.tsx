import { useState, type SubmitEvent } from 'react';
import { supabase, type Profile } from './supabase';
import { Button, Field } from './ui';

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

// 与数据库约束一致：2–12 个字，不能留联系方式或链接（防广告）
export function nicknameProblem(nickname: string) {
  const name = nickname.trim();
  if (name.length < 2) return 'At least 2 characters.';
  if (name.length > 12) return 'At most 12 characters.';
  if (/\d{5,}|https?:|www\.|@|\.(com|net|org|io|me)\b/i.test(name)) return 'No phone numbers, emails or links.';
}

export function Onboarding({ userId, onDone }: { userId: string; onDone: (profile: Profile) => void }) {
  const [nickname, setNickname] = useState('');
  const [touched, setTouched] = useState(false);
  const [country, setCountry] = useState(guessCountry);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const problem = nicknameProblem(nickname);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    setTouched(true);
    if (problem) return;
    setBusy(true);
    const { data, error } = await supabase!
      .from('profiles')
      .insert({ id: userId, nickname: nickname.trim(), country_code: country })
      .select()
      .single();
    setBusy(false);
    if (error) setError('Couldn’t save. Try a different nickname.');
    else onDone(data as Profile);
  }

  return (
    <div className="grid min-h-dvh place-items-center bg-canvas px-[var(--gutter)] py-10">
      <form onSubmit={save} noValidate className="sticker animate-enter grid w-full max-w-md gap-5 p-6 sm:p-8">
        <div>
          <p className="eyebrow">Welcome</p>
          <h1 className="display mt-2 text-4xl">What should players call you?</h1>
        </div>
        <Field label="Nickname" hint="2–12 characters. No phone numbers or links." error={(touched && problem) || error}>
          {(props) => (
            <input
              {...props}
              autoFocus
              autoComplete="nickname"
              maxLength={12}
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              onBlur={() => setTouched(true)}
              className="field h-12"
            />
          )}
        </Field>
        <Field label="Where do you play?" hint="You’ll be matched with players in the same country.">
          {(props) => (
            <select {...props} value={country} onChange={(e) => setCountry(e.target.value)} className="field h-12">
              {countries.map((c) => (
                <option key={c.code} value={c.code}>{c.name}</option>
              ))}
            </select>
          )}
        </Field>
        <Button busy={busy}>Continue</Button>
      </form>
    </div>
  );
}
