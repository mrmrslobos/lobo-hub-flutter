import path from 'path';
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, '.', '');

  return {
    server: {
      port: 3000,
      host: '0.0.0.0',
    },
    plugins: [react()],
    // REMOVED 'define' block to prevent hard-coding empty vars at build time
    resolve: {
      alias: {
        '@': path.resolve(__dirname, '.'),
      }
    },
    build: {
      rollupOptions: {
        // env-config.js is injected at runtime by docker-entrypoint.sh —
        // tell Rollup not to try to bundle it.
        external: [],
      },
    },
  };
});
