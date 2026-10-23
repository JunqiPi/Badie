import { useSyncExternalStore } from 'react';

// 界面文字：英文原文就是 key（和 iOS 用中文原文作 key 一样），其他语言放在 locales/<语言>.json，用到时才加载。
// 支持的语言与 iOS 一致

export const languages = [
  ['en', 'English'],
  ['zh-Hans', '简体中文'],
  ['zh-Hant', '繁體中文'],
  ['ja', '日本語'],
  ['ko', '한국어'],
  ['id', 'Bahasa Indonesia'],
  ['ms', 'Bahasa Melayu'],
  ['th', 'ไทย'],
  ['vi', 'Tiếng Việt'],
  ['hi', 'हिन्दी'],
] as const;
export type Locale = (typeof languages)[number][0];

const storageKey = 'badie-language';
let locale: Locale = 'en';
let messages: Record<string, string> = {};
const listeners = new Set<() => void>();

function match(tag: string): Locale | undefined {
  const lower = tag.toLowerCase();
  if (lower.startsWith('zh')) return /hant|-tw|-hk|-mo/.test(lower) ? 'zh-Hant' : 'zh-Hans';
  return languages.find(([code]) => code === lower.split('-')[0])?.[0];
}

/** 中文版的静态页面（/zh/…）固定用中文；其他页面用用户选过的语言，否则按浏览器语言，都不支持时用英文 */
export function detect(): Locale {
  if (document.documentElement.dataset.fixedLocale) return document.documentElement.dataset.fixedLocale as Locale;
  try {
    const saved = localStorage.getItem(storageKey) as Locale | null;
    if (saved && languages.some(([code]) => code === saved)) return saved;
  } catch {
    // 隐私模式等情况下读不了本地存储，按浏览器语言处理
  }
  for (const tag of navigator.languages ?? [navigator.language]) {
    const found = match(tag);
    if (found) return found;
  }
  return 'en';
}

export async function setLocale(next: Locale, remember = false) {
  messages = next === 'en' ? {} : (await import(`./locales/${next}.json`)).default;
  locale = next;
  document.documentElement.lang = next;
  if (remember) rememberLocale(next);
  listeners.forEach((notify) => notify());
}

/** 记住用户选的语言（存不下就只在这次打开时生效） */
export function rememberLocale(next: Locale) {
  try {
    localStorage.setItem(storageKey, next);
  } catch {
    // 隐私模式等情况下存不了
  }
}

export const currentLocale = () => locale;

/** 第一次打开：按存过的选择或浏览器语言加载（App 和静态页上的顶栏共用，只加载一次） */
let starting: Promise<void> | undefined;
export const startLocale = () => (starting ??= setLocale(detect()).catch(() => undefined));

/** 语言变了就重新渲染 */
export function useLocale() {
  return useSyncExternalStore(
    (notify) => {
      listeners.add(notify);
      return () => listeners.delete(notify);
    },
    () => locale,
    () => 'en' as Locale,
  );
}

/**
 * t('Courts near {place}', { place })。
 * 单复数写成 '{n} game|{n} games'，按 n 和当前语言的规则选；不分单复数的语言只写一种
 */
export function t(key: string, params?: Record<string, string | number>) {
  return format(messages[key] || key, params, locale);
}

/** 选单复数、填参数（静态页面构建时也用） */
export function format(text: string, params: Record<string, string | number> | undefined, language: string) {
  if (text.includes('|')) {
    const forms = text.split('|');
    const one = new Intl.PluralRules(language).select(Number(params?.n ?? 0)) === 'one';
    text = forms[one ? 0 : forms.length - 1];
  }
  return params ? text.replace(/\{(\w+)\}/g, (whole, name) => (name in params ? String(params[name]) : whole)) : text;
}
