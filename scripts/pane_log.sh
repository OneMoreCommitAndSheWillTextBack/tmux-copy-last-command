#!/usr/bin/env bash
set -euo pipefail

pane_id="${1:?pane id is required}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-copy-last-command"

mkdir -p "$state_dir"
cat >>"${state_dir}/pane-${pane_id#%}.raw"
