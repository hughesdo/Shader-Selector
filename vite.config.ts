import { defineConfig } from 'vite';

export default defineConfig({
  // relative base so the built dist/ works from any folder or subpath
  base: './',
  server: { port: 5180, open: true },
  preview: { port: 5181 },
  build: { target: 'es2022', chunkSizeWarningLimit: 800 },
});
