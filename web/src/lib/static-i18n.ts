// 静态页面的中文版（/zh/…）：搜索引擎和 AI 只读得到服务器给的文字，浏览器里切语言它们看不到，所以中文要在构建时就写进页面。
// 页面照常用英文写，要翻译的文字标 data-t（和浏览器里切语言用的是同一套标记和译文），构建时由 middleware 换成中文；
// 标题、描述这类不在正文里的文字用 translator() 翻
import { format } from '../app/i18n';
import zhHans from '../app/locales/zh-Hans.json';

/** 路由里的语言前缀（[...lang]）：英文没有前缀，中文是 /zh/ */
export const languages = [undefined, 'zh'] as const;

/** 有中文版的页面：首页、关于、等级表、球馆目录 */
const localized = /^\/(?:$|about\/|levels\/|courts\/)/;

/** 页面语言：/zh/ 开头的是简体中文 */
export const pageLocale = (pathname: string) => (pathname.startsWith('/zh/') ? 'zh-Hans' : 'en');

/** 去掉 /zh 前缀，得到英文版的路径 */
export const englishPath = (pathname: string) => pathname.replace(/^\/zh(?=\/)/, '');

/** 同一页面的各语言版本（给 hreflang 用）；没有中文版的页面为空 */
export function alternates(pathname: string, site: URL) {
  const english = englishPath(pathname);
  if (!localized.test(english)) return [];
  return [
    { hreflang: 'en', href: new URL(english, site).href },
    { hreflang: 'zh-Hans', href: new URL(`/zh${english}`, site).href },
    { hreflang: 'x-default', href: new URL(english, site).href },
  ];
}

/** 把站内路径换成这个页面语言的版本 */
export const localPath = (pathname: string, path: string) => (pageLocale(pathname) === 'en' || !localized.test(path) ? path : `/zh${path}`);

/** 标题、描述等：t('Badminton courts in {place} — Badie', { place }) */
export function translator(pathname: string) {
  const locale = pageLocale(pathname);
  const catalog: Record<string, string> = locale === 'en' ? {} : zhHans;
  return (key: string, params?: Record<string, string | number>) => format(catalog[key] || key, params, locale);
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
 * 构建时把英文页面换成中文：data-t 的文字、data-t-placeholder / data-t-label、data-region 的国家名，
 * 再把指向有中文版页面的站内链接（包括地图上的链接）换到 /zh/
 */
export function localizeHtml(html: string, locale: string) {
  const t = (key: string, params?: Record<string, string>) => format((zhHans as Record<string, string>)[key] || key, params, locale);
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
    .replace(/(\s(?:href|action)="|&quot;)\/(courts\/|about\/|levels\/)/g, '$1/zh/$2');
}
