# Tooling Design: Tests, Linter & Formatter

## Overview

Add Vitest (tests), ESLint 9 flat config (linting), and Prettier (formatting) to the
ulazin-plugins monorepo. The tooling lives at the repo root and is shared across all
current and future plugins via npm workspaces.

## Stack

| Tool                   | Version  | Role                                                         |
| ---------------------- | -------- | ------------------------------------------------------------ |
| Vitest                 | ^3       | Unit test framework (native ESM support)                     |
| ESLint                 | ^9       | Linting with flat config (`eslint.config.js`)                |
| eslint-config-prettier | ^10      | Disables ESLint formatting rules that conflict with Prettier |
| Prettier               | ^3       | Code formatting                                              |
| npm workspaces         | built-in | Monorepo dependency management                               |

## Architecture Decisions

### Why these tools

- **Vitest over Jest**: The codebase is 100% ES Modules (`"type": "module"`). Jest requires
  `--experimental-vm-modules` or Babel transforms for ESM. Vitest handles ESM natively.
- **Vitest over node:test**: Better DX — watch mode, coverage UI, richer assertions.
  `node:test` is viable but has weaker ESM mocking.
- **ESLint flat config over .eslintrc**: `.eslintrc` is deprecated since ESLint v9. Flat
  config uses explicit `files` globs — clearer when rules apply to Node.js vs browser code.
- **Single root configs over shared config package**: For a small monorepo with 2-3 plugins
  from the same author, a shared `@repo/eslint-config` package adds overhead without
  benefit. A single root file with `files` globs achieves the same consistency.

### Vendor code exclusion

`libs/js/` is Ulanzi SDK code (Chinese comments, different style, provided by manufacturer).
It is excluded from linting and testing. If modifications are needed in the future, they
can be linted on a file-by-file basis.

### Test scope: business logic only

Tests cover the `plugin/` layer — actions, utilities, and command-building logic. The
executors (`iterm-executor.js`, `terminal-executor.js`) are thin AppleScript wrappers that
call `osascript` — mocking them provides little value. The real logic lives in
`applescript-utils.js` (escaping, command construction), which is fully testable.

Property inspectors (`property-inspector/`) are browser UI with simple DOM bindings to the
SDK. No business logic to test.

## Directory Structure

```
ulazin-plugins/
├── package.json                  # root: private, workspaces, devDependencies
├── eslint.config.js              # flat config with files-based overrides
├── .prettierrc                   # single shared config
├── .prettierignore               # excludes vendor, node_modules, dist
├── .gitignore                    # updated
├── vitest.config.js              # root: projects pointing to plugin configs
│
├── com.ulanzi.toolbox.ulanziPlugin/
│   ├── package.json              # workspace (runtime deps only: ws)
│   ├── vitest.config.js          # plugin-level: include/exclude paths
│   ├── libs/                     # vendor SDK (excluded from lint + tests)
│   ├── plugin/
│   │   ├── app.js
│   │   ├── actions/
│   │   │   ├── RunCommandAction.js
│   │   │   ├── RunCommandAction.test.js
│   │   │   ├── RunScriptAction.js
│   │   │   ├── RunScriptAction.test.js
│   │   │   ├── SshCommandAction.js
│   │   │   └── SshCommandAction.test.js
│   │   ├── executors/
│   │   │   ├── applescript-utils.js
│   │   │   ├── applescript-utils.test.js
│   │   │   ├── executor.js
│   │   │   ├── terminal-executor.js
│   │   │   └── iterm-executor.js
│   │   └── utils/
│   │       ├── detect-terminal.js
│   │       └── detect-terminal.test.js
│   └── property-inspector/       # lint (browser globals), no tests
│
└── (future plugins)/             # same pattern
```

Test files are co-located with source (`.test.js` next to the file they test). This is
Vitest's default pattern and the simplest approach for small codebases — the test is always
visible next to the source in the editor.

## Configuration Details

### Root `package.json`

