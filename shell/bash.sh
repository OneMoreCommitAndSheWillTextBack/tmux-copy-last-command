#!/usr/bin/env bash

__tmux_osc133() {
  printf '\033]133;%s\033\\' "$1"
}

__tmux_copy_last_command_dir() {
  printf '%s/tmux-copy-last-command' "${XDG_RUNTIME_DIR:-/tmp}"
}

__tmux_copy_last_command_history_file() {
  local pane_id="${TMUX_PANE#%}"
  printf '%s/history-%s.log' "$(__tmux_copy_last_command_dir)" "$pane_id"
}

__tmux_pre_prompt() {
  local dir
  dir="$(__tmux_copy_last_command_dir)"
  mkdir -p "$dir"
  HISTTIMEFORMAT= builtin history 20 | sed 's/^ *[0-9]\+ *//' > "$(__tmux_copy_last_command_history_file)"
  __tmux_osc133 A
}

case ";${PROMPT_COMMAND:-};" in
*";__tmux_pre_prompt;"*) ;;
*)
  PROMPT_COMMAND="__tmux_pre_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
  ;;
esac

case "${PS0:-}" in
*$'\e]133;C\e\\'*) ;;
*)
  PS0="${PS0:-}"$'\e]133;C\e\\'
  ;;
esac
