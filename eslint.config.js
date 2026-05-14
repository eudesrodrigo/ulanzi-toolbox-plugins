import js from '@eslint/js';
import prettier from 'eslint-config-prettier';

export default [
  {
    ignores: ['**/libs/**', '**/node_modules/**', 'coverage/**', 'docs/**'],
  },

  // Node.js plugin code
  {
    files: ['**/plugin/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        console: 'readonly',
        process: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
        URL: 'readonly',
        Buffer: 'readonly',
      },
    },
    rules: {
      ...js.configs.recommended.rules,
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },

  // Browser property-inspector code
  {
    files: ['**/property-inspector/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'script',
      globals: {
        // Browser globals
        console: 'readonly',
        document: 'readonly',
        window: 'readonly',
        navigator: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        HTMLCanvasElement: 'readonly',
        XMLHttpRequest: 'readonly',
        FormData: 'readonly',
        URLSearchParams: 'readonly',
        WebSocket: 'readonly',
        Image: 'readonly',
        FileReader: 'readonly',
        File: 'readonly',
        fetch: 'readonly',
        AbortController: 'readonly',
        location: 'readonly',
        // Ulanzi SDK globals (loaded via <script> tags)
        $UD: 'readonly',
        EventEmitter: 'readonly',
        Utils: 'readonly',
        Events: 'readonly',
        SocketErrors: 'readonly',
      },
    },
    rules: {
      ...js.configs.recommended.rules,
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },

  prettier,
];
