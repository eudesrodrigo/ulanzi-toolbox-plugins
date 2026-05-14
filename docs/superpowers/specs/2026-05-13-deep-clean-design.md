# Deep Clean — macOS Disk Cleanup via D200

## Overview

A single D200 button press opens a terminal running Claude Code with a detailed
cleanup prompt. Claude Code scans the disk in parallel using 4 subagents, presents
findings organized by category with `AskUserQuestion` (multi-select), and executes
only what the user approves.

**Engine:** Claude Code itself — no intermediate script. The D200 `Run Command`
action executes:

```
claude "$(cat ~/.config/deep-clean/prompt.md)"
```

The `$(cat ...)` expansion passes the prompt file contents as the initial prompt
argument. The prompt file lives outside the plugin so it can be updated
independently. Shell expansion happens at invocation time, so the file is read
fresh on each button press.

## Architecture

```
D200 button press
    │
    ▼
Run Command action → opens Terminal → claude "<prompt>"
    │
    ▼
Claude Code receives prompt
    │
    ├── Agent 1: Docker & Package Managers
    ├── Agent 2: IDE, AI & Browser Caches
    ├── Agent 3: Projects, node_modules, Build Artifacts
    └── Agent 4: System, Misc, Downloads
    │
    ▼
Aggregate results into summary table
    │
    ▼
AskUserQuestion × 4 (multi-select, one per category)
    │
    ▼
Execute approved cleanups
    │
    ▼
Final report: space freed, errors, skipped items
```

## Scan Targets by Category

### Q1: Docker & Package Managers

| Target                  | Command                   | Expected Size | Risk                         |
| ----------------------- | ------------------------- | ------------- | ---------------------------- |
| Docker unused images    | `docker image prune -a`   | ~11 GB        | Low — rebuilds on pull/build |
| Docker build cache      | `docker builder prune`    | ~850 MB       | Low — rebuilds on next build |
| Docker volumes (unused) | `docker volume prune`     | variable      | Medium — check if named      |
| npm cache               | `npm cache clean --force` | ~1.8 GB       | Low — rebuilds on install    |
| Homebrew cache          | `brew cleanup --prune=0`  | ~760 MB       | Low — old versions           |
| uv cache (Python)       | `uv cache clean`          | ~640 MB       | Low — rebuilds               |
| pnpm store + cache      | `pnpm store prune`        | ~420 MB       | Low — rebuilds               |
| pip cache               | `pip cache purge`         | ~100 MB       | Low — rebuilds               |
| Go build cache          | `go clean -cache`         | ~80 MB        | Low — rebuilds               |
| Go module cache         | `go clean -modcache`      | ~25 MB        | Low — re-downloads           |
| node-gyp cache          | `rm -rf ~/.node-gyp`      | ~60 MB        | Low — rebuilds               |

### Q2: IDE, AI & Browser Caches

| Target               | Command                                                                 | Expected Size | Risk                                    |
| -------------------- | ----------------------------------------------------------------------- | ------------- | --------------------------------------- |
| JetBrains caches     | `rm -rf ~/Library/Caches/JetBrains`                                     | ~1.9 GB       | Low — regenerates on IDE open           |
| Brave cache          | `rm -rf ~/Library/Caches/BraveSoftware`                                 | ~1.5 GB       | Low — regenerates                       |
| Chrome cache         | `rm -rf ~/Library/Caches/Google/Chrome`                                 | ~950 MB       | Low — regenerates                       |
| Playwright browsers  | `rm -rf ~/Library/Caches/ms-playwright`                                 | ~1.5 GB       | Medium — needs `npx playwright install` |
| Claude Code sessions | delete `.jsonl` transcripts older than 90 days in `~/.claude/projects/` | ~400 MB       | Medium — old transcripts, keeps recent  |
| Cursor caches        | `rm -rf ~/Library/Caches/Cursor`                                        | variable      | Low — regenerates                       |

### Q3: Build Artifacts & Projects

