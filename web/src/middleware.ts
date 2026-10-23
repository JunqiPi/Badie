import { defineMiddleware } from 'astro:middleware';
import { localizeHtml, pageLocale } from './lib/static-i18n';

// 中文版静态页面（/zh/…）：构建时把页面里标了 data-t 的英文换成中文
export const onRequest = defineMiddleware(async ({ url }, next) => {
  const response = await next();
  const locale = pageLocale(url.pathname);
  if (locale === 'en' || !response.headers.get('content-type')?.includes('text/html')) return response;
  return new Response(localizeHtml(await response.text(), locale), response);
});
