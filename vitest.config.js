import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: ['com.ulanzi.*.ulanziPlugin/vitest.config.js'],
  },
});
