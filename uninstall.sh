#!/bin/bash
set -e

PLUGIN_NAME="com.ulanzi.toolbox.ulanziPlugin"
PLUGIN_DIR="${HOME}/Library/Application Support/Ulanzi/UlanziDeck/Plugins"
ICONS_DIR="${HOME}/Library/Application Support/Ulanzi/UlanziDeck/Icons"
ICON_PACK_NAME="Dev Tools"
ULANZI_APP="/Applications/Ulanzi Studio.app"

main() {

if [ -t 1 ]; then
  BOLD="\033[1m" GREEN="\033[32m" YELLOW="\033[33m" RED="\033[31m" CYAN="\033[36m" RESET="\033[0m"
else
  BOLD="" GREEN="" YELLOW="" RED="" CYAN="" RESET=""
fi

info()  { printf "${CYAN}[info]${RESET}  %s\n" "$1"; }
ok()    { printf "${GREEN}[ok]${RESET}    %s\n" "$1"; }
fail()  { printf "${RED}[fail]${RESET}  %s\n" "$1"; exit 1; }

DEST="${PLUGIN_DIR}/${PLUGIN_NAME}"

printf "\n  ${BOLD}Dev Tools — Uninstaller${RESET}\n\n"

if [ ! -d "$DEST" ]; then
  fail "Plugin not installed (${PLUGIN_NAME} not found in Plugins directory)."
fi

info "Removing ${PLUGIN_NAME}..."
rm -rf "$DEST"
ok "Plugin removed"

if [ -d "${ICONS_DIR}/${ICON_PACK_NAME}" ]; then
  info "Removing icon pack '${ICON_PACK_NAME}'..."
  rm -rf "${ICONS_DIR}/${ICON_PACK_NAME}"
  ok "Icon pack removed"
fi

# Remove backups too?
BACKUPS=$(find "$PLUGIN_DIR" -maxdepth 1 -name "${PLUGIN_NAME}.backup-*" -type d 2>/dev/null)
if [ -n "$BACKUPS" ]; then
  printf "\n  Found backup(s):\n"
  echo "$BACKUPS" | while read -r b; do printf "    %s\n" "$(basename "$b")"; done
  printf "\n  Remove backups too? [y/N] "
  read -r answer || answer="n"
  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    echo "$BACKUPS" | while read -r b; do rm -rf "$b"; done
    ok "Backups removed"
  fi
fi

printf "\n"
if pgrep -x "Ulanzi Studio" &>/dev/null; then
  printf "  Restart Ulanzi Studio? [Y/n] "
  read -r answer || answer="n"
  if [ "$answer" != "n" ] && [ "$answer" != "N" ]; then
    info "Restarting Ulanzi Studio..."
    pkill -x "Ulanzi Studio" 2>/dev/null || true
    sleep 2
    open "$ULANZI_APP"
    ok "Ulanzi Studio restarted"
  fi
fi

printf "\n  ${GREEN}${BOLD}Dev Tools has been uninstalled.${RESET}\n\n"

}

main "$@"
