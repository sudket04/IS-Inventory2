import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// base: '/app/' matches app.py's app.mount("/app", ...) for the production
// build. The dev server instead proxies /api straight to uvicorn so
// `npm run dev` needs no separate CORS setup.
export default defineConfig({
  plugins: [react()],
  base: '/app/',
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:8000',
    },
  },
  build: {
    outDir: 'dist',
  },
});
