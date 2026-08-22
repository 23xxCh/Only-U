# 有网 Agent 壳使用 dsh-TUI

无网地板仍是 `portable\diagnose.cmd`。有网的 **运维会话** 不再用 `headless` 一句退出，也不把 Web 当主入口。二次开发基于 [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI) 的终端界面，Agent 仍调用同一套 portable 脚本。

**Status:** accepted

## Canonical commands

开发机（仓库已 `pnpm install` + `pnpm run build`）：

```bat
cd dsh
pnpm dsh --profile dsh-tui
```

恢复会话：`pnpm dsh --profile dsh-tui --resume <id>`

装/升级插件（不要用 Git URL，不要用 TUI 里的 `/update`——它会找全局 `dsh.cmd`）：

```bat
cd dsh
pnpm dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
```

包名：`@deepseek-harness-tui/dsh-tui`。文档里的 `github:deepseek-harness/turtle-ui` 仓库不存在，不要用。

Profile 在本机 `%USERPROFILE%\.dsh\profiles\dsh-tui`，不进 Git。U 盘烘焙时拷到 `portable\.dsh-home\profiles\dsh-tui`，由 `start.cmd` 设 `DSH_HOME`。

Key 只放 `dsh\.env` / `portable\.env`（gitignore）。`upstream drift` 警告可忽略，直到 TUI 发新版本再 `plugin add @…@版本`。

## Do

- Only-U skill、portable 脚本、`start.cmd` 包装 `dsh --profile dsh-tui`
- TUI 里优先跑 `diagnose.ps1` / `clean.ps1`（预览后才 `-Execute`）

## Do not

- Fork `dsh/` 或 fork dsh-TUI 源码进本仓库
- 把 `~/.dsh` vendor 进 Git
- 以 Web UI 或 TUI 当无网唯一入口
- 无网禁止诊断（仍走 ADR-0002）

## Considered options

- 继续 headless 一句退出（否决：二次开发要可交互终端）
- TUI 当唯一入口、丢掉 diagnose.cmd（否决：评委机可能没编过 DSH）
- 离线脚本地板 + TUI 作为有网壳（采纳）
