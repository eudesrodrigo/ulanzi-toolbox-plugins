# Deep Clean — macOS Disk Cleanup for D200

## Overview

A dedicated D200 action that continuously shows disk usage percentage on the key
and, when pressed, opens an interactive cleanup script in the terminal. After
cleanup, the key updates to reflect the new disk state.

No external dependencies — pure bash script + plugin JS. Works offline,
deterministic behavior.

## D200 Key Experience

The key is a **live dashboard**, not just a launcher.

### State Machine

```
                    ┌──────────────────────┐
                    │       IDLE           │
                    │                      │
                    │   ┌────────────┐     │
                    │   │  [disk]    │     │  polls df every 60s
                    │   │ 80/228 GB  │     │  setStateIcon(ctx, 0, "80/228 GB")
                    │   └────────────┘     │
                    └──────────┬───────────┘
                               │ key press
                               ▼
                    ┌──────────────────────┐
                    │      RUNNING         │
                    │                      │
                    │   ┌────────────┐     │  setStateIcon(ctx, 1, "...")
                    │   │  [broom]   │     │  opens terminal with script
                    │   │   ...      │     │  polls exit file (no timeout)
                    │   └────────────┘     │
                    └──────────┬───────────┘
                               │ script exits
                       ┌───────┴───────┐
                       ▼               ▼
              ┌──────────────┐ ┌──────────────┐
              │   SUCCESS    │ │    ERROR     │
              │              │ │              │
              │  [disk]      │ │  showAlert() │
              │ 94/228 GB    │ │              │
              └──────┬───────┘ └──────┬───────┘
                     │  2s flash      │  2s flash
                     └───────┬────────┘
                             ▼
                     back to IDLE
                     (updated GB)
```

### What the User Sees

| Moment                    | Key Display             | How                                              |
| ------------------------- | ----------------------- | ------------------------------------------------ |
| Key added to deck         | Disk icon + "80/228 GB" | `setStateIcon(ctx, 0, "80/228 GB")`              |
| Every 60 seconds          | Updated free/total      | timer → `exec('df')` → `setStateIcon`            |
| Key pressed               | Broom icon + "..."      | `setStateIcon(ctx, 1, "...")`                    |
| Script running            | Broom icon + "..."      | terminal is open, user interacts                 |
| Script succeeds           | Disk icon + "94/228 GB" | re-poll df → `setStateIcon(ctx, 0, "94/228 GB")` |
| Script fails              | Alert flash             | `showAlert(ctx)` → then back to idle with GB     |
| Key pressed while running | Nothing                 | ignored (debounce)                               |

### Manifest Icons (States)

The action needs 2 states in the manifest:

```json
"States": [
  { "Name": "Idle", "Image": "plugin/icons/deep-clean/idle.png" },
  { "Name": "Running", "Image": "plugin/icons/deep-clean/running.png" }
]
```

- **idle.png**: disk/storage icon (dark background, white outline)
- **running.png**: broom/sweep icon (dark background, white outline)

Both are 196x196 PNG, 72 DPI, following existing icon conventions.
The SDK's `textData` parameter overlays the percentage text on top.

## Plugin Changes

### New Action: DeepCleanAction

```
plugin/actions/DeepCleanAction.js
```

Lifecycle:

| Event                | Method          | Behavior                                     |
| -------------------- | --------------- | -------------------------------------------- |
| `onAdd`              | `onAppear()`    | Start 60s polling timer, run initial `df`    |
| `onRun`              | `execute()`     | Set running state, execute script, poll exit |
| `onSetActive(false)` | pause timer     | Stop polling while key is not visible        |
| `onSetActive(true)`  | resume timer    | Resume polling                               |
| `onClear`            | `onDisappear()` | Stop timer, cleanup                          |

Key implementation details:

- **Polling**: `exec('df -h /')` every 60s, parse percentage, call
  `setStateIcon(context, 0, "${free}/${total} GB")`
- **Execute**: Reuses the existing `executeCommand()` from `executors/executor.js`
  to open the script in Terminal/iTerm. The script path is hardcoded relative to
  the plugin directory (no user configuration needed)
- **Exit polling**: Like `RunCommandAction.pollExitCode`, but with **no timeout** —
  the script is interactive and can run for minutes. Poll stops when the exit
  file appears or the action is deactivated
