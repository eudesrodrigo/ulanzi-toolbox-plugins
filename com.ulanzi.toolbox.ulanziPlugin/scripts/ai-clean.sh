#!/bin/bash
trap 'exit 2' INT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v claude &>/dev/null; then
  printf "\n  Error: 'claude' CLI not found in PATH.\n"
  printf "  Install: https://docs.anthropic.com/en/docs/claude-code\n\n"
  printf "  Press Enter to close...\n"
  read -r
  exit 1
fi

claude --dangerously-skip-permissions \
  --append-system-prompt-file "$SCRIPT_DIR/ai-clean-system-prompt.md" \
  "Scan this Mac for reclaimable disk space. Show me what you find and ask before cleaning anything."
