// 安卓 App 的安装包（从网站直接下载，还没上 Google Play）：发版工作流把它发到 GitHub Release，
// 网站构建前（web.yml）下载到 public/android/，构建时 astro.config.ts 读 version.json 放进 PUBLIC_ANDROID_APP。
// 没有安装包时为 null，各处退回“添加到主屏幕”
import { currentLocale, pathPrefixes } from './i18n';

export type AndroidApp = { versionCode: number; versionName: string; url: string; sha256: string; minSdk: number; size: number };

function read(): AndroidApp | null {
  try {
    const raw = import.meta.env.PUBLIC_ANDROID_APP as string | undefined;
    return raw ? (JSON.parse(raw) as AndroidApp) : null;
  } catch {
    return null;
  }
}

export const androidApp = read();

/** 下载地址（同一个网站下，Cloudflare Pages 按附件下载） */
export const ANDROID_APK = '/android/badie.apk';

/** 安装包大小，按 MB 显示一位小数 */
export const megabytes = (bytes: number) => (bytes / 1048576).toFixed(1);

/** 安卓 App 的介绍页，跟着当前语言 */
export const androidPage = () => `${pathPrefixes[currentLocale()]}/android/`;

/** 装安卓 App 的三步（打开下载的文件、允许浏览器安装应用、点安装）：下载后的面板和 /android/ 页面共用。t 是这一处用的翻译函数 */
export const androidSteps = (t: (key: string) => string) => [
  t('When the download finishes, open badie.apk. If your browser asks, keep the file.'),
  t('If Android says it can’t install apps from this source, tap Settings, turn on Allow from this source, then go back.'),
  t('Tap Install.'),
];