- **Debounce**: If `this.running === true`, subsequent key presses are ignored
- **Post-completion**: Re-run `df`, update key text, brief success indicator

### Changes to app.js

Add lifecycle hooks for actions that need them:

```javascript
$UD.onAdd((jsn) => {
  let instance = ACTION_CACHES[jsn.context];
  if (!instance) instance = createAction(jsn);
  applySettings(jsn);
  instance.onAppear?.(); // NEW
});

$UD.onClear((jsn) => {
  if (jsn.param) {
    for (const item of jsn.param) {
      ACTION_CACHES[item.context]?.onDisappear?.(); // NEW
      delete ACTION_CACHES[item.context];
    }
  }
});

$UD.onSetActive((jsn) => {
  const instance = ACTION_CACHES[jsn.context];
  if (instance) {
    instance.active = jsn.active;
    instance.onActiveChange?.(jsn.active); // NEW
  }
});
```

Backwards-compatible — existing actions don't have these methods, so optional
chaining skips them.

### Manifest Addition

New entry in the `Actions` array:

```json
{
  "Name": "Deep Clean",
  "Icon": "plugin/icons/deep-clean/idle.png",
  "PropertyInspectorPath": "property-inspector/deep-clean/inspector.html",
  "States": [
    { "Name": "Idle", "Image": "plugin/icons/deep-clean/idle.png" },
    { "Name": "Running", "Image": "plugin/icons/deep-clean/running.png" }
  ],
  "Tooltip": "Show disk usage and run cleanup",
  "UUID": "com.ulanzi.ulanzistudio.toolbox.deepclean",
  "SupportedInMultiActions": false,
  "DisableAutomaticStates": true,
  "Controllers": ["Keypad"]
}
```

`SupportedInMultiActions: false` because this action has persistent state
(polling timer) that doesn't make sense in a multi-action sequence.

### Property Inspector

Minimal — the action is self-contained:

```
property-inspector/deep-clean/inspector.html
```

Fields:

| Field           | Type       | Default     | Purpose                                     |
| --------------- | ---------- | ----------- | ------------------------------------------- |
| Terminal        | select     | Auto-detect | iTerm or Terminal.app                       |
| Projects dir    | text input | ~/Projects  | Where to scan for build artifacts           |
| Stale threshold | number     | 30          | Days since last commit to flag node_modules |

### ACTION_MAP Registration

```javascript
const ACTION_MAP = {
  [`${PLUGIN_UUID}.runcommand`]: RunCommandAction,
  [`${PLUGIN_UUID}.runscript`]: RunScriptAction,
  [`${PLUGIN_UUID}.sshcommand`]: SshCommandAction,
  [`${PLUGIN_UUID}.deepclean`]: DeepCleanAction, // NEW
};
```

## Script: deep-clean.sh

### Location

```
com.ulanzi.toolbox.ulanziPlugin/scripts/deep-clean.sh
```

Shipped with the plugin, deployed by `install.sh`. The `DeepCleanAction` resolves
its path relative to `__dirname`.

### Architecture

```
┌──────────────────────────────────────────┐
│              deep-clean.sh               │
├──────────────────────────────────────────┤
│  Phase 1: DETECT                         │
│  - Which tools are installed?            │
│  - df -h / for baseline                 │
│                                          │
│  Phase 2: SCAN                           │
│  - Measure each target (du -sh)          │
│  - Run safety checks (pgrep, git, etc.) │
│  - Build numbered item list              │
│                                          │
│  Phase 3: DISPLAY                        │
│  - Banner + disk usage bar               │
│  - Categorized items with sizes          │
│                                          │
│  Phase 4: SELECT                         │
│  - User picks items (numbers/ranges/all) │
│                                          │
│  Phase 5: CONFIRM                        │
│  - Show selected items + exact commands  │
│  - y/N confirmation                      │
│                                          │
│  Phase 6: EXECUTE                        │
│  - Run each cleanup, show [OK]/[FAIL]    │
│                                          │
│  Phase 7: REPORT                         │
│  - Before/after disk usage               │
│  - Total space freed                     │
└──────────────────────────────────────────┘
```

### Terminal UX

**Scan screen:**

```
  Deep Clean v1.0
  ════════════════════════════════════════

  Disk: Macintosh HD
  [##############..........] 65% used (148/228 GB)

  Scanning targets...
    Checking Docker..................... done
    Checking package managers........... done
    Checking IDE & browser caches....... done
    Checking build artifacts............ done
    Checking system caches.............. done
```

