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
printf "  ${BOLD}${CYAN}Deep Clean${RESET} v1.0\n"
printf "  ════════════════════════════════════════\n\n"
print_disk_bar
printf "\n"

# --- Phase 2: Scan --------------------------------------------------------
printf "  Scanning targets...\n"

# Docker
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
      GB|gb) echo "$(echo "$val * 1048576" | bc | cut -d. -f1)" ;;
      MB|mb) echo "$(echo "$val * 1024" | bc | cut -d. -f1)" ;;
      kB|KB|kb) echo "${val%.*}" ;;
      *) echo 0 ;;
    esac
  }

  img_kb=$(to_kb "${img_size:-0}" "${img_unit:-MB}")
  build_kb=$(to_kb "${build_size:-0}" "${build_unit:-MB}")

  running=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
  warn=""
  [ "$running" -gt 0 ] && warn="$running container(s) running"
  add_item "Docker & Package Managers" "Docker unused images" "${img_kb:-0}" "docker image prune -a -f" "$warn"
  add_item "Docker & Package Managers" "Docker build cache" "${build_kb:-0}" "docker builder prune -f" ""
  printf " done\n"
else
  printf " ${DIM}not running${RESET}\n"
fi

# Package managers
printf "    Checking package managers..."
if command -v npm &>/dev/null; then
  npm_dir=$(npm config get cache 2>/dev/null)
  npm_kb=$(measure_dir "$npm_dir")
  add_item "Docker & Package Managers" "npm cache" "$npm_kb" "npm cache clean --force" ""
fi
if command -v brew &>/dev/null; then
  brew_dir=$(brew --cache 2>/dev/null)
  brew_kb=$(measure_dir "$brew_dir")
  add_item "Docker & Package Managers" "Homebrew old versions" "$brew_kb" "brew cleanup --prune=0" ""
fi
if command -v uv &>/dev/null && [ -d "$HOME/.cache/uv" ]; then
  uv_kb=$(measure_dir "$HOME/.cache/uv")
  add_item "Docker & Package Managers" "uv cache (Python)" "$uv_kb" "uv cache clean" ""
fi
if command -v pnpm &>/dev/null; then
  pnpm_dir=$(pnpm store path 2>/dev/null)
  if [ -n "$pnpm_dir" ] && [ -d "$pnpm_dir" ]; then
    pnpm_kb=$(measure_dir "$pnpm_dir")
    add_item "Docker & Package Managers" "pnpm store" "$pnpm_kb" "pnpm store prune" ""
  fi
fi
if command -v pip3 &>/dev/null; then
  pip_dir="$HOME/Library/Caches/pip"
  pip_kb=$(measure_dir "$pip_dir")
  add_item "Docker & Package Managers" "pip cache" "$pip_kb" "pip3 cache purge" ""
fi
if command -v go &>/dev/null; then
  go_cache=$(go env GOCACHE 2>/dev/null)
  go_mod=$(go env GOMODCACHE 2>/dev/null)
  go_kb=0
  [ -d "$go_cache" ] && go_kb=$((go_kb + $(measure_dir "$go_cache")))
  [ -d "$go_mod" ] && go_kb=$((go_kb + $(measure_dir "$go_mod")))
  add_item "Docker & Package Managers" "Go caches" "$go_kb" "go clean -cache && go clean -modcache" ""
fi
if [ -d "$HOME/.node-gyp" ]; then
  gyp_kb=$(measure_dir "$HOME/.node-gyp")
  add_item "Docker & Package Managers" "node-gyp cache" "$gyp_kb" "rm -rf ~/.node-gyp" ""
fi
printf " done\n"

# IDE & Browser caches
printf "    Checking IDE & browser caches..."
if [ -d "$HOME/Library/Caches/JetBrains" ]; then
  jb_kb=$(measure_dir "$HOME/Library/Caches/JetBrains")
  jb_warn=""
  pgrep -fi "pycharm\|idea\|webstorm\|goland\|rider" &>/dev/null && jb_warn="IDE is running — cache regenerates on restart"
  add_item "IDE & Browser Caches" "JetBrains caches" "$jb_kb" "rm -rf ~/Library/Caches/JetBrains" "$jb_warn"
fi
if [ -d "$HOME/Library/Caches/BraveSoftware" ]; then
  brave_kb=$(measure_dir "$HOME/Library/Caches/BraveSoftware")
  brave_warn=""
  pgrep -fi "brave" &>/dev/null && brave_warn="Brave is running — cache regenerates on restart"
  add_item "IDE & Browser Caches" "Brave browser cache" "$brave_kb" "rm -rf ~/Library/Caches/BraveSoftware" "$brave_warn"
fi
if [ -d "$HOME/Library/Caches/Google/Chrome" ]; then
  chrome_kb=$(measure_dir "$HOME/Library/Caches/Google/Chrome")
  chrome_warn=""
  pgrep -fi "chrome" &>/dev/null && chrome_warn="Chrome is running — cache regenerates on restart"
  add_item "IDE & Browser Caches" "Chrome browser cache" "$chrome_kb" "rm -rf ~/Library/Caches/Google/Chrome" "$chrome_warn"
fi
if [ -d "$HOME/Library/Caches/ms-playwright" ]; then
  pw_kb=$(measure_dir "$HOME/Library/Caches/ms-playwright")
  add_item "IDE & Browser Caches" "Playwright browsers" "$pw_kb" "rm -rf ~/Library/Caches/ms-playwright" "needs npx playwright install to restore"
