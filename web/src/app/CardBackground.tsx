import { t } from './i18n';
import { CARD_COLORS, cardColorName, cardColorOf, type CardColor } from './PlayerCard';
import { cleanPhotoFolder, supabase, type Profile } from './supabase';
import { toast } from './ui';

// 卡片照片和头像：两张图分开存（都在 avatars 桶里）。卡片照片裁成 600×800，头像裁成 320×320

/** 传一张照片（已裁好的 JPEG）：先传新的、换上，再删旧的。返回新照片的位置，失败时抛错 */
async function uploadPhoto(profile: Profile, jpeg: Blob, kind: 'card' | 'avatar') {
  await cleanPhotoFolder(profile.id, [profile.avatar_path, profile.card_photo_path]).catch(() => {});
  const path = `${profile.id}/${crypto.randomUUID()}.jpg`;
  const { error: uploadError } = await supabase!.storage.from('avatars').upload(path, jpeg, { contentType: 'image/jpeg' });
  if (uploadError) throw uploadError;
  const { error } = await supabase!.rpc(kind === 'card' ? 'set_card_photo' : 'set_avatar', { p_path: path });
  if (error) {
    await supabase!.storage.from('avatars').remove([path]);
    throw error;
  }
  const old = kind === 'card' ? profile.card_photo_path : profile.avatar_path;
  if (old) await supabase!.storage.from('avatars').remove([old]);
  return path;
}

export const uploadCardPhoto = (profile: Profile, jpeg: Blob) => uploadPhoto(profile, jpeg, 'card');
export const uploadAvatar = (profile: Profile, jpeg: Blob) => uploadPhoto(profile, jpeg, 'avatar');

/** 撤下卡片照片或头像：先解除引用，再删文件。失败时抛错 */
export async function removePhoto(profile: Profile, kind: 'card' | 'avatar') {
  const { error } = await supabase!.rpc(kind === 'card' ? 'set_card_photo' : 'set_avatar', { p_path: null });
  if (error) throw error;
  const old = kind === 'card' ? profile.card_photo_path : profile.avatar_path;
  if (old) await supabase!.storage.from('avatars').remove([old]);
}

const SWATCH: Record<CardColor, string> = {
  lime: 'bg-lime', lavender: 'bg-lavender', peach: 'bg-peach', sky: 'bg-sky', pink: 'bg-pink', mint: 'bg-mint', butter: 'bg-butter', ink: 'bg-[#17140f]',
};

/** 没照片时卡片用的颜色（8 种）：点一下马上存，失败就退回 */
export function CardColors({ profile, onChange, labelledBy }: { profile: Profile; onChange: (p: Profile) => void; labelledBy: string }) {
  const current = cardColorOf(profile.id, profile.card_color);

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
    <div role="radiogroup" aria-labelledby={labelledBy} className="-mx-1 flex flex-wrap">
      {CARD_COLORS.map((color) => (
        <button key={color} type="button" role="radio" aria-checked={color === current} aria-label={cardColorName(color)} title={cardColorName(color)}
                onClick={() => void choose(color)} className="grid size-10 place-items-center rounded-full sm:size-11">
          <span className={`grid size-[2.375rem] place-items-center rounded-full border-[2.5px] ${color === current ? 'border-ink' : 'border-transparent'}`}>
            <span className={`size-7 rounded-full border-2 border-stroke ${SWATCH[color]}`} />
          </span>
        </button>
      ))}
    </div>
  );
}
