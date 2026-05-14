#!/bin/bash
set -o pipefail

# --- Configuration --------------------------------------------------------
PROJECTS_DIR="${DEEP_CLEAN_PROJECTS_DIR:-$HOME/Projects}"
STALE_DAYS="${DEEP_CLEAN_STALE_DAYS:-30}"
MIN_SIZE_MB="${DEEP_CLEAN_MIN_SIZE_MB:-10}"

# --- Colors ---------------------------------------------------------------
if [ -t 1 ]; then
  BOLD="\033[1m"
  CYAN="\033[36m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  RED="\033[31m"
  DIM="\033[2m"
  RESET="\033[0m"
else
  BOLD="" CYAN="" GREEN="" YELLOW="" RED="" DIM="" RESET=""
fi

# --- Trap -----------------------------------------------------------------
trap 'printf "\n  Cancelled.\n"; exit 2' INT

# --- Globals --------------------------------------------------------------
declare -a ITEM_LABELS=()
declare -a ITEM_SIZES=()
declare -a ITEM_HUMAN=()
declare -a ITEM_CMDS=()
declare -a ITEM_WARNINGS=()
declare -a ITEM_CATEGORIES=()
ITEM_COUNT=0

# --- Helpers --------------------------------------------------------------
bytes_to_human() {
  local bytes=$1
  if [ "$bytes" -ge 1073741824 ]; then
    awk "BEGIN {printf \"%.1f GB\", $bytes / 1073741824}"
  elif [ "$bytes" -ge 1048576 ]; then
    printf "%d MB" "$((bytes / 1048576))"
  else
    printf "%d KB" "$((bytes / 1024))"
  fi
}

measure_dir() {
  local dir="$1"
  if [ ! -d "$dir" ]; then echo 0; return; fi
  local result
  result=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
  echo "${result:-0}"
}

measure_glob() {
  local pattern="$1"
  local total=0
  for d in $pattern; do
    [ -d "$d" ] || continue
    local s
    s=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
    total=$((total + ${s:-0}))
  done
  echo "$total"
}

kb_to_bytes() { echo $(($1 * 1024)); }

add_item() {
  local category="$1" label="$2" size_kb="$3" cmd="$4" warning="${5:-}"
  local size_bytes=$((size_kb * 1024))
  local min_bytes=$((MIN_SIZE_MB * 1048576))
  [ "$size_bytes" -lt "$min_bytes" ] && return
  ITEM_LABELS+=("$label")
  ITEM_SIZES+=("$size_bytes")
  ITEM_HUMAN+=("$(bytes_to_human "$size_bytes")")
  ITEM_CMDS+=("$cmd")
  ITEM_WARNINGS+=("$warning")
  ITEM_CATEGORIES+=("$category")
  ITEM_COUNT=$((ITEM_COUNT + 1))
}

get_disk_info() {
  df -g / | awk 'NR==2 {print $2, $3, $4}'
}

format_age() {
  local age_days=$1
  if [ "$age_days" -ge 365 ]; then
    echo "$(( age_days / 365 ))y ago"
  elif [ "$age_days" -ge 30 ]; then
    echo "$(( age_days / 30 ))mo ago"
  else
    echo "${age_days}d ago"
  fi
}

is_project_stale() {
  local proj_dir="$1"
  local dirty
  dirty=$(git -C "$proj_dir" status --porcelain 2>/dev/null)
  [ -n "$dirty" ] && return 1
  local last_epoch
  last_epoch=$(git -C "$proj_dir" log -1 --format="%at" 2>/dev/null)
  [ -z "$last_epoch" ] && return 1
  local now_epoch age_days
  now_epoch=$(date +%s)
  age_days=$(( (now_epoch - last_epoch) / 86400 ))
  [ "$age_days" -lt "$STALE_DAYS" ] && return 1
  return 0
}

print_disk_bar() {
  local total used avail pct
  read -r total used avail <<< "$(get_disk_info)"
  used=$((total - avail))
  if [ "$total" -gt 0 ]; then
    pct=$((used * 100 / total))
  else
    pct=0
  fi
  local bar_width=30
  local filled=$((pct * bar_width / 100))
  local empty=$((bar_width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar="${bar}#"; done
  for ((i=0; i<empty; i++)); do bar="${bar}."; done
  printf "  Disk: %s\n" "$(diskutil info / 2>/dev/null | awk -F: '/Volume Name/{gsub(/^ +/,"",$2);print $2}' || echo "Macintosh HD")"
  printf "  [${CYAN}%s${RESET}%s] %d%% used (%d/%d GB)\n" \
    "$(echo "$bar" | cut -c1-"$filled")" \
    "$(echo "$bar" | cut -c$((filled+1))-)" \
    "$pct" "$used" "$total"
}

# --- Phase 1: Banner + Baseline ------------------------------------------
clear
printf "\n"
printf "  ${BOLD}${CYAN}Deep Clean${RESET} v2.0\n"
printf "  ════════════════════════════════════════\n\n"
print_disk_bar
printf "\n"

# --- Phase 2: Scan --------------------------------------------------------
printf "  Scanning targets...\n"

# ── Docker ────────────────────────────────────────────────────────────────
printf "    Checking Docker..."
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  docker_df=$(docker system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null)
  img_size=$(echo "$docker_df" | awk -F'\t' '/Images/{print $3}' | sed 's/[^0-9.]//g')
  img_unit=$(echo "$docker_df" | awk -F'\t' '/Images/{print $3}' | sed 's/[0-9. ]//g' | head -c2)
  build_size=$(echo "$docker_df" | awk -F'\t' '/Build Cache/{print $3}' | sed 's/[^0-9.]//g')
  build_unit=$(echo "$docker_df" | awk -F'\t' '/Build Cache/{print $3}' | sed 's/[0-9. ]//g' | head -c2)

  to_kb() {
    local val="$1" unit="$2"
    case "$unit" in
      GB|gb) awk "BEGIN {printf \"%d\", $val * 1048576}" ;;
      MB|mb) awk "BEGIN {printf \"%d\", $val * 1024}" ;;
      kB|KB|kb) echo "${val%.*}" ;;
      *) echo 0 ;;
    esac
  }

  img_kb=$(to_kb "${img_size:-0}" "${img_unit:-MB}")
  build_kb=$(to_kb "${build_size:-0}" "${build_unit:-MB}")

  running=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
  warn=""
  [ "$running" -gt 0 ] && warn="$running container(s) running"
  add_item "Docker" "Docker dangling images" "${img_kb:-0}" "docker image prune -f" "$warn"
  add_item "Docker" "Docker build cache" "${build_kb:-0}" "docker builder prune -f" ""

  # Stopped containers
  stopped=$(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l | tr -d ' ')
  if [ "$stopped" -gt 0 ]; then
    stop_size=$(docker ps -a --filter "status=exited" --format "{{.Size}}" 2>/dev/null | awk -F'(' '{
      val=$1; gsub(/[^0-9.]/,"",val);
      if ($1 ~ /GB/) s+=val*1048576;
      else if ($1 ~ /MB/) s+=val*1024;
      else if ($1 ~ /kB/) s+=val;
    } END {printf "%d", s+0}')
    add_item "Docker" "Docker stopped containers ($stopped)" "${stop_size:-0}" "docker container prune -f" ""
  fi

  # Dangling volumes
  dang_vol=$(docker volume ls -q -f dangling=true 2>/dev/null | wc -l | tr -d ' ')
  if [ "$dang_vol" -gt 0 ]; then
    add_item "Docker" "Docker dangling volumes ($dang_vol)" "10240" "docker volume prune -f" ""
  fi

  printf " done\n"
