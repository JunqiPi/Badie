import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import { movedPaths, noindexPaths } from './src/lib/venues';

// 安卓 App 的安装包：web.yml 在构建前从最新的安卓 Release 下载到 public/android/（见 src/app/androidApp.ts）。
// 有的话把 version.json 交给页面（PUBLIC_ 开头的环境变量浏览器里也能读），没有就不显示下载
const androidVersion = new URL('./public/android/version.json', import.meta.url);
if (existsSync(androidVersion) && existsSync(new URL('./public/android/badie.apk', import.meta.url))) {
  process.env.PUBLIC_ANDROID_APP = readFileSync(androidVersion, 'utf8');
}

const hidden = noindexPaths();
hidden.add('/captcha/');

// 网页应用只连自己的 Supabase 项目（本地开发 / CI 是本机的 Supabase）
const supabase = process.env.PUBLIC_SUPABASE_URL ? new URL(process.env.PUBLIC_SUPABASE_URL) : undefined;
const turnstile = 'https://challenges.cloudflare.com';
// 球馆地图的矢量瓦片、字体和图标（OpenFreeMap，免费、不用密钥）
const maps = 'https://tiles.openfreemap.org';
// 设密码时查是否泄露过（只发 SHA-1 前 5 位，见 src/app/password.ts）
const pwned = 'https://api.pwnedpasswords.com';
// 访问统计：Cloudflare Web Analytics（Pages 自动插入，不用 cookie、不识别个人）
const insights = 'https://static.cloudflareinsights.com';
const insightsReport = 'https://cloudflareinsights.com';

/**
 * 球馆目录改过城市的分法，旧的城市页、球馆页地址 301 到新地址（src/lib/venues.ts 的 movedPaths），英文和中文各一条。
 * 构建完接在 dist/_redirects 后面。Cloudflare Pages 最多 2,000 条固定跳转：超过时城市页优先，多出来的球馆页不跳（构建日志里写一句）
 */
function movedRedirects() {
  return {
    name: 'badie-moved-redirects',
    hooks: {
      'astro:build:done': ({ dir }: { dir: URL }) => {
        const file = new URL('_redirects', dir);
        const depth = (path: string) => path.split('/').length;
        const moves = movedPaths().sort((a, b) => depth(a[0]) - depth(b[0]));
        const lines = moves.flatMap(([from, to]) => ['', '/zh'].map((prefix) => `${encodeURI(prefix + from)} ${encodeURI(prefix + to)} 301`));
        const existing = existsSync(file) ? readFileSync(file, 'utf8').split('\n').filter((l) => l.trim() && !l.startsWith('#')).length : 0;
        const room = 2000 - existing;
        if (lines.length > room) console.warn(`[redirects] 旧地址 ${lines.length} 条，只放得下 ${room} 条，后面的球馆页不跳`);
        appendFileSync(file, `\n# 球馆目录改过城市的分法（构建时生成）\n${lines.slice(0, room).join('\n')}\n`);
      },
    },
  };
}

export default defineConfig({
  site: process.env.SITE_URL || 'http://localhost:4321',
  trailingSlash: 'always',
  devToolbar: { enabled: false },
  // 站点地图不收 noindex 的球馆目录页面和中文版球馆目录（各语言前缀和 src/app/i18n.ts 的 pathPrefixes 一致）
  integrations: [react(), movedRedirects(), sitemap({
    filter: (page) => {
      const path = decodeURIComponent(new URL(page).pathname);
      const english = path.replace(/^\/(?:zh-hant|zh|ja|ko|id|ms|th|vi|hi)(?=\/)/, '');
      // 不收录的球馆页、城市页、国家页不进；球馆目录的中文版也不进（只有英文版收录）
      return !hidden.has(english) && !(english !== path && english.startsWith('/courts/'));
    },
  })],
  vite: { plugins: [tailwindcss()] },
  // 内容安全策略：Astro 给页面里的每段脚本和样式算哈希，其他来源一律不许加载，XSS 注入的脚本跑不起来
  security: {
    csp: {
      directives: [
        "default-src 'self'",
        `img-src 'self' data: blob: ${supabase?.origin ?? ''} ${maps}`,
        "font-src 'self'",
        `connect-src 'self' ${supabase ? `${supabase.origin} ${supabase.origin.replace(/^http/, 'ws')}` : ''} ${turnstile} ${maps} ${pwned} ${insightsReport}`,
        "worker-src 'self' blob:",
        `frame-src ${turnstile}`,
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
      ],
      scriptDirective: { resources: ["'self'", turnstile, insights] },
    },
  },
});
