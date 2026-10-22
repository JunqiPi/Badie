import type { APIRoute } from 'astro';

// 搜索引擎和 AI（搜索和训练）都可以看公开页面：新品牌要让 ChatGPT、Gemini、Claude 这些先认识 Badie。
// 要登录的个人页面不用抓
const privatePaths = ['/app/', '/captcha/', '/signin/', '/play/', '/games/', '/rooms/', '/groups/', '/join/', '/challenges/', '/rankings/', '/messages/', '/notifications/', '/players/', '/me/', '/settings/', '/verification/', '/level-quiz/', '/admin/'];

export const GET: APIRoute = ({ site }) =>
  new Response(
    [
      `User-agent: *\nAllow: /\n${privatePaths.map((path) => `Disallow: ${path}\n`).join('')}`,
      `Sitemap: ${new URL('/sitemap-index.xml', site)}\n`,
    ].join('\n'),
  );
