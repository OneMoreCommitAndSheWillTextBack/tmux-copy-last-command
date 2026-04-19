#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-copy-last-command"
[ -d "$state_dir" ] || exit 0

active_panes="$(mktemp)"
trap 'rm -f "$active_panes"' EXIT

tmux list-panes -a -F '#{pane_id}' | sed 's/^%//' | sort -u >"$active_panes"

find "$state_dir" -maxdepth 1 -type f \
  \( -name 'history-*.log' -o -name 'pane-*.raw' \) -print0 |
while IFS= read -r -d '' path; do
  name="$(basename "$path")"
  pane_suffix="${name#*-}"
  pane_suffix="${pane_suffix%.*}"

  if ! grep -qx -- "$pane_suffix" "$active_panes"; then
    rm -f -- "$path"
  fi
done

rmdir --ignore-fail-on-non-empty "$state_dir" 2>/dev/null || true