**Selection screen:**

```
  Found 26.5 GB reclaimable across 18 items.

  -- Docker & Package Managers --------------- 16.3 GB --

   [1] Docker unused images                     11.4 GB
   [2] Docker build cache                        850 MB
   [3] npm cache                                1.8 GB
   [4] Homebrew old versions                     760 MB
   [5] Python caches (pip + uv)                  740 MB
   [6] pnpm store                                420 MB
   [7] Go caches (build + modules)               105 MB
   [8] node-gyp cache                             62 MB

  -- IDE & Browser Caches ---------------------- 5.8 GB --

   [9]  JetBrains caches                        1.9 GB
   [10] Brave browser cache                     1.5 GB
        ! Brave is running — cache regenerates on restart
   [11] Chrome browser cache                     948 MB
   [12] Playwright browsers                     1.5 GB
        * needs `npx playwright install` to restore

  -- Build Artifacts & Projects ---------------- 2.7 GB --

   [13] node_modules (3 stale projects)         1.2 GB
        - service-api (4 months ago)
        - old-prototype (8 months ago)
        - archived-tool (1 year ago)
   [14] .next build cache                        379 MB
   [15] Python caches (__pycache__, .mypy_cache)  195 MB

  -- System ------------------------------------- 1.7 GB --

   [16] Siri/Geo system caches                   301 MB
   [17] Xcode DerivedData                        850 MB
   [18] Trash                                    120 MB
        ! Permanent deletion — cannot be undone

  (i) Downloads: 2.1 GB — run `open ~/Downloads` to review

  ───────────────────────────────────────────────────────

  Select items (e.g. 1 3 5-8 all) or q to quit: _
```

**Confirmation screen:**

```
  Selected for cleanup:

   [1]  Docker unused images                    11.4 GB
        $ docker image prune -a -f
   [3]  npm cache                               1.8 GB
        $ npm cache clean --force
   [5]  Python caches (pip + uv)                 740 MB
        $ pip3 cache purge && uv cache clean

  Total: ~14.0 GB

  Proceed? [y/N]: _
```

**Execution & report:**

```
  Cleaning...

   [OK]   Docker unused images                 -11.4 GB
   [OK]   npm cache                            -1.8 GB
   [OK]   Python caches                         -740 MB

  ════════════════════════════════════════════════

  Before: 148 GB used (65%)
  After:  134 GB used (59%)
  Freed:  14.0 GB

  ════════════════════════════════════════════════

  Press Enter to close.
```

The "Press Enter to close" gives the user time to read the report before the
terminal tab closes and the D200 key updates.

### Exit Codes

| Code | Meaning                            | D200 Key Response        |
| ---- | ---------------------------------- | ------------------------ |
| 0    | At least one cleanup succeeded     | Update GB                |
| 1    | All cleanups failed                | showAlert, then update % |
| 2    | User cancelled (q or N at confirm) | Update GB (no alert)     |
| 130  | Ctrl+C                             | Update GB (no alert)     |

The `DeepCleanAction` treats exit codes 0 and 2 as non-error (key returns to
idle with updated GB). Code 1 triggers `showAlert` briefly before returning
to idle.

### Configuration

Environment variables with sensible defaults — can be set in the property
inspector and passed as env vars to the script:

```bash
DEEP_CLEAN_PROJECTS_DIR="${DEEP_CLEAN_PROJECTS_DIR:-$HOME/Projects}"
DEEP_CLEAN_STALE_DAYS="${DEEP_CLEAN_STALE_DAYS:-30}"
DEEP_CLEAN_MIN_SIZE_MB="${DEEP_CLEAN_MIN_SIZE_MB:-10}"
```

## Scan Targets

### Category 1: Docker & Package Managers

