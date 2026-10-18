import type { APIRoute } from 'astro';

// 搜索引擎和 AI 搜索（会带来访问的）可以看公开页面；只拿去训练模型、不带来访问的爬虫不让抓。
// robots.txt 只约束守规矩的爬虫，真正的拦截在 Cloudflare（Bot Fight Mode、AI Crawl Control）
const trainingCrawlers = ['GPTBot', 'CCBot', 'Google-Extended', 'ClaudeBot', 'anthropic-ai', 'Applebot-Extended', 'Bytespider', 'meta-externalagent', 'Diffbot', 'cohere-training-data-crawler'];

export const GET: APIRoute = ({ site }) =>
  new Response(
    [
      ...trainingCrawlers.map((bot) => `User-agent: ${bot}\nDisallow: /\n`),
      'User-agent: *\nAllow: /\nDisallow: /app/\nDisallow: /captcha/\n',
      `Sitemap: ${new URL('/sitemap-index.xml', site)}\n`,
    ].join('\n'),
  );
