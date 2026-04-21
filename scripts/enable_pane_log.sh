#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pane_id="${1:?pane id is required}"
retry_count="${2:-${TMUX_COPY_LAST_COMMAND_ENABLE_RETRIES:-10}}"
retry_delay="${TMUX_COPY_LAST_COMMAND_RETRY_DELAY:-0.2}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-copy-last-command"
history_file="${state_dir}/history-${pane_id#%}.log"

schedule_retry() {
  local next_retry="${1:?retry count is required}"
  local cmd

  [ "$next_retry" -gt 0 ] || return 0

  printf -v cmd '%q %q %q' "$CURRENT_DIR/enable_pane_log.sh" "$pane_id" "$next_retry"
  tmux run-shell -b "sleep $retry_delay; $cmd" || true
}

pane_dead="$(tmux display-message -p -t "$pane_id" '#{pane_dead}' 2>/dev/null || true)"
[ -n "$pane_dead" ] || exit 0
[ "$pane_dead" = "0" ] || exit 0

pane_pipe="$(tmux display-message -p -t "$pane_id" '#{pane_pipe}' 2>/dev/null || true)"
[ "$pane_pipe" = "1" ] && exit 0

pane_cmd="$(tmux display-message -p -t "$pane_id" '#{pane_current_command}' 2>/dev/null || true)"
should_attach=0

case "$pane_cmd" in
  bash|sh|zsh|fish)
    should_attach=1
    ;;
esac

[ -f "$history_file" ] && should_attach=1

if [ "$should_attach" = "1" ]; then
  tmux pipe-pane -o -t "$pane_id" "$CURRENT_DIR/pane_log.sh $pane_id" || true
fi

schedule_retry "$((retry_count - 1))"