| Target                  | Detect                                         | Measure                                   | Cleanup                    |
| ----------------------- | ---------------------------------------------- | ----------------------------------------- | -------------------------- |
| Docker images (unused)  | `command -v docker && docker info &>/dev/null` | `docker system df` (Images row)           | `docker image prune -a -f` |
| Docker build cache      | (same)                                         | `docker system df` (Build Cache row)      | `docker builder prune -f`  |
| Docker volumes (unused) | (same)                                         | `docker system df` (Volumes row)          | `docker volume prune -f`   |
| npm cache               | `command -v npm`                               | `du -sh "$(npm config get cache)"`        | `npm cache clean --force`  |
| Homebrew cache          | `command -v brew`                              | `du -sh "$(brew --cache)"`                | `brew cleanup --prune=0`   |
| uv cache                | `command -v uv`                                | `du -sh ~/.cache/uv`                      | `uv cache clean`           |
| pnpm store              | `command -v pnpm`                              | `du -sh "$(pnpm store path 2>/dev/null)"` | `pnpm store prune`         |
| pip cache               | `command -v pip3`                              | `pip3 cache info` (parse size)            | `pip3 cache purge`         |
| Go build cache          | `command -v go`                                | `du -sh "$(go env GOCACHE)"`              | `go clean -cache`          |
| Go module cache         | `command -v go`                                | `du -sh "$(go env GOMODCACHE)"`           | `go clean -modcache`       |
| node-gyp cache          | `[ -d ~/.node-gyp ]`                           | `du -sh ~/.node-gyp`                      | `rm -rf ~/.node-gyp`       |

### Category 2: IDE & Browser Caches

| Target              | Detect                                  | Measure  | Cleanup                                 |
| ------------------- | --------------------------------------- | -------- | --------------------------------------- |
| JetBrains caches    | `[ -d ~/Library/Caches/JetBrains ]`     | `du -sh` | `rm -rf ~/Library/Caches/JetBrains`     |
| Brave cache         | `[ -d ~/Library/Caches/BraveSoftware ]` | `du -sh` | `rm -rf ~/Library/Caches/BraveSoftware` |
| Chrome cache        | `[ -d ~/Library/Caches/Google/Chrome ]` | `du -sh` | `rm -rf ~/Library/Caches/Google/Chrome` |
| Playwright browsers | `[ -d ~/Library/Caches/ms-playwright ]` | `du -sh` | `rm -rf ~/Library/Caches/ms-playwright` |
| Cursor caches       | `[ -d ~/Library/Caches/Cursor ]`        | `du -sh` | `rm -rf ~/Library/Caches/Cursor`        |

### Category 3: Build Artifacts & Projects

| Target               | Detect                                                   | Measure        | Cleanup                      |
| -------------------- | -------------------------------------------------------- | -------------- | ---------------------------- |
| node_modules (stale) | `find $PROJECTS -maxdepth 3 -name node_modules -type d`  | `du -sh` each  | `rm -rf` per project         |
| .next build dirs     | `find $PROJECTS -maxdepth 3 -name .next -type d`         | `du -sh` each  | `rm -rf` per project         |
| .mypy_cache          | `find $PROJECTS -maxdepth 3 -name .mypy_cache -type d`   | `du -sh` each  | `rm -rf` each                |
| \_\_pycache\_\_ dirs | `find $PROJECTS -maxdepth 4 -name __pycache__ -type d`   | `du -sh` total | `find ... -exec rm -rf {} +` |
| .pytest_cache        | `find $PROJECTS -maxdepth 3 -name .pytest_cache -type d` | `du -sh` total | `find ... -exec rm -rf {} +` |
| .turbo cache         | `find $PROJECTS -maxdepth 3 -name .turbo -type d`        | `du -sh` total | `rm -rf` each                |

**node_modules filtering:**

```bash
project_dir="$(dirname "$nm_path")"
last_commit=$(git -C "$project_dir" log -1 --format="%cr" 2>/dev/null)
dirty=$(git -C "$project_dir" status --porcelain 2>/dev/null)
```

- `dirty` non-empty → **skip entirely** (uncommitted work)
- Last commit < `$DEEP_CLEAN_STALE_DAYS` days → **skip** (active project)
- Last commit >= threshold → **show as stale** with date label

### Category 4: System & Misc

