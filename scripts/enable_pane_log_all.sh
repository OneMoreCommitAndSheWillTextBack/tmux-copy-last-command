#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux list-panes -a -F '#{pane_id}' | while IFS= read -r pane_id; do
  [ -n "$pane_id" ] || continue
  "$CURRENT_DIR/enable_pane_log.sh" "$pane_id"
done
