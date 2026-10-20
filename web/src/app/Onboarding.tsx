import { useState, type SubmitEvent } from 'react';
import { GenderField, type Gender } from './gender';
import { currentLocale, t } from './i18n';
import { supabase, type Profile } from './supabase';
import { CardFan } from './kit';
import { Button, Field } from './ui';

const codes = ['US', 'CA', 'GB', 'AU', 'NZ', 'SG', 'MY', 'HK', 'TW', 'JP', 'KR', 'IN', 'ID', 'TH', 'VN', 'PH', 'DE', 'FR', 'DK', 'CN'];

/** 国家 / 地区名按界面语言显示 */
function countries() {
  const names = new Intl.DisplayNames([currentLocale()], { type: 'region' });
  return codes.map((code) => ({ code, name: names.of(code) ?? code })).sort((a, b) => a.name.localeCompare(b.name, currentLocale()));
}

function guessCountry() {
  try {
    const region = new Intl.Locale(navigator.language).maximize().region;
    if (codes.includes(region!)) return region!;
  } catch {
    // 有些浏览器给的语言标签不合法（如 "C"），按首发市场处理
  }
  return 'US';
}

// 与数据库约束一致：2–12 个字，不能留联系方式或链接（防广告）
export function nicknameProblem(nickname: string) {
  const name = nickname.trim();
  if (name.length < 2) return t('At least 2 characters.');
  if (name.length > 12) return t('At most 12 characters.');
  if (/\d{5,}|https?:|www\.|@|\.(com|net|org|io|me)\b/i.test(name)) return t('No phone numbers, emails or links.');
}

export function Onboarding({ userId, onDone }: { userId: string; onDone: (profile: Profile) => void }) {
  const [nickname, setNickname] = useState('');
  const [touched, setTouched] = useState(false);
  const [country, setCountry] = useState(guessCountry);
  const [gender, setGender] = useState<Gender | null>(null);
  // 点了“继续”才提示没选性别（离开昵称框就提示会让页面跳动，点不准）
  const [tried, setTried] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const problem = nicknameProblem(nickname);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    setTouched(true);
    setTried(true);
    if (problem || !gender) return;
    setBusy(true);
    const { data, error } = await supabase!
      .from('profiles')
      .insert({ id: userId, nickname: nickname.trim(), country_code: country, gender })
      .select()
      .single();
    setBusy(false);
    if (error) setError(t('Couldn’t save. Try a different nickname.'));
    else onDone(data as Profile);
  }

  return (
    <div className="mx-auto grid max-w-md gap-6 py-4">
      <CardFan />
      <form onSubmit={save} noValidate className="sticker animate-enter grid w-full gap-5 p-6 sm:p-8">
        <div>
          <p className="text-subhead font-bold text-ink-secondary">{t('Welcome')}</p>
          <h1 className="mt-1 text-title">{t('What should players call you?')}</h1>
        </div>
        <Field label={t('Nickname')} hint={t('2–12 characters. No phone numbers or links.')} error={(touched && problem) || error}>
          {(props) => (
            <input
              {...props}
              autoFocus
              autoComplete="nickname"
              maxLength={12}
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              onBlur={() => setTouched(true)}
              className="field"
            />
          )}
        </Field>
        <Field label={t('Where do you play?')} hint={t('You’ll be matched with players in the same country.')}>
          {(props) => (
            <select {...props} value={country} onChange={(e) => setCountry(e.target.value)} className="field">
              {countries().map((c) => (
                <option key={c.code} value={c.code}>{c.name}</option>
              ))}
            </select>
          )}
        </Field>
        <GenderField value={gender} onChange={setGender} error={tried && !gender ? t('Choose one to continue.') : undefined} />
        <Button className="button-lg button-inverse" busy={busy}>{t('Continue')}</Button>
      </form>
    </div>
  );
}

/** 以前注册、还没填性别的人：打开 App 先补上（男女的等级分开算） */
export function GenderPrompt({ profile, onDone }: { profile: Profile; onDone: (profile: Profile) => void }) {
  const [gender, setGender] = useState<Gender | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!gender) return setError(t('Choose one to continue.'));
    setBusy(true);
    const { data, error } = await supabase!.from('profiles').update({ gender }).eq('id', profile.id).select().single();
    setBusy(false);
    if (error) setError(t('Couldn’t save. Try again.'));
    else onDone(data as Profile);
  }

  return (
    <div className="mx-auto grid max-w-md gap-6 py-4">
      <form onSubmit={save} noValidate className="sticker animate-enter grid w-full gap-5 p-6 sm:p-8">
        <div>
          <p className="text-subhead font-bold text-ink-secondary">{t('One more thing')}</p>
          <h1 className="mt-1 text-title">{t('Men’s or women’s levels?')}</h1>
        </div>
        <GenderField value={gender} onChange={(g) => { setGender(g); setError(undefined); }} error={error} />
        <Button className="button-lg button-inverse" busy={busy}>{t('Continue')}</Button>
      </form>
    </div>
  );
}