else
  printf " ${DIM}not running${RESET}\n"
fi

# ── Package Managers ──────────────────────────────────────────────────────
printf "    Checking package managers..."
if command -v npm &>/dev/null; then
  npm_dir=$(npm config get cache 2>/dev/null)
  npm_kb=$(measure_dir "$npm_dir")
  add_item "Package Managers" "npm cache" "$npm_kb" "npm cache clean --force" ""
fi
if command -v brew &>/dev/null; then
  brew_dir=$(brew --cache 2>/dev/null)
  brew_kb=$(measure_dir "$brew_dir")
  add_item "Package Managers" "Homebrew downloads cache" "$brew_kb" "brew cleanup --prune=0 -s" ""
  # Orphaned deps
  orphans=$(brew autoremove --dry-run 2>/dev/null | grep "^==> Would uninstall" -A100 | grep -v "^==>" | wc -l | tr -d ' ')
  if [ "$orphans" -gt 0 ]; then
    add_item "Package Managers" "Homebrew orphaned deps ($orphans)" "10240" "brew autoremove" ""
  fi
fi
if command -v uv &>/dev/null && [ -d "$HOME/.cache/uv" ]; then
  uv_kb=$(measure_dir "$HOME/.cache/uv")
  add_item "Package Managers" "uv cache (Python)" "$uv_kb" "uv cache clean" ""
fi
if command -v pnpm &>/dev/null; then
  pnpm_dir=$(pnpm store path 2>/dev/null)
  if [ -n "$pnpm_dir" ] && [ -d "$pnpm_dir" ]; then
    pnpm_kb=$(measure_dir "$pnpm_dir")
    add_item "Package Managers" "pnpm store" "$pnpm_kb" "pnpm store prune" ""
  fi
