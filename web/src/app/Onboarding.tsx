import { useEffect, useState, type SubmitEvent } from 'react';
import { setArea, useArea } from './area';
import { GenderField, type Gender } from './gender';
import { currentLocale, t } from './i18n';
import { loadRef } from './quizStore';
import { heardFromOptions, problem as explain, supabase, type HeardFrom, type Profile } from './supabase';
import { CardFan } from './kit';
import { CourtSearch } from './pickers';
import { Button, Field, toast } from './ui';
import { addUsualCourt, nearestCourt, type UsualCourt } from './usualCourt';

/** “你从哪里知道 Badie 的” 的选项（和数据库的约束一致） */
const heardFromLabel = (option: HeardFrom) => ({
  friend: t('A friend'),
  level_card: t('Someone’s level card'),
  social: t('Social media'),
  search: t('Search engine'),
  app_store: t('App Store'),
  club: t('My club or group'),
  other: t('Somewhere else'),
})[option];

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
  // 常去球馆：必填，默认离你最近的一家（附近的人靠它找到你）。“在附近的人里显示我”新账号默认开，以后在设置里能关
  const [court, setCourt] = useState<UsualCourt>();
  const [changingCourt, setChangingCourt] = useState(false);
  // 我们还没收录的地方（搜不到自己的球馆）：可以先不选，以后在球馆页选
  const [noCourt, setNoCourt] = useState(false);
  const [locating, setLocating] = useState(false);
  const area = useArea();
  const [heardFrom, setHeardFrom] = useState<HeardFrom | ''>('');
  // 点了“继续”才提示没选性别（离开昵称框就提示会让页面跳动，点不准）
  const [tried, setTried] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const problem = nicknameProblem(nickname);

  // 知道你在哪（定位过或搜过城市）就先选上最近的一家
  useEffect(() => {
    if (!area || court) return;
    let stale = false;
    nearestCourt(area).then((nearest) => !stale && nearest && setCourt((current) => current ?? nearest));
    return () => {
      stale = true;
    };
  }, [area]);

  function locate() {
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (p) => {
        setLocating(false);
        setArea({ lat: p.coords.latitude, lon: p.coords.longitude });
      },
      () => {
        setLocating(false);
        toast(t('Location is off. Search for your court instead.'), 'error');
      },
      { timeout: 10000 },
    );
  }

  async function save(event: SubmitEvent) {
    event.preventDefault();
    setTouched(true);
    setTried(true);
    if (problem || !gender || (!court && !noCourt)) return;
    setBusy(true);
    const { data, error } = await supabase!
      .from('profiles')
      // 来源：从哪个链接来的（?ref=card，不含个人信息）和自己选的，都可以没有
      .insert({ id: userId, nickname: nickname.trim(), country_code: country, gender, ...(loadRef() && { ref: loadRef() }), ...(heardFrom && { heard_from: heardFrom }) })
      .select()
      .single();
    const saved = !error && (!court || !(await addUsualCourt(userId, court.id)).error);
    setBusy(false);
    // 昵称有不当用语时说清楚原因，其他情况多半是重名之类，换一个就好
    if (error) setError(error.message === 'objectionable_content' ? explain(error) : t('Couldn’t save. Try a different nickname.'));
    else if (!saved) setError(t('Couldn’t save. Try again.'));
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
        <fieldset className="grid gap-1.5">
          <legend className="mb-1.5 text-footnote font-bold text-ink-secondary">{t('Usual court')}</legend>
          {court && !changingCourt ? (
            <div className="tile flex items-center gap-3 p-3">
              <span className="min-w-0 flex-1">
                <span className="block truncate text-headline">{court.name}</span>
                <span className="block truncate text-footnote text-ink-secondary">{court.city}</span>
              </span>
              <button type="button" onClick={() => setChangingCourt(true)} className="button button-sm button-quiet">{t('Change')}</button>
            </div>
          ) : (
            <div className="grid gap-2">
              {!court && <Button type="button" variant="quiet" busy={locating} onClick={locate}>{t('Use my location')}</Button>}
              <CourtSearch onPick={(c) => { setCourt({ id: c.id, name: c.name, city: c.city }); setChangingCourt(false); setNoCourt(false); }} />
              {!court && !noCourt && (
                <button type="button" onClick={() => setNoCourt(true)} className="justify-self-start text-footnote font-bold underline underline-offset-4">
                  {t('My court isn’t listed')}
                </button>
              )}
            </div>
          )}
          <p className={`text-footnote ${tried && !court && !noCourt ? 'font-bold text-danger' : 'text-ink-secondary'}`} role={tried && !court && !noCourt ? 'alert' : undefined}>
            {tried && !court && !noCourt ? t('Choose a court to continue.')
              : !court && noCourt ? t('OK. You can choose one later in Courts.')
              : t('Players near this court can find you.')}
          </p>
        </fieldset>
        <Field label={`${t('Where did you hear about Badie?')} ${t('(optional)')}`}>
          {(props) => (
            <select {...props} value={heardFrom} onChange={(e) => setHeardFrom(e.target.value as HeardFrom | '')} className="field">
              <option value="">—</option>
              {heardFromOptions.map((option) => <option key={option} value={option}>{heardFromLabel(option)}</option>)}
            </select>
          )}
        </Field>
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
