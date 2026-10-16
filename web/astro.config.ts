import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import { noindexPaths } from './src/lib/venues';

const hidden = noindexPaths();

export default defineConfig({
  site: process.env.SITE_URL ?? 'http://localhost:4321',
  trailingSlash: 'always',
  integrations: [sitemap({ filter: (page) => !hidden.has(decodeURIComponent(new URL(page).pathname)) })],
  vite: { plugins: [tailwindcss()] },
});