fi
if command -v pip3 &>/dev/null; then
  pip_dir="$HOME/Library/Caches/pip"
  pip_kb=$(measure_dir "$pip_dir")
  add_item "Package Managers" "pip cache" "$pip_kb" "pip3 cache purge" ""
fi
if command -v go &>/dev/null; then
  go_cache=$(go env GOCACHE 2>/dev/null)
  go_mod=$(go env GOMODCACHE 2>/dev/null)
  go_kb=0
  [ -d "$go_cache" ] && go_kb=$((go_kb + $(measure_dir "$go_cache")))
  [ -d "$go_mod" ] && go_kb=$((go_kb + $(measure_dir "$go_mod")))
  add_item "Package Managers" "Go caches" "$go_kb" "go clean -cache && go clean -modcache" ""
fi
if [ -d "$HOME/.node-gyp" ]; then
  gyp_kb=$(measure_dir "$HOME/.node-gyp")
  add_item "Package Managers" "node-gyp cache" "$gyp_kb" "rm -rf ~/.node-gyp" ""
fi
if [ -d "$HOME/.cargo/registry" ]; then
  cargo_kb=$(measure_dir "$HOME/.cargo/registry")
  add_item "Package Managers" "Cargo registry cache" "$cargo_kb" "rm -rf ~/.cargo/registry/cache && rm -rf ~/.cargo/registry/src" "run 'cargo build' to restore"
fi
if command -v yarn &>/dev/null; then
  yarn_dir=$(yarn cache dir 2>/dev/null)
  if [ -n "$yarn_dir" ] && [ -d "$yarn_dir" ]; then
    yarn_kb=$(measure_dir "$yarn_dir")
    add_item "Package Managers" "Yarn cache" "$yarn_kb" "yarn cache clean" ""
  fi
fi
if [ -d "$HOME/Library/Caches/virtualenv" ]; then
  venv_cache_kb=$(measure_dir "$HOME/Library/Caches/virtualenv")
  add_item "Package Managers" "virtualenv cache" "$venv_cache_kb" "rm -rf ~/Library/Caches/virtualenv" ""
fi
printf " done\n"

# ── IDE & Browser Caches ─────────────────────────────────────────────────
printf "    Checking IDE & browser caches..."
if [ -d "$HOME/Library/Caches/JetBrains" ]; then
  jb_kb=$(measure_dir "$HOME/Library/Caches/JetBrains")
  jb_warn=""
  pgrep -fi "pycharm\|idea\|webstorm\|goland\|rider" &>/dev/null && jb_warn="IDE is running — cache regenerates on restart"
  add_item "IDE & Browser Caches" "JetBrains caches" "$jb_kb" "rm -rf ~/Library/Caches/JetBrains" "$jb_warn"
fi
# JetBrains old version data
if [ -d "$HOME/Library/Application Support/JetBrains" ]; then
  for jb_dir in "$HOME/Library/Application Support/JetBrains/"*/; do
    jb_ver=$(basename "$jb_dir")
    case "$jb_ver" in Daemon|PrivacyPolicy|bl|crl|consentOptions|acp-agents) continue ;; esac
    app_name=$(echo "$jb_ver" | sed 's/[0-9.]//g')
    if ! ls /Applications/"${app_name}"*.app &>/dev/null 2>&1; then
      old_jb_kb=$(measure_dir "$jb_dir")
      add_item "IDE & Browser Caches" "JetBrains $jb_ver (uninstalled)" "$old_jb_kb" "rm -rf '$jb_dir'" ""
    fi
  done
fi
# JetBrains logs
if [ -d "$HOME/Library/Logs/JetBrains" ]; then
  jb_log_kb=$(measure_dir "$HOME/Library/Logs/JetBrains")
  add_item "IDE & Browser Caches" "JetBrains logs" "$jb_log_kb" "rm -rf ~/Library/Logs/JetBrains" ""
fi
if [ -d "$HOME/Library/Caches/BraveSoftware" ]; then
  brave_kb=$(measure_dir "$HOME/Library/Caches/BraveSoftware")
  brave_warn=""
  pgrep -fi "brave" &>/dev/null && brave_warn="Brave is running — cache regenerates on restart"
  add_item "IDE & Browser Caches" "Brave browser cache" "$brave_kb" "rm -rf ~/Library/Caches/BraveSoftware" "$brave_warn"
