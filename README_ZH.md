# tmux-copy-last-command

英文文档见 `README.md`。

一个本地 tmux 插件，用来在 `prefix + Y` 时复制“上一条命令块”。

这里的“命令块”指的是：

- 该条命令的命令行文本
- 该条命令在 pane 中显示出来的输出内容

当前实现面向 `bash + tmux`。

## 功能

- 在 `prefix + Y` 时复制上一条命令块
- 同时写入 tmux buffer 和系统剪贴板
- 为新的 shell pane 自动开启输出记录
- 在 pane 关闭后自动清理对应日志
- 在插件加载时自动清扫已经失效的旧日志

## 目录结构

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

## 依赖

- `tmux`
- `bash`
- `python3`
- `xclip`

如果 `xclip` 不可用，插件仍然会写入 tmux buffer，但不会写入系统剪贴板。

## 加载方式

### tmux

在 `.tmux.conf` 中加载插件入口：

```tmux
if-shell '[ -x ~/.tmux/plugins/tmux-copy-last-command/tmux-copy-last-command.tmux ]' \
  'run-shell ~/.tmux/plugins/tmux-copy-last-command/tmux-copy-last-command.tmux'
```

### bash

在 `.bashrc` 中加入：

```bash
if [ -n "${TMUX:-}" ]; then
  __tmux_copy_last_command_bash_plugin="$HOME/.tmux/plugins/tmux-copy-last-command/shell/bash.sh"
  if [ -f "$__tmux_copy_last_command_bash_plugin" ]; then
    . "$__tmux_copy_last_command_bash_plugin"
  fi
  unset __tmux_copy_last_command_bash_plugin
fi
```

说明：

- 只在 tmux 内部加载
- 已经打开的旧 shell pane 需要执行一次 `source ~/.bashrc`
- 新开的 pane 会自动生效

## 使用方式

默认按键：

```text
prefix + Y
```

行为：

1. 从当前 pane 对应的历史快照里读取最近命令
2. 从当前 pane 的输出日志中切出上一条命令对应的输出块
3. 拼接成一个文本块
4. 写入 tmux buffer
5. 通过 `xclip` 写入系统剪贴板

## 它是怎么工作的

这个插件不是直接从 bash 里取“上一条命令对象”，而是把两部分信息拼起来：

- 命令文本来自 bash history 快照
- 输出内容来自 tmux pane 的实时输出日志

### 1. 命令文本从哪里来

`shell/bash.sh` 会在每次提示符出现前做两件事：

- 把最近的 history 写到运行时目录中的 `history-<pane>.log`
- 输出一个 `OSC 133;A` marker

另外它还会通过 `PS0` 在命令开始执行前输出 `OSC 133;C` marker。

这样插件就能知道：

- 命令什么时候开始
- 下一次提示符什么时候回来

### 2. 输出日志从哪里来

`tmux-copy-last-command.tmux` 会给 shell pane 注册 `pipe-pane`：

- `enable_pane_log.sh` 为 pane 开启日志
- `pane_log.sh` 把 pane 的输出追加到 `pane-<pane>.raw`

这个 raw 文件里不是纯文本日志，而是 pane 实际显示过的终端字节流，里面可能包含：

- 普通输出文本
- 颜色控制序列
- 光标移动
- 全屏程序刷屏内容

### 3. 复制时怎么切块

`copy_last_command.py` 会：

1. 读取 `history-<pane>.log`
2. 读取 `pane-<pane>.raw` 的最近一段尾部
3. 用 `OSC 133;C` 和 `OSC 133;A` 定位输出范围
4. 去掉 ANSI/OSC 控制序列
5. 取最近一对“命令 + 输出块”
6. 写入 tmux buffer 和系统剪贴板

## 日志文件在哪里

运行时文件放在：

```text
${XDG_RUNTIME_DIR:-/tmp}/tmux-copy-last-command
```

在大多数 Linux 桌面环境里，这通常是：

```text
/run/user/<uid>/tmux-copy-last-command
```

这个目录不是项目目录，也不是 home 仓库目录。常见情况下它位于运行时 `tmpfs`，因此：

- 当前登录会话中会增长
- 注销或重启后通常会被系统清掉

## 自动清理机制

当前清理策略有两层：

### 1. pane 关闭时清理

插件在这两个 hook 上触发清理：

- `pane-exited`
- `after-kill-pane`

但这里不是直接按 hook 参数删除单个 pane 文件，而是运行 `prune_pane_logs.sh`：

- 先取 tmux 当前仍然活着的 pane 列表
- 再删除运行时目录里所有“不属于活动 pane”的日志文件

这样做的原因是：某些 hook 上下文里，tmux 并不会稳定提供“刚被关闭的 pane id”。

### 2. 插件加载时清理

插件每次加载时也会主动执行一次 `prune_pane_logs.sh`，把之前遗留的失效日志一起清掉。

## 当前限制

这个插件复制的是“上一条命令块”，不是严格意义上的完整 `stdin/stdout/stderr` 记录。

当前能保证的部分：

- 命令行文本基本可得
- 在 pane 中显示出来的输出基本可得

当前不能严格区分的部分：

- `stdout` 和 `stderr` 会混在一起
- 交互式程序真正读入的 `stdin` 不能完整恢复
- here-doc、全屏程序、REPL、编辑器等场景可能会混入额外屏幕刷新内容

所以更准确的说法是：

- 复制上一条 shell 命令及其可见输出块

而不是：

- 完整复制上一条命令的全部标准输入和标准输出

## 性能策略

为了避免 `prefix + Y` 时卡住：

- `Y` 绑定使用 `run-shell -b` 后台执行
- `copy_last_command.py` 只读取 raw 日志尾部最近一段数据

这能避免每次复制都把整份 pane 历史重新扫一遍。

## 常见问题

### 为什么新 pane 里能工作，老 pane 里不一定行

因为老 pane 里的 shell 可能没有重新加载 `.bashrc`。

处理方式：

```bash
source ~/.bashrc
```

### 为什么日志目录里会有 `pane-*.raw`

这是 `pipe-pane` 记录下来的 pane 输出日志，属于运行时文件。

### 为什么关闭 pane 后日志没有立刻少

正常情况下会自动清理；如果 tmux 刚 reload 或 hook 状态有变化，重新加载插件后会再执行一次 prune，把失效日志清掉。

## 调试

查看当前活动 pane：

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{pane_current_command}'
```

查看当前日志目录：

```bash
ls -lah "${XDG_RUNTIME_DIR:-/tmp}/tmux-copy-last-command"
```

查看当前 hook：

```bash
tmux show-hooks -g pane-exited
tmux show-hooks -g after-kill-pane
```

## 备注

这个插件目前是本地插件目录形式，未接入 TPM 自动安装流程，但结构已经独立，可以直接单独管理、移动或发布到 Git 仓库。