| Target                  | Command                                                         | Expected Size | Risk                         |
| ----------------------- | --------------------------------------------------------------- | ------------- | ---------------------------- |
| node_modules (inactive) | `rm -rf <path>/node_modules`                                    | ~2 GB         | Low — `npm install` restores |
| .next build dirs        | `rm -rf <path>/.next`                                           | ~380 MB       | Low — `next build` restores  |
| .mypy_cache             | `rm -rf <path>/.mypy_cache`                                     | ~195 MB       | Low — regenerates            |
| **pycache** dirs        | `find ~/Projects -type d -name __pycache__ -exec rm -rf {} +`   | variable      | Low — regenerates            |
| .pytest_cache           | `find ~/Projects -type d -name .pytest_cache -exec rm -rf {} +` | variable      | Low — regenerates            |
| .turbo cache            | `rm -rf <path>/.turbo`                                          | variable      | Low — regenerates            |
| dist/build output       | show list, let user pick                                        | variable      | Medium — may need rebuild    |

### Q4: System & Misc

| Target             | Command                                                | Expected Size | Risk                    |
| ------------------ | ------------------------------------------------------ | ------------- | ----------------------- |
| SiriTTS cache      | `rm -rf ~/Library/Caches/com.apple.SiriTTSTraining*`   | ~236 MB       | Low — regenerates       |
| GeoServices cache  | `rm -rf ~/Library/Caches/GeoServices`                  | ~65 MB        | Low — regenerates       |
| macOS log archives | `sudo rm -rf /var/log/asl/*.asl`                       | variable      | Low — old logs          |
| Xcode DerivedData  | `rm -rf ~/Library/Developer/Xcode/DerivedData`         | variable      | Low — rebuilds          |
| Xcode archives     | show list, let user pick                               | variable      | Medium — old app builds |
| iOS DeviceSupport  | `rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport`  | variable      | Low — re-downloads      |
| Downloads folder   | `open ~/Downloads` (show size only, never auto-delete) | variable      | High — user files       |
| Trash              | show size, offer `rm -rf ~/.Trash/*`                   | variable      | High — last chance      |

## Intelligence Layer

Before presenting options, each subagent runs safety checks:

### Process & State Checks

```bash
# Docker — only offer cleanup if Docker daemon is running
docker info &>/dev/null

# Running containers — warn if any are running
docker ps --format '{{.Names}}' 2>/dev/null

# IDE — warn if JetBrains/browser is open before cache cleanup
pgrep -f "pycharm\|idea\|webstorm\|goland" 2>/dev/null
pgrep -f "Brave\|Chrome\|Firefox" 2>/dev/null
```

### Project Activity Checks

```bash
# For each project with node_modules, check last activity
git -C <project> log -1 --format="%cr" 2>/dev/null
# Tag as: "active (2 days ago)" vs "stale (4 months ago)"

# Uncommitted work — NEVER delete node_modules if dirty
git -C <project> status --porcelain 2>/dev/null
```

### Disk State

```bash
# Current disk usage summary
df -h /
# Show percentage before and estimate after cleanup
```

## AskUserQuestion Structure

Claude Code's `AskUserQuestion` supports up to 4 questions per call with
`multiSelect: true`. Each question gets up to 4 options. The subagents aggregate
scan results into these questions:

```
Question 1 — "Docker & Package Managers"
  header: "Dev Infra"
  options (multi-select):
    [ ] Docker: images + build cache + volumes (~12.3 GB)
    [ ] npm + pnpm + node-gyp cache (~2.3 GB)
    [ ] Homebrew old versions (~760 MB)
    [ ] Python: pip + uv cache (~740 MB)

Question 2 — "IDE, AI & Browser Caches"
  header: "Caches"
  options (multi-select):
    [ ] JetBrains IDE caches (~1.9 GB)
    [ ] Browser caches: Brave + Chrome (~2.5 GB)
    [ ] Playwright browsers (~1.5 GB)
    [ ] Claude Code old sessions (~400 MB)

Question 3 — "Build Artifacts & Projects"
  header: "Projects"
  options (multi-select):
    [ ] Stale node_modules (>30d inactive) — list projects
    [ ] .next / .turbo / dist build caches
    [ ] Python caches: __pycache__ + .mypy_cache + .pytest_cache
    [ ] Go caches: build + modules (~105 MB)

Question 4 — "System & Misc"
  header: "System"
  options (multi-select):
    [ ] macOS system caches (Siri, Geo, logs)
    [ ] Xcode: DerivedData + DeviceSupport
    [ ] Trash (show size)
    [ ] Downloads (open Finder only — never auto-delete)
```

