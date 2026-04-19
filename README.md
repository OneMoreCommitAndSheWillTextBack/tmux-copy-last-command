# tmux-copy-last-command

Chinese documentation is available in `README_ZH.md`.

`tmux-copy-last-command` is a local tmux plugin that copies the previous command block when you press `prefix + Y`.

In this plugin, a "command block" means:

- the command line itself
- the output that was visibly rendered in the pane for that command

The current implementation targets `bash + tmux`.

## Features

- Copy the previous command block with `prefix + Y`
- Write the result to both the tmux buffer and the system clipboard
- Automatically enable output logging for new shell panes
- Automatically clean stale logs when panes are closed
- Prune orphaned runtime logs whenever the plugin is loaded

## Project Layout

```text
tmux-copy-last-command/
├── .gitignore
├── README.md
├── README_ZH.md
├── tmux-copy-last-command.tmux
├── scripts/
│   ├── clean_pane_log.sh
│   ├── copy_last_command.py
│   ├── enable_pane_log.sh
│   ├── enable_pane_log_all.sh
│   ├── pane_log.sh
│   └── prune_pane_logs.sh
└── shell/
    └── bash.sh
```

## Requirements

- `tmux`
- `bash`
- `python3`
- `xclip`

If `xclip` is unavailable, the plugin still writes to the tmux buffer, but it will not update the system clipboard.

## Loading

### tmux

Load the plugin entrypoint from `.tmux.conf`:

```tmux
if-shell '[ -x ~/.tmux/plugins/tmux-copy-last-command/tmux-copy-last-command.tmux ]' \
  'run-shell ~/.tmux/plugins/tmux-copy-last-command/tmux-copy-last-command.tmux'
```

### bash

Add this to `.bashrc`:

```bash
if [ -n "${TMUX:-}" ]; then
  __tmux_copy_last_command_bash_plugin="$HOME/.tmux/plugins/tmux-copy-last-command/shell/bash.sh"
  if [ -f "$__tmux_copy_last_command_bash_plugin" ]; then
    . "$__tmux_copy_last_command_bash_plugin"
  fi
  unset __tmux_copy_last_command_bash_plugin
fi
```

Notes:

- The shell integration is only loaded inside tmux.
- Existing shell panes need `source ~/.bashrc` once.
- Newly created panes pick it up automatically.

## Usage

Default key binding:

```text
prefix + Y
```

What happens:

1. Read the recent history snapshot for the current pane.
2. Extract the previous command's output block from the pane log.
3. Reconstruct a single text block.
4. Store it in the tmux buffer.
5. Send it to the system clipboard with `xclip`.

## How It Works

This plugin does not pull a structured "previous command object" from bash. Instead, it reconstructs the result from two sources:

- command text from a bash history snapshot
- output content from the pane's runtime log

### 1. Where the command text comes from

`shell/bash.sh` runs before each prompt is shown and does two things:

- writes recent history entries to `history-<pane>.log`
- emits an `OSC 133;A` marker

It also appends an `OSC 133;C` marker to `PS0`, so a marker is emitted right before command execution begins.

That gives the plugin a way to identify:

- when a command starts
- when control returns to the prompt

### 2. Where the output log comes from

`tmux-copy-last-command.tmux` installs `pipe-pane` logging for shell panes:

- `enable_pane_log.sh` enables logging for a pane
- `pane_log.sh` appends pane output to `pane-<pane>.raw`

This raw file is not a clean text log. It contains the terminal byte stream that was rendered in the pane, which may include:

- ordinary text output
- color escape sequences
- cursor movement
- full-screen redraws

### 3. How copying reconstructs a block

`copy_last_command.py`:

1. reads `history-<pane>.log`
2. reads the recent tail of `pane-<pane>.raw`
3. uses `OSC 133;C` and `OSC 133;A` to locate the output range
4. strips ANSI and OSC control sequences
5. picks the most recent command and matching output block
6. writes the result to the tmux buffer and clipboard

## Runtime Logs

Runtime state lives under:

```text
${XDG_RUNTIME_DIR:-/tmp}/tmux-copy-last-command
```

On most Linux desktop systems, that is usually:

```text
/run/user/<uid>/tmux-copy-last-command
```

This directory is not inside the plugin repository and is usually backed by runtime `tmpfs`, so:

- it can grow during the current login session
- it is usually removed after logout or reboot

## Cleanup Strategy

The cleanup mechanism has two layers.

### 1. Cleanup on pane close

The plugin reacts to these hooks:

- `pane-exited`
- `after-kill-pane`

It does not try to delete a single pane file based on hook arguments. Instead, it runs `prune_pane_logs.sh`, which:

- lists all currently active tmux panes
- removes any `history-*.log` or `pane-*.raw` file that no longer belongs to an active pane

This is intentional because tmux does not reliably expose the closed pane id in every hook context.

### 2. Cleanup when the plugin loads

Whenever the plugin is loaded, it also runs `prune_pane_logs.sh` once to remove stale leftovers from earlier sessions or older hook state.

## Current Limitations

This plugin copies the previous visible command block. It does not produce a perfect `stdin/stdout/stderr` recording.

What it can do reliably:

- recover the command line text
- recover output that was visibly rendered in the pane

What it cannot separate perfectly:

- `stdout` and `stderr` are mixed together
- true interactive `stdin` cannot be reconstructed completely
- here-docs, full-screen apps, REPLs, and editors may introduce extra screen redraw noise

So the accurate description is:

- copy the previous shell command and its visible output block

not:

- capture the full standard input and standard output streams with exact fidelity

## Performance Notes

To avoid tmux freezing during `prefix + Y`:

- the key binding runs through `run-shell -b`
- `copy_last_command.py` only reads the recent tail of the raw pane log

This avoids rescanning the entire pane log on every copy.

## FAQ

### Why does it work in new panes but not always in old ones?

Because older shell panes may not have reloaded `.bashrc`.

Run:

```bash
source ~/.bashrc
```

### Why do I see `pane-*.raw` files in the runtime directory?

Those are `pipe-pane` output logs for active panes.

### Why didn't logs disappear immediately after a pane was closed?

Under normal conditions they are pruned automatically. If tmux was just reloaded or hook state changed, reloading the plugin runs pruning again and removes stale files.

## Debugging

List active panes:

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{pane_current_command}'
```

Inspect the runtime log directory:

```bash
ls -lah "${XDG_RUNTIME_DIR:-/tmp}/tmux-copy-last-command"
```

Inspect the active hooks:

```bash
tmux show-hooks -g pane-exited
tmux show-hooks -g after-kill-pane
```

## Notes

This is currently a local plugin directory rather than a TPM-installable remote plugin, but the structure is already self-contained and ready to be managed or published as its own repository.
