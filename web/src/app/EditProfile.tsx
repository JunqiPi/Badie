import { useEffect, useRef, useState, type SubmitEvent } from 'react';
import { AvatarCrop, decode } from './AvatarCrop';
import { CardColors, removePhoto, uploadAvatar, uploadCardPhoto } from './CardBackground';
import { km } from './Courts';
import { GenderField } from './gender';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { Divider, Group, IconButton, IconTile, Row, ScreenHeader, Segmented } from './kit';
import { sortUsual, Sheet, UsualChips } from './Nearby';
import { nicknameProblem } from './Onboarding';
import { CardCover, DayCard, type CardPerson } from './PlayerCard';
import { Link } from './router';
import { avatarUrl, problem, supabase, useLive, type Mode, type PlayerCard, type Profile } from './supabase';
import { clock } from './time';
import { toHHMM, toMinutes, weekdayShort, type UsualTime } from './usual';
import { Button, Field, toast } from './ui';

// 我的卡片（“我的”最上面、编辑资料的预览）和编辑资料（iOS 的 EditProfileView）

type Court = { id: string; name: string };

/** 我收藏的球馆（“常去”）：先收藏的排前面。没加载完是 undefined */
export function useMyCourts() {
  const [courts, setCourts] = useState<Court[]>();
  useEffect(() => {
    supabase!.from('favorite_venues').select('venues(id, name)').order('created_at').then(({ data }) => {
      setCourts((data ?? []).flatMap((f) => (f.venues ? [f.venues as unknown as Court] : [])));
    });
  }, []);
  return courts;
}

/** 我的卡片：和别人在发现页刷到的是同一个组件。distance：预览里像别人看到的那样带上距离（示例），“我的”页上不带 */
export function MyCard({ profile, card, courts, distance }: { profile: Profile; card?: PlayerCard | null; courts?: Court[]; distance?: number }) {
  const person: CardPerson = {
    id: profile.id, nickname: profile.nickname, tag: profile.tag, rating: profile.rating, avatar: profile.avatar_path,
    card_color: profile.card_color, card_photo: profile.card_photo_path, recent_no_shows: card?.recent_no_shows,
  };
  const venue = courts?.[0];
  const mode = profile.preferred_mode;
  const label = venue
    ? [distance != null && km(distance * 1000), t('Often plays at {venue}', { venue: venue.name })].filter(Boolean).join(' · ')
    : distance != null ? t('Plays nearby') : undefined;
  return (
    <DayCard
      person={person}
      label={label}
      details={[mode && (mode === 'doubles' ? t('Doubles') : t('Singles'))]}
      reliable={Boolean(card) && (card?.recent_no_shows ?? 0) === 0}
      footer={<UsualChips times={profile.usual_times} />}
    />
  );
}

/** 资料填了几项（卡片照片、头像、空闲时间、常去球馆；常打不算：“都行”存的是 null，和没填分不出来），点一下去编辑资料里填下一项。填齐了不显示 */
export function ProfileProgress({ profile, courts }: { profile: Profile; courts: Court[] }) {
  const steps: [boolean, string, string][] = [
    [Boolean(profile.card_photo_path), 'photos', t('Add a card photo')],
    [Boolean(profile.avatar_path), 'photos', t('Add a profile photo')],
    [Boolean(profile.usual_times?.length), 'free-times', t('Add free times to get more invites')],
    [courts.length > 0, 'courts', t('Add the courts you play at')],
  ];
  const next = steps.find(([done]) => !done);
  if (!next) return null;
  return (
    <Link to={`/me/edit/#${next[1]}`} className="press flex min-h-12 items-center gap-2 rounded-[16px] border-2 border-dashed border-stroke bg-surface px-4 py-2.5 text-footnote font-bold">
      <span className="min-w-0 flex-1">{t('Profile {n}/4', { n: steps.filter(([done]) => done).length })} · {next[2]}</span>
      <Icon name="chevronRight" className="size-3.5 shrink-0 text-ink-tertiary" />
    </Link>
  );
}