Each option label includes the measured size so the user makes informed decisions.

## Safety Rules

These are hard constraints embedded in the prompt:

1. **Never delete source code or `.git` directories** — only derived/cached artifacts
2. **Never stop running Docker containers** — prune only applies to stopped/unused
3. **Never delete `node_modules` in projects with uncommitted changes** — check
   `git status --porcelain` first
4. **Downloads folder: show size, open Finder** — never `rm` user files
5. **Trash: explicit confirmation** — separate from other options
6. **Warn if IDE or browser is running** before deleting their caches — include
   process name in the warning
7. **Show exact commands before executing** — no hidden operations
8. **Active projects (git activity <30 days) get a warning label** on node_modules
9. **`sudo` operations require explicit callout** — user must see the elevated command
10. **Dry-run first** — show what would be deleted and estimated size before acting

## Prompt Design

The prompt file (`~/.config/deep-clean/prompt.md`) contains the full instructions
for Claude Code. Key sections:

### Prompt Structure

```
1. MISSION — You are a macOS disk cleanup assistant
2. PHASE 1: SCAN — Launch 4 parallel subagents
3. PHASE 2: AGGREGATE — Combine results into summary
4. PHASE 3: PRESENT — Use AskUserQuestion with categories
5. PHASE 4: EXECUTE — Run approved cleanups
6. PHASE 5: REPORT — Show before/after disk usage
7. SAFETY RULES — Hard constraints (see above)
```

### Subagent Prompts

Each subagent receives a focused prompt:

**Agent 1 — Docker & Package Managers:**

> Scan Docker disk usage (docker system df), npm/pnpm/pip/uv/Homebrew/Go caches.
> Report each item as: name, path, size (human-readable), cleanup command.
> Check if Docker daemon is running. List running containers.

**Agent 2 — IDE, AI & Browser Caches:**

> Scan ~/Library/Caches for JetBrains, Brave, Chrome, Cursor, Playwright.
> Scan Claude Code sessions (~/.claude). Report age and count.
> Check if each app is currently running (pgrep).

**Agent 3 — Projects, node_modules, Build Artifacts:**

> Find all node_modules, .next, .turbo, dist, **pycache**, .mypy_cache,
> .pytest_cache under ~/Projects. For each: report project path, size, last
> git commit date, whether git status is clean.

**Agent 4 — System & Misc:**

> Scan system caches (Siri, Geo, logs), Xcode data, Downloads, Trash.
> Report sizes. Flag any that need sudo.

### Execution Strategy

After user selection:

1. Show a summary table of all selected items with exact commands
2. Execute sequentially (not parallel) to avoid race conditions
3. After each category, report success/failure
4. Final summary: total space freed, any errors, suggestions for next time

## D200 Button Configuration

In the Ulanzi Studio property inspector:

| Field    | Value                                            |
| -------- | ------------------------------------------------ |
| Action   | Run Command                                      |
| Command  | `claude "$(cat ~/.config/deep-clean/prompt.md)"` |
| Terminal | Terminal.app (or iTerm)                          |
| Label    | Deep Clean                                       |

The button icon should show a broom or disk icon with the current disk usage
percentage overlay (future enhancement).

## File Deliverables

| File                             | Purpose                                        |
| -------------------------------- | ---------------------------------------------- |
| `~/.config/deep-clean/prompt.md` | The Claude Code prompt with full instructions  |
| `icons/actions/deep-clean.png`   | Button icon for the D200 (196x196 PNG, 72 DPI) |

The prompt file is standalone — it does not depend on any plugin code. The user
configures a standard `Run Command` action on the D200 pointing to the claude
command.

## Out of Scope

- Automated scheduling (cron) — this is a manual, on-demand tool
- Linux/Windows support — macOS only, matches the plugin's platform constraint
- GUI overlay on the D200 key — future enhancement (disk % display)
- Network cleanup (DNS cache, etc.) — too risky, minimal space gain
- Application uninstall — out of scope, user should use AppCleaner
