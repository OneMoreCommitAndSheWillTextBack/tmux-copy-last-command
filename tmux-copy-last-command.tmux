#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

copy_script="$CURRENT_DIR/scripts/copy_last_command.py"
enable_log_script="$CURRENT_DIR/scripts/enable_pane_log.sh"
enable_all_script="$CURRENT_DIR/scripts/enable_pane_log_all.sh"
clean_script="$CURRENT_DIR/scripts/clean_pane_log.sh"
prune_script="$CURRENT_DIR/scripts/prune_pane_logs.sh"

tmux bind-key Y run-shell -b "$copy_script \"#{pane_id}\""
tmux set-hook -g after-new-session "run-shell \"$enable_all_script\""
tmux set-hook -g after-new-window "run-shell \"$enable_log_script #{pane_id}\""
tmux set-hook -g after-split-window "run-shell \"$enable_log_script #{pane_id}\""
tmux set-hook -g pane-exited "run-shell -b \"$prune_script\""
tmux set-hook -g after-kill-pane "run-shell -b \"$prune_script\""
tmux run-shell -b "$enable_all_script"
tmux run-shell -b "$prune_script"
