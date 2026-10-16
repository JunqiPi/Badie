import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import { noindexPaths } from './src/lib/venues';

const hidden = noindexPaths();
hidden.add('/app/');

export default defineConfig({
  site: process.env.SITE_URL || 'http://localhost:4321',
  trailingSlash: 'always',
  devToolbar: { enabled: false },
  integrations: [react(), sitemap({ filter: (page) => !hidden.has(decodeURIComponent(new URL(page).pathname)) })],
  vite: { plugins: [tailwindcss()] },
});
