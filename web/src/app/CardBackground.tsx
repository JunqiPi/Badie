import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { AvatarCrop, decode } from './AvatarCrop';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { Avatar, IconButton } from './kit';
import { CARD_COLORS, CardCover, DayCard, cardColorName, cardColorOf, type CardColor, type CardPerson } from './PlayerCard';
import { cleanPhotoFolder, supabase, tagText, useLive, type Profile, type Ticket } from './supabase';
import { timeOf } from './time';
import { Button, toast } from './ui';

/** 传一张卡片背景照片（已裁好的 JPEG）：先传新的、换上，再删旧的。返回新照片的位置，失败时抛错 */
export async function uploadCardPhoto(profile: Profile, jpeg: Blob) {
  await cleanPhotoFolder(profile.id, [profile.avatar_path, profile.card_photo_path]).catch(() => {});
  const path = `${profile.id}/${crypto.randomUUID()}.jpg`;
  const { error: uploadError } = await supabase!.storage.from('avatars').upload(path, jpeg, { contentType: 'image/jpeg' });
  if (uploadError) throw uploadError;
  const { error } = await supabase!.rpc('set_card_photo', { p_path: path });
  if (error) {
    await supabase!.storage.from('avatars').remove([path]);
    throw error;
  }
  if (profile.card_photo_path) await supabase!.storage.from('avatars').remove([profile.card_photo_path]);
  return path;
}

/** 卡片背景（iOS 编辑资料里的同一块）：别人在首页刷到你时看到的卡片。
 *  背景照片和头像分开：裁成 600×800 的竖图，先传新的、换上，再删旧的；没传照片就用选的颜色 */