/** 编辑资料：“编辑 / 预览”两个标签。每一项改了马上存 */
export function EditProfile({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const [tab, setTab] = useState<'edit' | 'preview'>(() => (new URLSearchParams(location.search).get('tab') === 'preview' ? 'preview' : 'edit'));
  const courts = useMyCourts();
  const { data: card } = useLive<PlayerCard | null>('player_card', { args: { p_user: profile.id }, every: 300_000 });
  // 上传要几秒：期间别的改动不能被上传前的资料盖掉
  const latest = useRef(profile);
  latest.current = profile;
  const patch = (p: Partial<Profile>) => onChange({ ...latest.current, ...p });

  // 从“我的”里“资料 N/5”点过来：滚到要填的那一项
  useEffect(() => {
    const id = location.hash.slice(1);
    if (id) document.getElementById(id)?.scrollIntoView({ block: 'center' });
  }, []);

  function switchTab(next: 'edit' | 'preview') {
    setTab(next);
    history.replaceState(null, '', next === 'preview' ? '?tab=preview' : location.pathname);
  }

  return (
    <div className="mx-auto grid max-w-2xl gap-6">
      <ScreenHeader title={t('Edit profile')} back="/me/">
        <Link to="/me/" className="press grid min-h-11 place-items-center rounded-[12px] px-2 font-bold">{t('Done')}</Link>
      </ScreenHeader>
      <Segmented label={t('Edit profile')} value={tab} onChange={switchTab}
                 options={[{ value: 'edit', label: t('Edit') }, { value: 'preview', label: t('Preview') }]} />

      {tab === 'preview' ? (
        <div className="mx-auto grid w-full max-w-md gap-4">
          <div className="grid aspect-[3/4] max-h-[70dvh]">
            <MyCard profile={profile} card={card} courts={courts} distance={1.9} />
          </div>
          {/* 和真卡片一样的三个按钮，预览里按不了 */}
          <div aria-hidden="true" className="flex items-center justify-center gap-6 opacity-35">
            {([['x', 'size-16 bg-surface text-ink'], ['heart', 'size-[4.5rem] bg-lime text-on-accent'], ['star', 'size-16 bg-butter text-on-accent']] as [IconName, string][]).map(([icon, colors]) => (
              <span key={icon} className={`grid place-items-center rounded-full border-2 border-stroke ${colors}`}>
                <Icon name={icon} className="size-7" />
              </span>
            ))}
          </div>
          <p className="text-center text-footnote font-bold text-ink-secondary">{t('This is the card others see on Discover')}</p>
        </div>
      ) : (
        <>
          <Photos profile={profile} patch={patch} />
          <section aria-labelledby="card-colors" className="grid gap-2">
            <h2 id="card-colors" className="px-1 text-footnote font-bold text-ink-secondary">{t('Card color without a photo')}</h2>
            <CardColors profile={profile} onChange={onChange} labelledBy="card-colors" />
          </section>
          <Group title={t('Profile')}>
            <Nickname profile={profile} onChange={onChange} />
            <Divider />
            <PreferredMode profile={profile} onChange={onChange} />
            <Divider />
            <div id="courts" className="scroll-mt-4">
              <Row icon="heart" tint="pink" title={t('Usual courts')} to="/courts/"
                   value={courts?.length ? (courts.length > 1 ? `${courts[0].name} +${courts.length - 1}` : courts[0].name) : undefined} />
            </div>
          </Group>
          <FreeTimes profile={profile} onChange={onChange} />
          <Group title={t('Levels')}>
            <div className="py-3">
              <GenderField value={profile.gender} onChange={(gender) => gender !== profile.gender && void save(profile, onChange, { gender })} />
            </div>
          </Group>
        </>
      )}
    </div>
  );
}

/** 改一项资料：先显示，存不上就退回 */
async function save(profile: Profile, onChange: (p: Profile) => void, change: Partial<Profile>) {
  onChange({ ...profile, ...change });
  const { data, error } = await supabase!.from('profiles').update(change).eq('id', profile.id).select().single();
  if (error) {
    onChange(profile);
    return toast(t('Couldn’t save. Try again.'), 'error');
  }
  onChange(data as Profile);
}

/** 两个照片格子：大的是卡片照片（600×800，3:4），小的是头像（320×320，正方形，和卡片顶端对齐），两张图分开存。
 *  一次只传一张：两张同时传时，清理文件夹会删掉另一张刚传上去的 */
function Photos({ profile, patch }: { profile: Profile; patch: (p: Partial<Profile>) => void }) {
  const [busy, setBusy] = useState<'card' | 'avatar'>();
  return (
    <section id="photos" aria-labelledby="photos-title" className="grid scroll-mt-4 gap-2">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 px-1">
        <h2 id="photos-title" className="text-footnote font-bold text-ink-secondary">{t('Photos')}</h2>
        <p className="text-caption text-ink-tertiary">{t('Card photo and profile photo are separate')}</p>
      </div>
      <div className="grid grid-cols-[2fr_1fr] items-start gap-3">
        <PhotoSlot kind="card" profile={profile} patch={patch} busy={busy} setBusy={setBusy} />
        <PhotoSlot kind="avatar" profile={profile} patch={patch} busy={busy} setBusy={setBusy} />
      </div>
    </section>
  );
}

function PhotoSlot({ kind, profile, patch, busy, setBusy }: {
  kind: 'card' | 'avatar';
  profile: Profile;
  patch: (p: Partial<Profile>) => void;
  busy?: 'card' | 'avatar';
  setBusy: (kind?: 'card' | 'avatar') => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [picked, setPicked] = useState<ImageBitmap>();
  const [menu, setMenu] = useState(false);
  const path = kind === 'card' ? profile.card_photo_path : profile.avatar_path;
  const key = kind === 'card' ? 'card_photo_path' : 'avatar_path';
  const name = kind === 'card' ? t('Card photo') : t('Profile photo');
  const titleId = `${kind}-photo-title`;

  async function pick(file: File) {
    setMenu(false);
    try {
      setPicked(await decode(file));
    } catch {
      toast(t('Couldn’t upload the photo. Try another one.'), 'error');
    }
  }

  function close() {
    picked?.close();
    setPicked(undefined);
  }

  async function upload(jpeg: Blob) {
    close();
    if (busy) return;
    setBusy(kind);
    try {
      patch({ [key]: await (kind === 'card' ? uploadCardPhoto : uploadAvatar)(profile, jpeg) });
      toast(kind === 'card' ? t('Card background updated') : t('Photo updated'));
    } catch {
      toast(t('Couldn’t upload the photo. Try another one.'), 'error');
    }
    setBusy(undefined);
  }

  async function remove() {
    setMenu(false);
    setBusy(kind);
    try {
      await removePhoto(profile, kind);
      patch({ [key]: null });
    } catch (error) {
      toast(problem(error as { message: string }), 'error');
    }
    setBusy(undefined);
  }

  const choose = (
    <input ref={input} type="file" accept="image/*" className="sr-only" tabIndex={-1} aria-hidden="true"
           onChange={(e) => { const file = e.target.files?.[0]; e.target.value = ''; if (file) void pick(file); }} />
  );
  const person: CardPerson = { id: profile.id, nickname: profile.nickname, tag: profile.tag, rating: profile.rating, avatar: profile.avatar_path, card_color: profile.card_color, card_photo: profile.card_photo_path };
  const layer = 'col-start-1 row-start-1';

  return (
    <>
      <button type="button" aria-label={name} aria-haspopup={path ? 'dialog' : undefined} disabled={Boolean(busy)}
              onClick={() => (path ? setMenu(true) : input.current?.click())}
              className={`press relative grid overflow-hidden rounded-[16px] border-2 border-stroke bg-surface-muted disabled:cursor-wait ${kind === 'card' ? 'aspect-[3/4]' : 'aspect-square'} ${busy === kind ? 'opacity-60' : ''}`}>
        {kind === 'card'
          ? <CardCover person={person} className={`${layer} size-full`} />
          : path && <img src={avatarUrl(path)} alt="" draggable={false} className={`${layer} size-full object-cover`} />}
        {!path && (
          <span className={`${layer} m-auto grid size-11 place-items-center rounded-full border-2 border-stroke bg-surface text-ink`}>
            <Icon name="plus" className="size-5" />
          </span>
        )}
        <span className="absolute bottom-2 left-2 rounded-full border-2 border-stroke bg-surface px-2 py-px text-caption font-black text-ink">
          {kind === 'card' ? t('Card') : t('Avatar')}
        </span>
      </button>
      {choose}
      <Sheet open={menu} onClose={() => setMenu(false)} labelledBy={titleId}>
        <h2 id={titleId} className="text-title3">{name}</h2>
        <label className="button button-lg w-full cursor-pointer">
          {t('Change photo')}
          <input type="file" accept="image/*" className="sr-only"
                 onChange={(e) => { const file = e.target.files?.[0]; e.target.value = ''; if (file) void pick(file); }} />
        </label>
        <Button className="button-lg w-full" variant="quiet" onClick={remove}>{t('Remove photo')}</Button>
        <Button className="button-lg w-full" variant="quiet" onClick={() => setMenu(false)}>{t('Cancel')}</Button>
      </Sheet>
      {picked && <AvatarCrop image={picked} card={kind === 'card'} onDone={upload} onCancel={close} />}
    </>
  );
}

/** 昵称：一行，点开半屏改 */
function Nickname({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const [open, setOpen] = useState(false);
  const [nickname, setNickname] = useState(profile.nickname);
  const [busy, setBusy] = useState(false);
  const issue = nicknameProblem(nickname);
  const changed = nickname.trim() !== profile.nickname;

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!changed) return setOpen(false);
    if (issue) return;
    setBusy(true);
    const { data, error } = await supabase!.from('profiles').update({ nickname: nickname.trim() }).eq('id', profile.id).select().single();
    setBusy(false);
    if (error) return toast(error.message === 'objectionable_content' ? problem(error) : t('Couldn’t save your nickname. Try again.'), 'error');
    onChange(data as Profile);
    setOpen(false);
    toast(t('Saved'));
  }

  return (
    <>
      <Row icon="user" tint="lavender" title={t('Nickname')} value={profile.nickname} onClick={() => { setNickname(profile.nickname); setOpen(true); }} />
      <Sheet open={open} onClose={() => setOpen(false)} labelledBy="nickname-title">
        <h2 id="nickname-title" className="sr-only">{t('Nickname')}</h2>
        <form onSubmit={submit} noValidate className="grid gap-4">
          <Field label={t('Nickname')} hint={t('2–12 characters. No phone numbers or links.')} error={changed ? issue : undefined}>
            {(props) => <input {...props} maxLength={12} value={nickname} onChange={(e) => setNickname(e.target.value)} className="field" />}
          </Field>
          <Button className="button-lg w-full" busy={busy} disabled={changed && Boolean(issue)}>{t('Save')}</Button>
          <Button type="button" className="button-lg w-full" variant="quiet" onClick={() => setOpen(false)}>{t('Cancel')}</Button>
        </form>
      </Sheet>
    </>
  );
}

/** 常打：单打、双打或都行（null，和 iOS 一样）。卡片上显示，按项目筛选时也用 */
function PreferredMode({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const current = profile.preferred_mode ?? null;
  const pick = (mode: Mode | null) => mode !== current && void save(profile, onChange, { preferred_mode: mode });
  return (
    <div id="mode" className="flex min-h-14 scroll-mt-4 flex-wrap items-center gap-x-3 gap-y-2 py-2.5">
      <IconTile icon="court" tint="lime" size="sm" />
      <span id="mode-label" className="min-w-0 flex-1 font-bold max-[379px]:text-subhead">{t('Usually play')}</span>
      <div role="radiogroup" aria-labelledby="mode-label" className="flex gap-2">
        {([['singles', t('Singles')], ['doubles', t('Doubles')], [null, t('Either')]] as const).map(([mode, label]) => (
          <button key={label} type="button" role="radio" aria-checked={current === mode} onClick={() => pick(mode)} className="toggle">
            {label}
          </button>
        ))}
      </div>
    </div>
  );
}

/** 空闲时间：星期几 + 时间段，最多 5 段，每段 1–8 小时（和 iOS、服务器一致）。显示在卡片上，别人点一下就能约。
 *  改了马上存（离开页面不会丢）；连着改时只用最后一次的结果 */
function FreeTimes({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const [rows, setRows] = useState<UsualTime[]>(() => sortUsual(profile.usual_times));
  const last = useRef(0);
  const halfHours = (from: number, to: number) => Array.from({ length: (to - from) / 30 + 1 }, (_, i) => from + i * 30);

  async function update(next: UsualTime[]) {
    const before = rows;
    setRows(next);
    const usual_times = sortUsual(next);
    const request = ++last.current;
    const { data, error } = await supabase!.from('profiles').update({ usual_times }).eq('id', profile.id).select().single();
    if (request !== last.current) return;
    if (error) {
      setRows(before);
      return toast(t('Couldn’t save. Try again.'), 'error');
    }
    onChange(data as Profile);
  }
  const set = (i: number, patch: Partial<UsualTime>) => void update(rows.map((r, j) => (j === i ? { ...r, ...patch } : r)));

  return (
    <Group title={t('Free times')} id="free-times">
      <div className="grid gap-3 py-3.5">
        <p className="text-footnote text-ink-secondary">{t('Shown on your card. Players can tap one to invite you.')}</p>
        {rows.map((row, i) => (
          <div key={i} className="flex flex-wrap items-center gap-2">
            <select className="field w-auto" aria-label={t('Day')} value={row.weekday} onChange={(e) => set(i, { weekday: Number(e.target.value) })}>
              {[2, 3, 4, 5, 6, 7, 1].map((w) => <option key={w} value={w}>{weekdayShort(w)}</option>)}
            </select>
            <select className="field w-auto" aria-label={t('From')} value={toMinutes(row.start)}
                    onChange={(e) => { const from = Number(e.target.value); set(i, { start: toHHMM(from), end: toHHMM(Math.min(Math.max(toMinutes(row.end), from + 60), from + 480, 1440)) }); }}>
              {halfHours(360, 1380).map((m) => <option key={m} value={m}>{clock(m)}</option>)}
            </select>
            <span aria-hidden="true">–</span>
            <select className="field w-auto" aria-label={t('To')} value={toMinutes(row.end)} onChange={(e) => set(i, { end: toHHMM(Number(e.target.value)) })}>
              {halfHours(toMinutes(row.start) + 60, Math.min(toMinutes(row.start) + 480, 1440)).map((m) => <option key={m} value={m}>{clock(m)}</option>)}
            </select>
            <IconButton icon="trash" label={t('Delete')} onClick={() => void update(rows.filter((_, j) => j !== i))} />
          </div>
        ))}
        {rows.length < 5 && (
          <Button className="button-sm justify-self-start" variant="quiet" onClick={() => void update([...rows, { weekday: [7, 1, 6, 5, 4, 3, 2].find((w) => !rows.some((r) => r.weekday === w)) ?? 7, start: '14:00', end: '18:00' }])}>
            <Icon name="plus" className="size-4" />{t('Add a time')}
          </Button>
        )}
      </div>
    </Group>
  );
}
