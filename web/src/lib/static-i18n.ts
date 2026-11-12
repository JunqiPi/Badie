// 静态页面的各语言版本（/zh/…、/ja/…）：搜索引擎和 AI 只读得到服务器给的文字，浏览器里切语言它们看不到，所以译文要在构建时就写进页面。
// 页面照常用英文写，要翻译的文字标 data-t（和浏览器里切语言用的是同一套标记和译文），构建时由 middleware 换成这种语言；
// 标题、描述这类不在正文里的文字用 translator() 翻。
// 首页、等级表和每一档的页面有 10 种语言；关于页和球馆目录只有英文和简体中文
import { format, pathPrefixes, type Locale } from '../app/i18n';
import zhHans from '../app/locales/zh-Hans.json';
import zhHant from '../app/locales/zh-Hant.json';
import ja from '../app/locales/ja.json';
import ko from '../app/locales/ko.json';
import id from '../app/locales/id.json';
import ms from '../app/locales/ms.json';
import th from '../app/locales/th.json';
import vi from '../app/locales/vi.json';
import hi from '../app/locales/hi.json';

const catalogs: Record<Locale, Record<string, string>> = { en: {}, 'zh-Hans': zhHans, 'zh-Hant': zhHant, ja, ko, id, ms, th, vi, hi };

/** 球馆目录的语言前缀（[...lang]）：英文没有前缀，中文是 /zh/ */
export const languages = [undefined, 'zh'] as const;

/** 10 种语言的前缀（不含英文）：zh、zh-hant、ja、ko…… */
export const prefixes = Object.values(pathPrefixes).filter(Boolean).map((p) => p.slice(1));
/** [...lang] 路由用：英文（没有前缀）加 9 种语言 */
export const allLanguages = [undefined, ...prefixes];

const localeOfPrefix = Object.fromEntries(Object.entries(pathPrefixes).map(([locale, prefix]) => [prefix.slice(1), locale as Locale]));
const prefixPattern = new RegExp(`^/(${[...prefixes].sort((a, b) => b.length - a.length).join('|')})(?=/)`);

/** 有 10 种语言的页面：首页、等级表、每一档的页面 */
const everyLanguage = /^\/(?:$|levels\/)/;
/** 只有英文和简体中文的页面：关于、球馆目录 */
const chineseOnly = /^\/(?:about\/|courts\/)/;

/** 页面语言：按地址前缀，没有前缀是英文 */
export const pageLocale = (pathname: string): Locale => localeOfPrefix[pathname.match(prefixPattern)?.[1] ?? ''] ?? 'en';

/** 去掉语言前缀，得到英文版的路径 */
export const englishPath = (pathname: string) => pathname.replace(prefixPattern, '');

/** 这个页面有哪些语言 */
export const localesOf = (english: string): Locale[] =>
  everyLanguage.test(english) ? (Object.keys(pathPrefixes) as Locale[]) : chineseOnly.test(english) ? ['en', 'zh-Hans'] : [];

/** 某种语言的地址 */
export const pathIn = (locale: Locale, english: string) => `${pathPrefixes[locale]}${english}`;

/** 同一页面的各语言版本（给 hreflang 用）；只有英文的页面为空 */
export function alternates(pathname: string, site: URL) {
  const english = englishPath(pathname);
  const locales = localesOf(english);
  if (!locales.length) return [];
  return [
    ...locales.map((locale) => ({ hreflang: locale, href: new URL(pathIn(locale, english), site).href })),
    { hreflang: 'x-default', href: new URL(english, site).href },
  ];
}

/** og:locale 的写法 */
export const ogLocale: Record<Locale, string> = {
  en: 'en_US', 'zh-Hans': 'zh_CN', 'zh-Hant': 'zh_TW', ja: 'ja_JP', ko: 'ko_KR', id: 'id_ID', ms: 'ms_MY', th: 'th_TH', vi: 'vi_VN', hi: 'hi_IN',
};