fi
# Brave Service Worker caches
brave_sw_kb=0
for sw_dir in "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"/*/Service\ Worker/CacheStorage; do
  [ -d "$sw_dir" ] || continue
  brave_sw_kb=$((brave_sw_kb + $(measure_dir "$sw_dir")))
done
if [ "$brave_sw_kb" -gt 0 ]; then
  add_item "IDE & Browser Caches" "Brave Service Workers" "$brave_sw_kb" "find ~/Library/Application\\ Support/BraveSoftware -name CacheStorage -type d -exec rm -rf {} + 2>/dev/null" ""
fi
if [ -d "$HOME/Library/Caches/Google/Chrome" ]; then
  chrome_kb=$(measure_dir "$HOME/Library/Caches/Google/Chrome")
  chrome_warn=""
  pgrep -fi "chrome" &>/dev/null && chrome_warn="Chrome is running — cache regenerates on restart"
  add_item "IDE & Browser Caches" "Chrome browser cache" "$chrome_kb" "rm -rf ~/Library/Caches/Google/Chrome" "$chrome_warn"
fi
# Chrome Service Worker caches
chrome_sw_kb=0
for sw_dir in "$HOME/Library/Application Support/Google/Chrome"/*/Service\ Worker/CacheStorage; do
  [ -d "$sw_dir" ] || continue
  chrome_sw_kb=$((chrome_sw_kb + $(measure_dir "$sw_dir")))
done
if [ "$chrome_sw_kb" -gt 0 ]; then
  add_item "IDE & Browser Caches" "Chrome Service Workers" "$chrome_sw_kb" "find ~/Library/Application\\ Support/Google/Chrome -name CacheStorage -type d -exec rm -rf {} + 2>/dev/null" ""
fi
if [ -d "$HOME/Library/Caches/ms-playwright" ]; then
  pw_kb=$(measure_dir "$HOME/Library/Caches/ms-playwright")
  add_item "IDE & Browser Caches" "Playwright browsers" "$pw_kb" "rm -rf ~/Library/Caches/ms-playwright" "needs npx playwright install to restore"
fi
if [ -d "$HOME/Library/Caches/Cursor" ]; then
  cursor_kb=$(measure_dir "$HOME/Library/Caches/Cursor")
  add_item "IDE & Browser Caches" "Cursor caches" "$cursor_kb" "rm -rf ~/Library/Caches/Cursor" ""
fi
# VS Code caches
for vsc_dir in "$HOME/Library/Application Support/Code/Cache" "$HOME/Library/Application Support/Code/CachedData" "$HOME/Library/Application Support/Code/CachedExtensionVSIXs"; do
  if [ -d "$vsc_dir" ]; then
    vsc_kb=$(measure_dir "$vsc_dir")
    vsc_name=$(basename "$vsc_dir")
    add_item "IDE & Browser Caches" "VS Code $vsc_name" "$vsc_kb" "rm -rf '$vsc_dir'" ""
  fi
done
printf " done\n"

# ── App Data & Logs ──────────────────────────────────────────────────────
printf "    Checking app data & logs..."
# BambuStudio logs
if [ -d "$HOME/Library/Application Support/BambuStudio/log" ]; then
  bambu_kb=$(measure_dir "$HOME/Library/Application Support/BambuStudio/log")
  add_item "App Data & Logs" "BambuStudio logs" "$bambu_kb" "rm -rf ~/Library/Application\\ Support/BambuStudio/log" ""