| Target             | Detect                                                | Measure               | Cleanup                                        |
| ------------------ | ----------------------------------------------------- | --------------------- | ---------------------------------------------- |
| SiriTTS cache      | `ls ~/Library/Caches/com.apple.SiriTTS* 2>/dev/null`  | `du -sh`              | `rm -rf ~/Library/Caches/com.apple.SiriTTS*`   |
| GeoServices cache  | `[ -d ~/Library/Caches/GeoServices ]`                 | `du -sh`              | `rm -rf ~/Library/Caches/GeoServices`          |
| macOS log archives | `[ -d /var/log/asl ]`                                 | `du -sh /var/log/asl` | `sudo rm -rf /var/log/asl/*.asl`               |
| Xcode DerivedData  | `[ -d ~/Library/Developer/Xcode/DerivedData ]`        | `du -sh`              | `rm -rf ~/Library/Developer/Xcode/DerivedData` |
| iOS DeviceSupport  | `[ -d ~/Library/Developer/Xcode/iOS\ DeviceSupport ]` | `du -sh`              | `rm -rf`                                       |
| Trash              | `[ -d ~/.Trash ]`                                     | `du -sh ~/.Trash`     | `rm -rf ~/.Trash/*`                            |

**Display-only (not selectable):**

| Target    | Why        | Shown as                                       |
| --------- | ---------- | ---------------------------------------------- |
| Downloads | User files | `(i) Downloads: 2.1 GB — run open ~/Downloads` |

## Safety Rules

1. **Never delete source code or `.git`** — only known cache/artifact paths
2. **Never delete node_modules with uncommitted work** — `git status --porcelain`
3. **Active projects (< stale threshold) excluded** from node_modules cleanup
4. **Warn if process running** before deleting caches (inline `!` warning)
5. **Docker: skip if daemon not running** — don't show items that would fail
6. **`sudo` commands labeled** — `(sudo)` in the item name
7. **Trash gets "permanent deletion" warning** inline
8. **Downloads: never deletable** — informational line only
9. **Show exact commands in confirmation** — no hidden operations
10. **Ctrl+C = clean exit** — trap SIGINT, no partial state

## Input Parsing

| Input        | Meaning             |
| ------------ | ------------------- |
| `3`          | Item 3 only         |
| `1 3 5`      | Items 1, 3, and 5   |
| `5-8`        | Items 5 through 8   |
| `1 3 5-8 12` | Mixed selection     |
| `all`        | All displayed items |
| `q`          | Quit (exit code 2)  |

Invalid numbers silently ignored. Empty selection after parsing → re-prompt.

## Scan Performance

- **Timeout per target**: 5s. If `du` times out → show `?? MB`, item still
  selectable
- **Skip missing targets**: Check existence before measuring
- **Docker uses `docker system df`** — instant (no `du`)
- **Group `find` calls**: One `find` per artifact type, not per project

Expected scan time: 5-15 seconds.

## File Deliverables

| File                                           | Purpose                                               |
| ---------------------------------------------- | ----------------------------------------------------- |
| `plugin/actions/DeepCleanAction.js`            | New action class with disk polling                    |
| `plugin/actions/DeepCleanAction.test.js`       | Tests for polling, state transitions, debounce        |
| `scripts/deep-clean.sh`                        | Interactive cleanup script                            |
| `plugin/icons/deep-clean/idle.png`             | Disk icon (196x196, 72 DPI)                           |
| `plugin/icons/deep-clean/running.png`          | Broom icon (196x196, 72 DPI)                          |
| `property-inspector/deep-clean/inspector.html` | Settings UI (terminal, projects dir, stale threshold) |
| `property-inspector/deep-clean/inspector.js`   | Property inspector logic                              |

Changes to existing files:

| File            | Change                                                                                       |
| --------------- | -------------------------------------------------------------------------------------------- |
| `plugin/app.js` | Add lifecycle hooks (`onAppear`, `onDisappear`, `onActiveChange`) + register DeepCleanAction |
| `manifest.json` | Add Deep Clean action entry                                                                  |

## Out of Scope (v1)

- Claude Code integration — could enhance with AI in v2
- Scheduled/automatic runs — manual, on-demand
- Linux/Windows — macOS only
- Application uninstall — use AppCleaner
- Network caches (DNS, ARP) — minimal space, high risk
- iCloud / Time Machine snapshots — managed by macOS
- Custom scan targets — hardcoded list is sufficient for v1

## Future Enhancements (v2+)

- **Color-coded text**: green (> 50 GB free), yellow (20-50 GB), red (< 20 GB)
  on the key text — needs testing if SDK `textData` supports color
- **Claude Code mode**: pass scan results for intelligent recommendations
- **History log**: track cleanup runs and space freed over time
- **Custom targets**: user-defined paths via config file
- **Disk usage trend**: show arrow (up/down) next to percentage
