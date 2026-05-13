#!/bin/bash
set -e

PLUGIN_NAME="com.ulanzi.toolbox.ulanziPlugin"
PLUGIN_DIR="${HOME}/Library/Application Support/Ulanzi/UlanziDeck/Plugins"
ICONS_DIR="${HOME}/Library/Application Support/Ulanzi/UlanziDeck/Icons"
REPO_URL="https://github.com/eudesrodrigo/ulanzi-toolbox-plugins"
ULANZI_APP="/Applications/Ulanzi Studio.app"
NODE_BUNDLED="${ULANZI_APP}/Contents/MacOS/NodeJS/node"

main() {

# --- Colors -----------------------------------------------------------
if [ -t 1 ]; then
  BOLD="\033[1m"
  CYAN="\033[36m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  RED="\033[31m"
  RESET="\033[0m"
else
  BOLD="" CYAN="" GREEN="" YELLOW="" RED="" RESET=""
fi

info()  { printf "${CYAN}[info]${RESET}  %s\n" "$1"; }
ok()    { printf "${GREEN}[ok]${RESET}    %s\n" "$1"; }
warn()  { printf "${YELLOW}[warn]${RESET}  %s\n" "$1"; }
fail()  { printf "${RED}[fail]${RESET}  %s\n" "$1"; exit 1; }

# --- Banner -----------------------------------------------------------
printf "\n${BOLD}${CYAN}"
cat << 'EOF'
  ____                _____           _
 |  _ \  _____   __  |_   _|__   ___ | |___
 | | | |/ _ \ \ / /    | |/ _ \ / _ \| / __|
 | |_| |  __/\ V /     | | (_) | (_) | \__ \
 |____/ \___| \_/      |_|\___/ \___/|_|___/

EOF
printf "${RESET}"
printf "  ${BOLD}Ulanzi D200 Plugin Installer${RESET}\n\n"

# --- Cleanup on error -------------------------------------------------
TMPDIR_CLONE=""
cleanup() {
  if [ -n "$TMPDIR_CLONE" ]; then rm -rf "$TMPDIR_CLONE"; fi
}
trap cleanup EXIT

# --- Pre-requisite checks ---------------------------------------------
info "Checking prerequisites..."

[ "$(uname)" = "Darwin" ] || fail "This plugin is macOS only."
ok "macOS detected"

if [ -d "$ULANZI_APP" ]; then
  ok "Ulanzi Studio found"
else
  fail "Ulanzi Studio not found at ${ULANZI_APP}. Install it first from https://www.ulanzi.com"
fi

if [ -d "$PLUGIN_DIR" ]; then
  ok "Plugins directory found"
else
  fail "Plugins directory not found at ${PLUGIN_DIR}. Open Ulanzi Studio at least once first."
fi

NODE_BIN=""
if [ -x "$NODE_BUNDLED" ]; then
  NODE_BIN="$NODE_BUNDLED"
  ok "Using Ulanzi's bundled Node.js ($("$NODE_BIN" --version))"
elif command -v node &>/dev/null; then
  NODE_BIN="$(command -v node)"
  ok "Node.js found ($("$NODE_BIN" --version))"
else
  fail "Node.js not found. Install it from https://nodejs.org"
fi

NPM_BIN=""
BUNDLED_NPM="${ULANZI_APP}/Contents/MacOS/NodeJS/npm"
if [ -x "$BUNDLED_NPM" ]; then
  NPM_BIN="$BUNDLED_NPM"
elif command -v npm &>/dev/null; then
  NPM_BIN="$(command -v npm)"
else
  fail "npm not found."
fi

printf "\n"

# --- Determine source -------------------------------------------------
PLUGIN_SRC=""
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

if [ -d "${SCRIPT_DIR}/${PLUGIN_NAME}" ]; then
  info "Installing from local repository..."
  PLUGIN_SRC="${SCRIPT_DIR}/${PLUGIN_NAME}"
else
  info "Downloading from GitHub..."
  TMPDIR_CLONE="$(mktemp -d)"
  git clone --depth 1 "$REPO_URL" "$TMPDIR_CLONE" 2>/dev/null \
    || fail "Failed to clone repository. Check your internet connection."
  PLUGIN_SRC="${TMPDIR_CLONE}/${PLUGIN_NAME}"
  [ -d "$PLUGIN_SRC" ] || fail "Plugin directory not found in downloaded repo."
fi

# --- Backup existing --------------------------------------------------
DEST="${PLUGIN_DIR}/${PLUGIN_NAME}"

if [ -d "$DEST" ]; then
  BACKUP="${DEST}.backup-$(date +%Y%m%d-%H%M%S)"
  warn "Existing installation found — backing up to $(basename "$BACKUP")"
  mv "$DEST" "$BACKUP"
fi

# --- Copy plugin ------------------------------------------------------
info "Copying plugin files..."
cp -R "$PLUGIN_SRC" "$DEST"
ok "Plugin files copied (including icons and assets)"

# --- Install dependencies ---------------------------------------------
info "Installing dependencies..."
cd "$DEST"
"$NPM_BIN" install --production --silent 2>/dev/null
ok "Dependencies installed"

# --- Install icon pack ------------------------------------------------
ICON_PACK_NAME="Dev Tools"
ICONS_SRC="${PLUGIN_SRC}/../icons"
if [ -d "$ICONS_SRC" ]; then
  ICON_DEST="${ICONS_DIR}/${ICON_PACK_NAME}"
  mkdir -p "$ICON_DEST"
  ICON_COUNT=0
  find "$ICONS_SRC" -type f -name "*.png" | while read -r f; do
    cp "$f" "$ICON_DEST/"
    ICON_COUNT=$((ICON_COUNT + 1))
  done
  INSTALLED=$(find "$ICON_DEST" -type f -name "*.png" | wc -l | tr -d ' ')
  ok "Icon pack '${ICON_PACK_NAME}' installed (${INSTALLED} icons → Icon Library)"
fi

# --- Restart Ulanzi Studio -------------------------------------------
printf "\n"
if pgrep -xq "Ulanzi Studio" 2>/dev/null; then
  printf "  Ulanzi Studio is running. Restart it to load the plugin? [Y/n] "
  read -r answer || answer="n"
  if [ "$answer" != "n" ] && [ "$answer" != "N" ]; then
    info "Restarting Ulanzi Studio..."
    pkill -x "Ulanzi Studio" 2>/dev/null || true
    sleep 2
    open "$ULANZI_APP"
    ok "Ulanzi Studio restarted"
  fi
fi

# --- Done -------------------------------------------------------------
printf "\n"
printf "  ${GREEN}${BOLD}Installation complete!${RESET}\n\n"
printf "  Open Ulanzi Studio and look for ${BOLD}Dev Tools${RESET} in the sidebar.\n"
printf "  Three actions available:\n"
printf "    • Run Command  — execute any terminal command\n"
printf "    • Run Script   — run a script file (.sh, .py, .js, etc.)\n"
printf "    • SSH Command  — run a command on a remote host\n\n"
printf "  To uninstall: ${CYAN}bash <(curl -fsSL ${REPO_URL}/raw/main/uninstall.sh)${RESET}\n\n"

}

main "$@"