fi
# Comet browser caches
if [ -d "$HOME/Library/Application Support/Comet" ]; then
  comet_cache_kb=0
  for cc_dir in "$HOME/Library/Application Support/Comet"/*/Cache "$HOME/Library/Application Support/Comet"/*/Service\ Worker/CacheStorage "$HOME/Library/Application Support/Comet"/*/GPUCache; do
    [ -d "$cc_dir" ] || continue
    comet_cache_kb=$((comet_cache_kb + $(measure_dir "$cc_dir")))
  done
  if [ "$comet_cache_kb" -gt 0 ]; then
    comet_warn=""
    pgrep -fi "comet" &>/dev/null && comet_warn="Comet is running — cache regenerates on restart"
    add_item "App Data & Logs" "Comet browser caches" "$comet_cache_kb" "find ~/Library/Application\\ Support/Comet -name Cache -o -name CacheStorage -o -name GPUCache | xargs rm -rf 2>/dev/null" "$comet_warn"
  fi
fi
# Zoom data
if [ -d "$HOME/Library/Application Support/zoom.us" ]; then
  zoom_kb=$(measure_dir "$HOME/Library/Application Support/zoom.us/data")
  add_item "App Data & Logs" "Zoom cached data" "$zoom_kb" "rm -rf ~/Library/Application\\ Support/zoom.us/data" ""
fi
# Slack caches
for slack_dir in "$HOME/Library/Application Support/Slack/Cache" "$HOME/Library/Application Support/Slack/Service Worker/CacheStorage"; do
  if [ -d "$slack_dir" ]; then
    slack_kb=$(measure_dir "$slack_dir")
    slack_name=$(basename "$slack_dir")
    add_item "App Data & Logs" "Slack $slack_name" "$slack_kb" "rm -rf '$slack_dir'" ""
  fi
done
# Discord caches
if [ -d "$HOME/Library/Application Support/discord/Cache" ]; then
  discord_kb=$(measure_dir "$HOME/Library/Application Support/discord/Cache")
  add_item "App Data & Logs" "Discord cache" "$discord_kb" "rm -rf ~/Library/Application\\ Support/discord/Cache" ""
fi
# Spotify cache
if [ -d "$HOME/Library/Application Support/Spotify/PersistentCache" ]; then
  spotify_kb=$(measure_dir "$HOME/Library/Application Support/Spotify/PersistentCache")
  add_item "App Data & Logs" "Spotify cache" "$spotify_kb" "rm -rf ~/Library/Application\\ Support/Spotify/PersistentCache" ""
fi
# Claude Code old sessions
if [ -d "$HOME/.claude/projects" ]; then
  claude_kb=$(measure_dir "$HOME/.claude/projects")
  add_item "App Data & Logs" "Claude Code sessions" "$claude_kb" "find ~/.claude/projects -name '*.jsonl' -mtime +7 -delete" "keeps last 7 days"
fi
printf " done\n"

# ── Build Artifacts ──────────────────────────────────────────────────────
printf "    Checking build artifacts..."
if [ -d "$PROJECTS_DIR" ]; then
  # Stale node_modules
  nm_list=""
  nm_total_kb=0
  while IFS= read -r nm_path; do
    [ -z "$nm_path" ] && continue
    proj_dir=$(dirname "$nm_path")
    is_project_stale "$proj_dir" || continue
    nm_kb=$(measure_dir "$nm_path")
    nm_total_kb=$((nm_total_kb + nm_kb))
    proj_name=$(basename "$proj_dir")
    last_epoch=$(git -C "$proj_dir" log -1 --format="%at" 2>/dev/null)
    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - last_epoch) / 86400 ))
    nm_list="${nm_list}\n        - ${proj_name} ($(format_age $age_days))"
  done < <(find "$PROJECTS_DIR" -maxdepth 3 -name node_modules -type d 2>/dev/null)
  if [ "$nm_total_kb" -gt 0 ]; then
    add_item "Build Artifacts" "node_modules (stale)" "$nm_total_kb" "# see details" "$nm_list"
  fi

  # Stale Python venvs
  venv_list=""
  venv_total_kb=0
  while IFS= read -r venv_path; do
    [ -z "$venv_path" ] && continue
    proj_dir=$(dirname "$venv_path")
    is_project_stale "$proj_dir" || continue
    venv_kb=$(measure_dir "$venv_path")
    venv_total_kb=$((venv_total_kb + venv_kb))
    proj_name=$(basename "$proj_dir")
    last_epoch=$(git -C "$proj_dir" log -1 --format="%at" 2>/dev/null)
    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - last_epoch) / 86400 ))
    sep=""; [ -n "$venv_list" ] && sep=$'\n'
    venv_list="${venv_list}${sep}${proj_name} ($(format_age $age_days))"
  done < <(find "$PROJECTS_DIR" -maxdepth 3 \( -name .venv -o -name venv \) -type d 2>/dev/null)
  if [ "$venv_total_kb" -gt 0 ]; then
    add_item "Build Artifacts" "Python venvs (stale)" "$venv_total_kb" "# see details" "$venv_list"
  fi

  # Generic build outputs in stale projects
  build_total_kb=0
  build_list=""
  for build_name in .next dist build .turbo .parcel-cache coverage .tox .eggs; do
    while IFS= read -r build_path; do
      [ -z "$build_path" ] && continue
      proj_dir=$(dirname "$build_path")
      is_project_stale "$proj_dir" || continue
      bk=$(measure_dir "$build_path")
      build_total_kb=$((build_total_kb + bk))
      proj_name=$(basename "$proj_dir")
      sep=""; [ -n "$build_list" ] && sep=$'\n'
      build_list="${build_list}${sep}${proj_name}/${build_name}"
    done < <(find "$PROJECTS_DIR" -maxdepth 3 -name "$build_name" -type d 2>/dev/null)
  done
  if [ "$build_total_kb" -gt 0 ]; then
    add_item "Build Artifacts" "Build outputs (stale)" "$build_total_kb" "# see details" "$build_list"
  fi

  # Python caches (always safe regardless of staleness)
  py_kb=0
  py_kb=$((py_kb + $(measure_glob "$PROJECTS_DIR"/*/.mypy_cache)))
  pycache_kb=$(find "$PROJECTS_DIR" -maxdepth 4 -name __pycache__ -type d -exec du -sk {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
  py_kb=$((py_kb + pycache_kb))
  pytest_kb=$(find "$PROJECTS_DIR" -maxdepth 3 -name .pytest_cache -type d -exec du -sk {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
  py_kb=$((py_kb + pytest_kb))
  ruff_kb=$(find "$PROJECTS_DIR" -maxdepth 3 -name .ruff_cache -type d -exec du -sk {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
  py_kb=$((py_kb + ruff_kb))
  add_item "Build Artifacts" "Python caches" "$py_kb" "find '$PROJECTS_DIR' -maxdepth 4 \\( -name __pycache__ -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache \\) -type d -exec rm -rf {} +" ""

  # Rust target dirs in stale projects
  rust_total_kb=0
  rust_list=""
  while IFS= read -r target_path; do
    [ -z "$target_path" ] && continue
    proj_dir=$(dirname "$target_path")
    is_project_stale "$proj_dir" || continue
    rk=$(measure_dir "$target_path")
    rust_total_kb=$((rust_total_kb + rk))
    proj_name=$(basename "$proj_dir")
    sep=""; [ -n "$rust_list" ] && sep=$'\n'
    rust_list="${rust_list}${sep}${proj_name}/target"
  done < <(find "$PROJECTS_DIR" -maxdepth 3 -name target -type d -path "*/target" 2>/dev/null | while read p; do [ -f "$(dirname "$p")/Cargo.toml" ] && echo "$p"; done)
  if [ "$rust_total_kb" -gt 0 ]; then
    add_item "Build Artifacts" "Rust target/ (stale)" "$rust_total_kb" "# see details" "$rust_list"
  fi
fi
printf " done\n"

# ── macOS System ─────────────────────────────────────────────────────────
printf "    Checking system caches..."
sys_kb=0
sys_cmd=""
if ls "$HOME/Library/Caches/com.apple.SiriTTS"* &>/dev/null 2>&1; then
  siri_kb=$(du -sk "$HOME"/Library/Caches/com.apple.SiriTTS* 2>/dev/null | awk '{s+=$1}END{print s+0}')
  sys_kb=$((sys_kb + siri_kb))
  sys_cmd="rm -rf ~/Library/Caches/com.apple.SiriTTS*"
fi
if [ -d "$HOME/Library/Caches/GeoServices" ]; then
  geo_kb=$(measure_dir "$HOME/Library/Caches/GeoServices")
  sys_kb=$((sys_kb + geo_kb))
  [ -n "$sys_cmd" ] && sys_cmd="$sys_cmd && " || true
  sys_cmd="${sys_cmd}rm -rf ~/Library/Caches/GeoServices"
fi
add_item "macOS System" "System caches (Siri, Geo)" "$sys_kb" "$sys_cmd" ""

if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
  xcode_kb=$(measure_dir "$HOME/Library/Developer/Xcode/DerivedData")
  add_item "macOS System" "Xcode DerivedData" "$xcode_kb" "rm -rf ~/Library/Developer/Xcode/DerivedData" ""
fi

# Xcode iOS Device Support
if [ -d "$HOME/Library/Developer/Xcode/iOS DeviceSupport" ]; then
  ios_ds_kb=$(measure_dir "$HOME/Library/Developer/Xcode/iOS DeviceSupport")
  add_item "macOS System" "Xcode iOS DeviceSupport" "$ios_ds_kb" "rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport" "reconnect device to regenerate for that iOS version"
fi

# iOS Simulator data
if [ -d "$HOME/Library/Developer/CoreSimulator/Devices" ]; then
  sim_kb=$(measure_dir "$HOME/Library/Developer/CoreSimulator/Devices")
  add_item "macOS System" "iOS Simulator devices" "$sim_kb" "xcrun simctl delete unavailable 2>/dev/null; rm -rf ~/Library/Developer/CoreSimulator/Devices" "recreated on next Xcode use"
fi

# Swift Package Manager cache
if [ -d "$HOME/Library/Caches/org.swift.swiftpm" ]; then
  spm_kb=$(measure_dir "$HOME/Library/Caches/org.swift.swiftpm")
  add_item "macOS System" "Swift PM cache" "$spm_kb" "rm -rf ~/Library/Caches/org.swift.swiftpm" ""
fi

# macOS wallpaper aerials
if [ -d "$HOME/Library/Application Support/com.apple.wallpaper/aerials" ]; then
  aerials_kb=$(measure_dir "$HOME/Library/Application Support/com.apple.wallpaper/aerials")
  add_item "macOS System" "macOS aerial wallpapers" "$aerials_kb" "rm -rf ~/Library/Application\\ Support/com.apple.wallpaper/aerials" "re-downloads on demand"
fi

# Diagnostic & crash reports
diag_kb=0
diag_cmd=""
if [ -d "$HOME/Library/Logs/DiagnosticReports" ]; then
  dk=$(measure_dir "$HOME/Library/Logs/DiagnosticReports")
  diag_kb=$((diag_kb + dk))
  diag_cmd="rm -rf ~/Library/Logs/DiagnosticReports"
fi
if [ -d "$HOME/Library/Logs/CrashReporter" ]; then
  ck=$(measure_dir "$HOME/Library/Logs/CrashReporter")
  diag_kb=$((diag_kb + ck))
  [ -n "$diag_cmd" ] && diag_cmd="$diag_cmd && " || true
  diag_cmd="${diag_cmd}rm -rf ~/Library/Logs/CrashReporter"
fi
add_item "macOS System" "Diagnostic/crash reports" "$diag_kb" "$diag_cmd" ""

# Trash
if [ -d "$HOME/.Trash" ]; then
  trash_kb=$(measure_dir "$HOME/.Trash")
  add_item "macOS System" "Trash" "$trash_kb" "rm -rf ~/.Trash/*" "permanent deletion — cannot be undone"
fi
printf " done\n"

# --- Phase 3: Display ----------------------------------------------------
printf "\n"

if [ "$ITEM_COUNT" -eq 0 ]; then
  printf "  ${GREEN}Nothing to clean — disk is tidy!${RESET}\n\n"
  printf "  Press Enter to close."
  read -r
  exit 0
fi

total_bytes=0
for s in "${ITEM_SIZES[@]}"; do total_bytes=$((total_bytes + s)); done
printf "  Found ${BOLD}$(bytes_to_human $total_bytes)${RESET} reclaimable across ${BOLD}${ITEM_COUNT}${RESET} items.\n\n"

current_cat=""
for ((i=0; i<ITEM_COUNT; i++)); do
  cat="${ITEM_CATEGORIES[$i]}"
  if [ "$cat" != "$current_cat" ]; then
    current_cat="$cat"
    cat_bytes=0
    for ((j=i; j<ITEM_COUNT; j++)); do
      [ "${ITEM_CATEGORIES[$j]}" = "$cat" ] && cat_bytes=$((cat_bytes + ${ITEM_SIZES[$j]}))
    done
    cat_human=$(bytes_to_human "$cat_bytes")
    printf "  ${DIM}-- %s " "$cat"
    pad=$((44 - ${#cat}))
    for ((p=0; p<pad; p++)); do printf "-"; done
    printf " %s --${RESET}\n\n" "$cat_human"
  fi
  num=$((i + 1))
  printf "   ${BOLD}[%2d]${RESET} %-40s %10s\n" "$num" "${ITEM_LABELS[$i]}" "${ITEM_HUMAN[$i]}"
  if [ -n "${ITEM_WARNINGS[$i]}" ]; then
    while IFS= read -r wline; do
      printf "        ${YELLOW}! %s${RESET}\n" "$wline"
    done <<< "${ITEM_WARNINGS[$i]}"
  fi
done

# --- Phase 4: Select -----------------------------------------------------
printf "\n  ───────────────────────────────────────────────────────\n\n"
printf "  Select items (e.g. 1 3 5-8 all) or q to quit: "
read -r selection

[ "$selection" = "q" ] || [ "$selection" = "Q" ] && { printf "\n  Bye.\n"; exit 2; }

# Parse selection
declare -a SELECTED=()
if [ "$selection" = "all" ] || [ "$selection" = "ALL" ]; then
  for ((i=1; i<=ITEM_COUNT; i++)); do SELECTED+=("$i"); done
else
  for token in $selection; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      from="${BASH_REMATCH[1]}"
      to="${BASH_REMATCH[2]}"
      for ((n=from; n<=to && n<=ITEM_COUNT; n++)); do
        [ "$n" -ge 1 ] && SELECTED+=("$n")
      done
    elif [[ "$token" =~ ^[0-9]+$ ]] && [ "$token" -ge 1 ] && [ "$token" -le "$ITEM_COUNT" ]; then
      SELECTED+=("$token")
    fi
  done
fi

# Deduplicate
SELECTED=($(printf '%s\n' "${SELECTED[@]}" | sort -un))

if [ "${#SELECTED[@]}" -eq 0 ]; then
  printf "\n  No valid items selected.\n"
  printf "  Press Enter to close."
  read -r
  exit 2
fi

# --- Phase 5: Confirm ----------------------------------------------------
printf "\n  Selected for cleanup:\n\n"
sel_total=0
for num in "${SELECTED[@]}"; do
  idx=$((num - 1))
  printf "   ${BOLD}[%2d]${RESET} %-40s %10s\n" "$num" "${ITEM_LABELS[$idx]}" "${ITEM_HUMAN[$idx]}"
  if [[ "${ITEM_CMDS[$idx]}" == "# see details" ]]; then
    printf "        ${DIM}\$ rm -rf <each stale entry>${RESET}\n"
  else
    printf "        ${DIM}\$ %s${RESET}\n" "${ITEM_CMDS[$idx]}"
  fi
  sel_total=$((sel_total + ITEM_SIZES[idx]))
done

printf "\n  Total: ${BOLD}~$(bytes_to_human $sel_total)${RESET}\n\n"
printf "  Proceed? [y/N]: "
read -r confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  printf "\n  Cancelled.\n"
  printf "  Press Enter to close."
  read -r
  exit 2
fi

# --- Phase 6: Execute ----------------------------------------------------
printf "\n  Cleaning...\n\n"
ok_count=0
fail_count=0

for num in "${SELECTED[@]}"; do
  idx=$((num - 1))
  label="${ITEM_LABELS[$idx]}"
  cmd="${ITEM_CMDS[$idx]}"

  # Special handling for stale node_modules
  if [[ "$label" == "node_modules (stale)" ]]; then
    while IFS= read -r nm_path; do
      [ -z "$nm_path" ] && continue
      proj_dir=$(dirname "$nm_path")
      is_project_stale "$proj_dir" || continue
      rm -rf "$nm_path" 2>/dev/null
    done < <(find "$PROJECTS_DIR" -maxdepth 3 -name node_modules -type d 2>/dev/null)
    printf "   ${GREEN}[OK]${RESET}   %-40s -%s\n" "$label" "${ITEM_HUMAN[$idx]}"
    ok_count=$((ok_count + 1))
    continue
  fi

  # Special handling for stale Python venvs
  if [[ "$label" == "Python venvs (stale)" ]]; then
    while IFS= read -r venv_path; do
      [ -z "$venv_path" ] && continue
      proj_dir=$(dirname "$venv_path")
      is_project_stale "$proj_dir" || continue
      rm -rf "$venv_path" 2>/dev/null
    done < <(find "$PROJECTS_DIR" -maxdepth 3 \( -name .venv -o -name venv \) -type d 2>/dev/null)
    printf "   ${GREEN}[OK]${RESET}   %-40s -%s\n" "$label" "${ITEM_HUMAN[$idx]}"
    ok_count=$((ok_count + 1))
    continue
  fi

  # Special handling for stale build outputs
  if [[ "$label" == "Build outputs (stale)" ]]; then
    for build_name in .next dist build .turbo .parcel-cache coverage .tox .eggs; do
      while IFS= read -r build_path; do
        [ -z "$build_path" ] && continue
        proj_dir=$(dirname "$build_path")
        is_project_stale "$proj_dir" || continue
        rm -rf "$build_path" 2>/dev/null
      done < <(find "$PROJECTS_DIR" -maxdepth 3 -name "$build_name" -type d 2>/dev/null)
    done
    printf "   ${GREEN}[OK]${RESET}   %-40s -%s\n" "$label" "${ITEM_HUMAN[$idx]}"
    ok_count=$((ok_count + 1))
    continue
  fi

  # Special handling for stale Rust target/
  if [[ "$label" == "Rust target/ (stale)" ]]; then
    while IFS= read -r target_path; do
      [ -z "$target_path" ] && continue
      proj_dir=$(dirname "$target_path")
      [ -f "$proj_dir/Cargo.toml" ] || continue
      is_project_stale "$proj_dir" || continue
      rm -rf "$target_path" 2>/dev/null
    done < <(find "$PROJECTS_DIR" -maxdepth 3 -name target -type d 2>/dev/null)
    printf "   ${GREEN}[OK]${RESET}   %-40s -%s\n" "$label" "${ITEM_HUMAN[$idx]}"
    ok_count=$((ok_count + 1))
    continue
  fi

  if eval "$cmd" 2>/dev/null; then
    printf "   ${GREEN}[OK]${RESET}   %-40s -%s\n" "$label" "${ITEM_HUMAN[$idx]}"
    ok_count=$((ok_count + 1))
  else
    printf "   ${RED}[FAIL]${RESET} %-40s\n" "$label"
    fail_count=$((fail_count + 1))
  fi
done

# --- Phase 7: Report -----------------------------------------------------
printf "\n  ════════════════════════════════════════════════\n\n"
read -r new_total _new_raw_used new_avail <<< "$(get_disk_info)"
new_used=$((new_total - new_avail))
printf "  After:  %d GB used, %d GB free (%d GB total)\n" "$new_used" "$new_avail" "$new_total"
printf "  Freed:  ${GREEN}${BOLD}~$(bytes_to_human $sel_total)${RESET}\n"
if [ "$fail_count" -gt 0 ]; then
  printf "  Failed: ${RED}%d item(s)${RESET}\n" "$fail_count"
fi
printf "\n  ════════════════════════════════════════════════\n"
printf "\n  Press Enter to close."
read -r

if [ "$ok_count" -gt 0 ]; then
  exit 0
else
  exit 1
fi
