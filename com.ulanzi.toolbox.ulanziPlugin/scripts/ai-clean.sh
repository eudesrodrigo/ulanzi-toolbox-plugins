#!/bin/bash
set -o pipefail
trap 'printf "\n  Cancelled.\n"; rm -f "$REPORT_FILE"; exit 2' INT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCAN_PROMPT="$SCRIPT_DIR/ai-clean-scan-prompt.md"
EXEC_PROMPT="$SCRIPT_DIR/ai-clean-exec-prompt.md"
export REPORT_FILE
REPORT_FILE=$(mktemp /tmp/ai-clean-report-XXXXXX)

if [ -t 1 ]; then
  BOLD="\033[1m" CYAN="\033[36m" GREEN="\033[32m"
  YELLOW="\033[33m" RED="\033[31m" DIM="\033[2m" RESET="\033[0m"
else
  BOLD="" CYAN="" GREEN="" YELLOW="" RED="" DIM="" RESET=""
fi

# --- Banner ---
clear
printf "\n"
printf "  ${BOLD}${CYAN}AI Clean${RESET}\n"
printf "  ${DIM}Powered by Claude Code${RESET}\n"
printf "  ════════════════════════════════════════\n\n"

# --- Check claude CLI ---
if ! command -v claude &>/dev/null; then
  printf "  ${RED}Error: 'claude' CLI not found in PATH.${RESET}\n"
  printf "  Install: https://docs.anthropic.com/en/docs/claude-code\n\n"
  printf "  Press Enter to close...\n"
  read -r
  exit 1
fi

# --- Phase 1: Scan ---
printf "  ${YELLOW}Scanning disk with AI agent...${RESET}\n"
printf "  ${DIM}This may take 1-3 minutes.${RESET}\n\n"

claude -p "$(cat "$SCAN_PROMPT")" \
  --dangerously-skip-permissions \
  --output-format text \
  --max-turns 30 \
  --verbose

scan_exit=$?
if [ "$scan_exit" -ne 0 ]; then
  printf "\n  ${RED}Scan failed (exit code $scan_exit).${RESET}\n"
  printf "  Press Enter to close...\n"
  read -r
  rm -f "$REPORT_FILE"
  exit 1
fi

# --- Show report if written to file ---
if [ -s "$REPORT_FILE" ]; then
  printf "\n"
  cat "$REPORT_FILE"
  printf "\n"
fi

# --- Phase 2: Confirm ---
printf "\n  ${BOLD}Proceed with cleanup? [y/N]:${RESET} "
read -r answer
if [[ ! "$answer" =~ ^[Yy] ]]; then
  printf "\n  Cancelled.\n"
  rm -f "$REPORT_FILE"
  exit 2
fi

# --- Phase 3: Execute ---
printf "\n  ${YELLOW}Executing cleanup...${RESET}\n\n"
report_content=""
if [ -s "$REPORT_FILE" ]; then
  report_content=$(cat "$REPORT_FILE")
fi
rm -f "$REPORT_FILE"

exec_prompt=$(cat "$EXEC_PROMPT")
exec_prompt="${exec_prompt//\{REPORT_CONTENT\}/$report_content}"

claude -p "$exec_prompt" \
  --dangerously-skip-permissions \
  --output-format text \
  --max-turns 50 \
  --verbose

exec_exit=$?

printf "\n"
if [ "$exec_exit" -eq 0 ]; then
  printf "  ${GREEN}Cleanup complete!${RESET}\n"
else
  printf "  ${RED}Some operations may have failed.${RESET}\n"
fi

printf "\n  Press Enter to close...\n"
read -r
exit $exec_exit
