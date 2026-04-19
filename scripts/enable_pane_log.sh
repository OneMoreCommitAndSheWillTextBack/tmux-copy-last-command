#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pane_id="${1:?pane id is required}"
pane_cmd="$(tmux display-message -p -t "$pane_id" '#{pane_current_command}')"

case "$pane_cmd" in
  bash|sh|zsh|fish) ;;
  *)
    tmux pipe-pane -t "$pane_id" || true
    exit 0
    ;;
esac

tmux pipe-pane -o -t "$pane_id" "$CURRENT_DIR/pane_log.sh $pane_id" || true
