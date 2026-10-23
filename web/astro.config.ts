import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import { noindexPaths } from './src/lib/venues';

const hidden = noindexPaths();
hidden.add('/captcha/');

// 网页应用只连自己的 Supabase 项目（本地开发 / CI 是本机的 Supabase）
const supabase = process.env.PUBLIC_SUPABASE_URL ? new URL(process.env.PUBLIC_SUPABASE_URL) : undefined;
const turnstile = 'https://challenges.cloudflare.com';
// 球馆地图的矢量瓦片、字体和图标（OpenFreeMap，免费、不用密钥）
const maps = 'https://tiles.openfreemap.org';
// 设密码时查是否泄露过（只发 SHA-1 前 5 位，见 src/app/password.ts）
const pwned = 'https://api.pwnedpasswords.com';

export default defineConfig({
  site: process.env.SITE_URL || 'http://localhost:4321',
  trailingSlash: 'always',
  devToolbar: { enabled: false },
  integrations: [react(), sitemap({ filter: (page) => !hidden.has(decodeURIComponent(new URL(page).pathname).replace(/^\/zh(?=\/)/, '')) })],
  vite: { plugins: [tailwindcss()] },
  // 内容安全策略：Astro 给页面里的每段脚本和样式算哈希，其他来源一律不许加载，XSS 注入的脚本跑不起来
  security: {
    csp: {
      directives: [
        "default-src 'self'",
        `img-src 'self' data: blob: ${supabase?.origin ?? ''} ${maps}`,
        "font-src 'self'",
        `connect-src 'self' ${supabase ? `${supabase.origin} ${supabase.origin.replace(/^http/, 'ws')}` : ''} ${turnstile} ${maps} ${pwned}`,
        "worker-src 'self' blob:",
        `frame-src ${turnstile}`,
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
      ],
      scriptDirective: { resources: ["'self'", turnstile] },
    },
  },
});
