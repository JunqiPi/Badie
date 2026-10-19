// 浏览器推送：在“设置”里打开，或者发出约球请求后提示一次。浏览器支持、网站配了 VAPID 公钥时才出现
import { supabase } from './supabase';

const vapidKey = import.meta.env.PUBLIC_VAPID_KEY as string | undefined;

/** on / off；blocked：用户在浏览器里拒绝过；install：iPhone 上要先添加到主屏幕；unsupported：不支持 */
export type PushState = 'on' | 'off' | 'blocked' | 'install' | 'unsupported';

const supported = () => Boolean(vapidKey) && 'serviceWorker' in navigator && 'Notification' in window && 'PushManager' in window;
const fromBase64url = (text: string) => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
const subscription = async () => (await navigator.serviceWorker.getRegistration())?.pushManager.getSubscription() ?? null;

export async function pushState(): Promise<PushState> {
  if (!supported()) return vapidKey && /iPhone|iPad|iPod/.test(navigator.userAgent) ? 'install' : 'unsupported';
  if (Notification.permission === 'denied') return 'blocked';
  return (await subscription()) ? 'on' : 'off';
}

async function save(current: PushSubscription) {
  const { endpoint, keys } = current.toJSON();
  const { error } = await supabase!.rpc('register_push', { p_kind: 'web', p_token: endpoint, p_keys: keys });
  if (error) throw error;
}

/** 打开：要通知权限 → 订阅 → 告诉服务器这台设备 */
export async function enablePush(): Promise<PushState> {
  if ((await Notification.requestPermission()) !== 'granted') return pushState();
  const registration = await navigator.serviceWorker.register('/sw.js');
  await navigator.serviceWorker.ready;
  const current = (await registration.pushManager.getSubscription())
    ?? (await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: fromBase64url(vapidKey!) }));
  await save(current);
  return 'on';
}

/** 关掉，或者退出登录：服务器上删掉这台设备，浏览器也退订 */
export async function disablePush() {
  if (!supported()) return;
  const current = await subscription();
  if (!current) return;
  await supabase!.rpc('unregister_push', { p_token: current.endpoint });
  await current.unsubscribe();
}

/** 每次打开：订阅过的再报一次（换了账号登录，或者服务器删过时补上） */
export async function syncPush() {
  if (!supported() || Notification.permission !== 'granted') return;
  const current = await subscription();
  if (current) await save(current).catch(() => {});
}
