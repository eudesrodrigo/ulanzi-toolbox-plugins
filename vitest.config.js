import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: ['com.ulanzi.*.ulanziPlugin/vitest.config.js'],
    coverage: {
      provider: 'v8',
      include: ['com.ulanzi.*.ulanziPlugin/plugin/**/*.js'],
      exclude: ['**/*.test.js', '**/app.js'],
      thresholds: {
        lines: 95,
        functions: 95,
        branches: 95,
        statements: 95,
      },
    },
  },
});