fi
if [ -d "$HOME/Library/Caches/Cursor" ]; then
  cursor_kb=$(measure_dir "$HOME/Library/Caches/Cursor")
  add_item "IDE & Browser Caches" "Cursor caches" "$cursor_kb" "rm -rf ~/Library/Caches/Cursor" ""
fi
printf " done\n"

# Build artifacts
printf "    Checking build artifacts..."
if [ -d "$PROJECTS_DIR" ]; then
  # Stale node_modules
  nm_list=""
  nm_total_kb=0
  while IFS= read -r nm_path; do
    [ -z "$nm_path" ] && continue
    proj_dir=$(dirname "$nm_path")
    dirty=$(git -C "$proj_dir" status --porcelain 2>/dev/null)
    [ -n "$dirty" ] && continue
    last_epoch=$(git -C "$proj_dir" log -1 --format="%at" 2>/dev/null)
    [ -z "$last_epoch" ] && continue
    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - last_epoch) / 86400 ))
    [ "$age_days" -lt "$STALE_DAYS" ] && continue
    nm_kb=$(measure_dir "$nm_path")
    nm_total_kb=$((nm_total_kb + nm_kb))
    proj_name=$(basename "$proj_dir")
    if [ "$age_days" -ge 365 ]; then
      age_str="$(( age_days / 365 )) year(s) ago"
    elif [ "$age_days" -ge 30 ]; then
      age_str="$(( age_days / 30 )) month(s) ago"
    else
      age_str="${age_days} days ago"
    fi
    nm_list="${nm_list}\n        - ${proj_name} (${age_str})"
  done < <(find "$PROJECTS_DIR" -maxdepth 3 -name node_modules -type d 2>/dev/null)
  if [ "$nm_total_kb" -gt 0 ]; then
    nm_cmd="find '$PROJECTS_DIR' -maxdepth 3 -name node_modules -type d"
    add_item "Build Artifacts" "node_modules (stale)" "$nm_total_kb" "# see details" "$nm_list"
  fi

  # .next
  next_kb=$(measure_glob "$PROJECTS_DIR"/*/.next)
  add_item "Build Artifacts" ".next build caches" "$next_kb" "find '$PROJECTS_DIR' -maxdepth 2 -name .next -type d -exec rm -rf {} +" ""

  # Python caches
  py_kb=0
  py_kb=$((py_kb + $(measure_glob "$PROJECTS_DIR"/*/.mypy_cache)))
  pycache_kb=$(find "$PROJECTS_DIR" -maxdepth 4 -name __pycache__ -type d -exec du -sk {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
  py_kb=$((py_kb + pycache_kb))
  pytest_kb=$(find "$PROJECTS_DIR" -maxdepth 3 -name .pytest_cache -type d -exec du -sk {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
  py_kb=$((py_kb + pytest_kb))
  add_item "Build Artifacts" "Python caches" "$py_kb" "find '$PROJECTS_DIR' -maxdepth 4 \\( -name __pycache__ -o -name .mypy_cache -o -name .pytest_cache \\) -type d -exec rm -rf {} +" ""
fi
printf " done\n"

# System
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
  if [ -n "$sys_cmd" ]; then
    sys_cmd="$sys_cmd && rm -rf ~/Library/Caches/GeoServices"
  else
    sys_cmd="rm -rf ~/Library/Caches/GeoServices"
  fi
fi
add_item "System" "System caches (Siri, Geo)" "$sys_kb" "$sys_cmd" ""

if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
  xcode_kb=$(measure_dir "$HOME/Library/Developer/Xcode/DerivedData")
  add_item "System" "Xcode DerivedData" "$xcode_kb" "rm -rf ~/Library/Developer/Xcode/DerivedData" ""
fi

if [ -d "$HOME/.Trash" ]; then
  trash_kb=$(measure_dir "$HOME/.Trash")
  add_item "System" "Trash" "$trash_kb" "rm -rf ~/.Trash/*" "Permanent deletion — cannot be undone"
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
    printf "        ${YELLOW}! %s${RESET}\n" "${ITEM_WARNINGS[$i]}"
  fi
done

# Downloads info
if [ -d "$HOME/Downloads" ]; then
  dl_kb=$(measure_dir "$HOME/Downloads")
  dl_bytes=$((dl_kb * 1024))
  if [ "$dl_bytes" -ge 1073741824 ]; then
    printf "\n  ${DIM}(i) Downloads: $(bytes_to_human $dl_bytes) — run 'open ~/Downloads' to review${RESET}\n"
  fi
fi

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
  # Handle stale node_modules specially
  if [[ "${ITEM_LABELS[$idx]}" == "node_modules (stale)" ]]; then
    printf "        ${DIM}\$ rm -rf <each stale project>/node_modules${RESET}\n"
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
      dirty=$(git -C "$proj_dir" status --porcelain 2>/dev/null)
      [ -n "$dirty" ] && continue
      last_epoch=$(git -C "$proj_dir" log -1 --format="%at" 2>/dev/null)
      [ -z "$last_epoch" ] && continue
      now_epoch=$(date +%s)
      age_days=$(( (now_epoch - last_epoch) / 86400 ))
      [ "$age_days" -lt "$STALE_DAYS" ] && continue
      rm -rf "$nm_path" 2>/dev/null
    done < <(find "$PROJECTS_DIR" -maxdepth 3 -name node_modules -type d 2>/dev/null)
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
