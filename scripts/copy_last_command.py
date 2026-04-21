#!/usr/bin/env python3

import os
import re
import subprocess
import sys
from pathlib import Path


MAX_RAW_BYTES = 2 * 1024 * 1024
PROMPT_RE = re.compile(r"\x1b]133;A(?:\x1b\\|\x07)")
OUTPUT_RE = re.compile(r"\x1b]133;C(?:\x1b\\|\x07)")
OSC_RE = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
CSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ESC_RE = re.compile(r"\x1b[@-_]")
SELF_RE = re.compile(r"(?:^|[ \t/])tmux-copy-last-command(?:[ \t]|$)")
SHELL_COMMANDS = {"bash", "sh", "zsh", "fish"}


def tmux(*args, **kwargs):
    capture = kwargs.pop("capture", False)
    text = kwargs.pop("text", None)
    check = kwargs.pop("check", True)
    result = subprocess.run(
        ["tmux"] + list(args),
        check=check,
        universal_newlines=True,
        input=text,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    if capture:
        return result.stdout
    return ""


def inside_tmux():
    return bool(os.environ.get("TMUX"))


def state_dir():
    return Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "tmux-copy-last-command"


def pane_suffix(pane):
    return pane.lstrip("%")


def history_file(pane):
    return state_dir() / f"history-{pane_suffix(pane)}.log"


def raw_log_file(pane):
    return state_dir() / f"pane-{pane_suffix(pane)}.raw"


def read_recent_text(path, max_bytes=MAX_RAW_BYTES):
    if not path.exists():
        return ""

    with path.open("rb") as handle:
        handle.seek(0, os.SEEK_END)
        size = handle.tell()
        handle.seek(max(0, size - max_bytes))
        return handle.read().decode(errors="ignore")


def clean(text):
    text = PROMPT_RE.sub("", text)
    text = OUTPUT_RE.sub("", text)
    text = OSC_RE.sub("", text)
    text = CSI_RE.sub("", text)
    text = ESC_RE.sub("", text)
    return text.replace("\r", "").strip("\n")


def read_history(pane):
    path = history_file(pane)
    if not path.exists():
        return []
    return [line.rstrip("\n") for line in path.read_text(errors="ignore").splitlines() if line.strip()]


def extract_outputs(pane):
    path = raw_log_file(pane)
    raw = read_recent_text(path)
    if not raw:
        return []

    outputs = list(OUTPUT_RE.finditer(raw))
    prompts = list(PROMPT_RE.finditer(raw))
    if not outputs or not prompts:
        return []

    blocks = []
    prompt_index = 0
    for output in outputs:
        while prompt_index < len(prompts) and prompts[prompt_index].start() < output.end():
            prompt_index += 1
        if prompt_index >= len(prompts):
            break

        prompt = prompts[prompt_index]
        blocks.append(clean(raw[output.end() : prompt.start()]))

    return blocks


def fail(message, exit_code=0):
    if inside_tmux():
        subprocess.run(["tmux", "display-message", message], check=False)
        return 0
    else:
        sys.stderr.write(message + "\n")
    return exit_code


def main():
    pane = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TMUX_PANE")
    if not pane:
        return fail("tmux-copy-last-command: not inside tmux", exit_code=1)

    try:
        pane_command = tmux("display-message", "-p", "-t", pane, "#{pane_current_command}", capture=True).strip()
    except subprocess.CalledProcessError as error:
        details = (error.stderr or "").strip()
        if not details:
            details = "unable to query tmux pane state"
        return fail(f"tmux-copy-last-command: failed to inspect pane {pane}: {details}", exit_code=1)

    if pane_command not in SHELL_COMMANDS:
        return fail("Current pane is running '{0}'. Use this at a shell prompt.".format(pane_command or "unknown"))

    commands = read_history(pane)
    outputs = extract_outputs(pane)
    if not commands:
        return fail("No shell history snapshot yet. Run 'source ~/.bashrc' in this pane and execute a command first.")
    if not outputs:
        return fail("No pane output log yet. Reload tmux config, open a new pane, or execute another shell command first.")

    pair_count = min(len(commands), len(outputs))
    if pair_count == 0:
        return fail("No previous non-empty command block found yet")

    pairs = list(zip(commands[-pair_count:], outputs[-pair_count:]))
    block = None
    for command_text, output_text in reversed(pairs):
        if SELF_RE.search(command_text):
            continue
        parts = [command_text]
        if output_text:
            parts.append(output_text)
        block = "\n".join(parts)
        break

    if block is None:
        return fail("No previous non-empty command block found yet")

    tmux("set-buffer", "--", block)
    try:
        subprocess.run(
            ["xclip", "-selection", "clipboard", "-i"],
            input=block,
            universal_newlines=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        tmux("display-message", "Copied to tmux buffer, but xclip failed")
        return 0

    lines = block.count("\n")
    if not block.endswith("\n"):
        lines += 1
    tmux("display-message", "Copied previous command block ({0} lines)".format(lines))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        sys.exit(fail(f"tmux-copy-last-command: unexpected error: {error}", exit_code=1))