export function CardBackground({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const [busy, setBusy] = useState(false);
  const [picked, setPicked] = useState<ImageBitmap>();
  const [previewing, setPreviewing] = useState(false);
  const person: CardPerson = {
    id: profile.id, nickname: profile.nickname, tag: profile.tag, rating: profile.rating,
    avatar: profile.avatar_path, card_color: profile.card_color, card_photo: profile.card_photo_path,
  };
  const current = cardColorOf(profile.id, profile.card_color);

  async function pick(file: File) {
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
    setBusy(true);
    try {
      onChange({ ...profile, card_photo_path: await uploadCardPhoto(profile, jpeg) });
      toast(t('Card background updated'));
    } catch {
      toast(t('Couldn’t upload the photo. Try another one.'), 'error');
    }
    setBusy(false);
  }

  async function remove() {
    setBusy(true);
    const { error } = await supabase!.rpc('set_card_photo', { p_path: null });
    if (!error && profile.card_photo_path) await supabase!.storage.from('avatars').remove([profile.card_photo_path]);
    setBusy(false);
    if (error) return toast(t('Couldn’t save. Try again.'), 'error');
    onChange({ ...profile, card_photo_path: null });
  }

  async function choose(color: CardColor) {
    if (color === current && profile.card_color) return;
    onChange({ ...profile, card_color: color });
    const { error } = await supabase!.from('profiles').update({ card_color: color }).eq('id', profile.id);
    if (error) {
      onChange(profile);
      toast(t('Couldn’t save. Try again.'), 'error');
    }
  }

  return (
    <section aria-labelledby="card-background" className="sticker grid gap-4 p-5">
      <h2 id="card-background" className="text-headline">{t('Card background')}</h2>

      {/* 小卡片：改了马上看到 */}
      <div aria-hidden="true" className="overflow-hidden rounded-[16px] border-2 border-stroke bg-surface">
        <CardCover person={person} className={`h-32 ${busy ? 'opacity-60' : ''}`} />
        <div className="relative flex min-w-0 items-center gap-2 px-3 py-2">
          {person.card_photo && <Avatar id={person.id} name={person.nickname} photo={person.avatar} size={40} className="absolute -top-6 left-3" />}
          <p className={`flex min-w-0 font-bold ${person.card_photo ? 'pt-4' : ''}`}>
            <span className="truncate">{person.nickname}</span>
            {person.tag != null && <span className="shrink-0 text-ink-tertiary">{tagText(person.tag)}</span>}
          </p>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <label className={`button button-sm cursor-pointer ${busy ? 'pointer-events-none opacity-60' : ''}`}>
          {t('Upload photo')}
          <input type="file" accept="image/*" className="sr-only" disabled={busy}
                 onChange={(e) => { const file = e.target.files?.[0]; e.target.value = ''; if (file) void pick(file); }} />
        </label>
        <Button type="button" className="button-sm" variant="quiet" onClick={() => setPreviewing(true)}>{t('Preview')}</Button>
        {person.card_photo && <Button type="button" className="button-sm" variant="quiet" busy={busy} onClick={remove}>{t('Remove background photo')}</Button>}
      </div>

      {!person.card_photo && (
        <div className="grid gap-1.5">
          <p id="card-colors" className="text-caption text-ink-secondary">{t('Without a photo, your card uses this color')}</p>
          <div role="radiogroup" aria-labelledby="card-colors" className="flex flex-wrap">
            {CARD_COLORS.map((color) => (
              <button key={color} type="button" role="radio" aria-checked={color === current} aria-label={cardColorName(color)} title={cardColorName(color)}
                      onClick={() => void choose(color)} className="grid size-11 place-items-center rounded-full">
                <span className={`grid size-[2.375rem] place-items-center rounded-full border-[2.5px] ${color === current ? 'border-ink' : 'border-transparent'}`}>
                  <span className={`size-7 rounded-full border-2 border-stroke ${SWATCH[color]}`} />
                </span>
              </button>
            ))}
          </div>
        </div>
      )}

      {picked && <AvatarCrop image={picked} card onDone={upload} onCancel={close} />}
      {previewing && <MyCardPreview person={person} onClose={() => setPreviewing(false)} />}
    </section>
  );
}

const SWATCH: Record<CardColor, string> = {
  lime: 'bg-lime', lavender: 'bg-lavender', peach: 'bg-peach', sky: 'bg-sky', pink: 'bg-pink', mint: 'bg-mint', butter: 'bg-butter', ink: 'bg-[#17140f]',
};

/** 全屏看自己的卡片：和别人在首页刷到的一样。时间地点用我下一个约球请求的，没有就用示例 */
function MyCardPreview({ person, onClose }: { person: CardPerson; onClose: () => void }) {
  const { data: requests } = useLive<Ticket[]>('my_matchmaking');
  const title = useRef<HTMLHeadingElement>(null);
  const next = requests
    ?.filter((r) => (r.status === 'searching' || r.status === 'offered') && new Date(r.ends_at).getTime() > Date.now())
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at))[0];
  const evening = new Date();
  evening.setHours(19, 0, 0, 0);
  const starts = next?.starts_at ?? evening.toISOString();
  const ends = next?.ends_at ?? new Date(evening.getTime() + 2 * 3600000).toISOString();
  const doubles = next?.mode === 'doubles';

  // 全屏：底下的页面不滚动，焦点放到标题上，Esc 关闭
  useEffect(() => {
    const root = document.documentElement;
    const before = root.style.overflow;
    root.style.overflow = 'hidden';
    title.current?.focus();
    const onKey = (event: KeyboardEvent) => event.key === 'Escape' && onClose();
    document.addEventListener('keydown', onKey);
    return () => {
      root.style.overflow = before;
      document.removeEventListener('keydown', onKey);
    };
  }, []);

  return createPortal(
    <div role="dialog" aria-modal="true" aria-labelledby="my-card-title" className="fixed inset-0 z-40 flex flex-col bg-canvas text-ink">
      <header className="mx-auto flex w-full max-w-xl items-start gap-3 px-[var(--gutter)] pt-[calc(1rem+env(safe-area-inset-top))]">
        <div className="min-w-0 flex-1">
          <h1 id="my-card-title" ref={title} tabIndex={-1} className="text-title2 outline-none">{t('My card')}</h1>
          <p className="text-footnote font-bold text-ink-secondary">{t('This is what others see')}</p>
        </div>
        <IconButton icon="x" label={t('Close')} onClick={onClose} />
      </header>
      <div className="mx-auto min-h-0 w-full max-w-md flex-1 px-[var(--gutter)] py-4">
        <DayCard
          person={person}
          label={`${timeOf(starts)}–${timeOf(ends)} · ${doubles ? t('Doubles') : t('Singles')}`}
          details={next ? next.venues.slice(0, 2).map((v) => v.name) : [t('A court nearby')]}
        />
      </div>
      {/* 和真卡片一样的三个按钮，预览里按不了 */}
      <div aria-hidden="true" className="flex items-center justify-center gap-6 px-[var(--gutter)] pt-1 pb-[calc(1.25rem+env(safe-area-inset-bottom))] opacity-35">
        {([['x', 'size-16 bg-surface text-ink'], ['heart', 'size-[4.5rem] bg-lime text-on-accent'], ['star', 'size-16 bg-butter text-on-accent']] as [IconName, string][]).map(([icon, colors]) => (
          <span key={icon} className={`grid place-items-center rounded-full border-2 border-stroke ${colors}`}>
            <Icon name={icon} className="size-7" />
          </span>
        ))}
      </div>
    </div>,
    document.body,
  );
}