/** 把站内路径换成这个页面语言的版本（这种语言没有那一页就用英文的） */
export function localPath(pathname: string, path: string) {
  const locale = pageLocale(pathname);
  return locale !== 'en' && localesOf(path).includes(locale) ? pathIn(locale, path) : path;
}

/** 标题、描述等：t('Badminton courts in {place} — Badie', { place }) */
export function translator(pathname: string) {
  const locale = pageLocale(pathname);
  return (key: string, params?: Record<string, string | number>) => format(catalogs[locale][key] || key, params, locale);
}

/**
 * 搜索结果里标题太长会被截断（Bing 超过 70 个字符就报问题）：从长到短给几种写法，用第一个放得下的。
 * 中日韩文字一个字按两个英文字母宽度算
 */
export function fitTitle(...options: string[]) {
  const width = (text: string) => [...text].reduce((sum, char) => sum + (char.codePointAt(0)! >= 0x2e80 ? 2 : 1), 0);
  return options.find((title) => width(title) <= 65) ?? options.at(-1)!;
}

/** 国家或地区名，和浏览器里的规则一样：短名自然就用短名（香港、美国），短名是缩写就用全名 */
export function regionName(code: string, locale: string, english: string) {
  if (locale === 'en') return english;
  const name = new Intl.DisplayNames([locale], { type: 'region', style: 'short' }).of(code.toUpperCase()) ?? '';
  return /[.॰]|^[A-Z]+$/.test(name) ? (new Intl.DisplayNames([locale], { type: 'region' }).of(code.toUpperCase()) ?? english) : name;
}

const decode = (text: string) => text.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const encode = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const attributes = (tag: string) => Object.fromEntries([...tag.matchAll(/\sdata-([\w-]+)="([^"]*)"/g)].map(([, name, value]) => [name, decode(value)]));

/**
 * 构建时把英文页面换成这种语言：data-t 的文字、data-t-placeholder / data-t-label、data-region 的国家名，
 * 再把指向有这种语言版本的站内链接（包括地图上的链接）换到对应的前缀下
 */
export function localizeHtml(html: string, locale: Locale) {
  const t = (key: string, params?: Record<string, string>) => format(catalogs[locale][key] || key, params, locale);
  const sections = locale === 'zh-Hans' ? 'courts\\/|about\\/|levels\\/' : 'levels\\/';
  return html
    .replace(/<(\w+)(\s[^>]*?(?<=\s)data-t="[^"]*"[^>]*)>([^<]*)<\/\1>/g, (_, tag: string, attrs: string) => {
      const { t: key, ...rest } = attributes(attrs);
      // 数字按语言加千位分隔，和浏览器里一样
      const params = Object.fromEntries(
        Object.entries(rest)
          .filter(([name]) => !name.startsWith('t-') && name !== 'region')
          .map(([name, value]) => [name, /^\d+$/.test(value) ? Number(value).toLocaleString(locale) : value]),
      );
      return `<${tag}${attrs}>${encode(t(key, params))}</${tag}>`;
    })
    .replace(/<(\w+)(\s[^>]*?(?<=\s)data-region="(\w+)"[^>]*)>([^<]*)<\/\1>/g, (whole, tag: string, attrs: string, code: string, english: string) =>
      /\sdata-t="/.test(attrs) ? whole : `<${tag}${attrs}>${encode(regionName(code, locale, decode(english)))}</${tag}>`,
    )
    .replace(/<[^>]*\sdata-t-(?:placeholder|label)="[^"]*"[^>]*>/g, (tag) => {
      const { 't-placeholder': placeholder, 't-label': label } = attributes(tag);
      let out = tag;
      if (placeholder) out = out.replace(/\splaceholder="[^"]*"/, ` placeholder="${encode(t(placeholder))}"`);
      if (label) out = out.replace(/\saria-label="[^"]*"/, ` aria-label="${encode(t(label))}"`);
      return out;
    })
    .replace(new RegExp(`(\\s(?:href|action)="|&quot;)/(${sections})`, 'g'), `$1${pathPrefixes[locale]}/$2`);
}
