#!/usr/bin/env bash
set -euo pipefail

pane_id="${1:-}"
[ -n "$pane_id" ] || exit 0

state_dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-copy-last-command"
pane_suffix="${pane_id#%}"

rm -f -- \
  "${state_dir}/history-${pane_suffix}.log" \
  "${state_dir}/pane-${pane_suffix}.raw"

rmdir --ignore-fail-on-non-empty "$state_dir" 2>/dev/null || true