```json
{
  "private": true,
  "workspaces": ["com.ulanzi.*.ulanziPlugin"],
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "lint": "eslint .",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  },
  "devDependencies": {
    "eslint": "^9",
    "eslint-config-prettier": "^10",
    "prettier": "^3",
    "vitest": "^3",
    "@vitest/coverage-v8": "^3"
  }
}
```

### ESLint — `eslint.config.js`

Three config blocks via `files` globs:

1. **Node.js code** (`**/plugin/**/*.js`): `sourceType: "module"`, Node.js globals,
   recommended rules, no-unused-vars, no-undef.
2. **Browser code** (`**/property-inspector/**/*.js`): browser globals + SDK globals
   (`$UD`, `EventEmitter`, `Utils`, `Events`, `SocketErrors`).
3. **Ignored** (`**/libs/**`, `**/node_modules/**`): vendor SDK excluded entirely.

`eslint-config-prettier` is included last to disable any formatting rules that conflict
with Prettier.

### Prettier — `.prettierrc`

```json
{
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "semi": true
}
```

Matches the style already used in `plugin/` code (single quotes, semicolons, 2-space indent).

### Prettier — `.prettierignore`

```
node_modules/
**/libs/
dist/
*.html
```

HTML files excluded because the property inspector HTML is hand-written with specific
formatting for readability in the Ulanzi context.

### Vitest — root `vitest.config.js`

```js
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: ['com.ulanzi.*.ulanziPlugin/vitest.config.js'],
  },
});
```

### Vitest — plugin-level `vitest.config.js`

```js
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['plugin/**/*.test.js'],
    exclude: ['libs/**', 'node_modules/**'],
  },
});
```

### `.gitignore` additions

```
node_modules/
.DS_Store
coverage/
```

## Test Plan

### Files to test and what to cover

| Test File                   | Source                 | What to test                                                                                                                                                                                                                     |
| --------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `applescript-utils.test.js` | `applescript-utils.js` | `escapeAppleScript()` with backslashes, quotes, mixed. `buildFullCommand()` with/without cwd, with/without exitFile, special chars in paths. `SHELL_INIT` constant value.                                                        |
| `detect-terminal.test.js`   | `detect-terminal.js`   | `detectTerminal()` when iTerm exists vs doesn't (mock `existsSync`). `getTerminalById()` with valid id, 'auto', null, unknown. `getAvailableTerminals()` with/without iTerm present. Cache reset between tests.                  |
| `RunCommandAction.test.js`  | `RunCommandAction.js`  | `buildCommand()` returns settings.command or empty. `execute()` calls `executeCommand` with correct options. `execute()` shows alert when no command. `updateSettings()` merges. `pollExitCode()` reads and cleans up exit file. |
| `RunScriptAction.test.js`   | `RunScriptAction.js`   | `buildCommand()` wraps script in single quotes. `buildCommand()` appends args. `buildCommand()` returns empty when no script. `execute()` auto-sets cwd to script's directory. Inherits from RunCommandAction correctly.         |
| `SshCommandAction.test.js`  | `SshCommandAction.js`  | `buildCommand()` with valid host + command. `buildCommand()` escapes single quotes in command. `buildCommand()` rejects invalid hosts (injection attempts). `buildCommand()` returns empty when host or command missing.         |

### Mocking strategy

- `existsSync` — mocked via `vi.mock('fs')` for detect-terminal tests
- `executeCommand` — mocked via `vi.mock('../executors/executor.js')` for action tests
- `$UD` — plain object with `showAlert` as `vi.fn()` for action tests
- No mocking of `osascript`/AppleScript — those are integration boundaries we don't test

## Security Fixes (Pre-requisites, already applied)

1. **`RunScriptAction.js:10-11`** — Changed script path from double quotes to single quotes
   to prevent shell expansion of `$()` and backticks. Now consistent with `SshCommandAction`.
2. **`package-lock.json`** — Regenerated from `registry.npmjs.org` (was pointing to a
   corporate Artifactory proxy). Integrity hash verified as identical.

## Out of Scope

- TypeScript migration
- Pre-commit hooks (husky/lint-staged) — can be added later
- CI/CD pipeline
- E2E testing of the plugin running inside Ulanzi Studio
- Modifications to vendor SDK (`libs/js/`)
