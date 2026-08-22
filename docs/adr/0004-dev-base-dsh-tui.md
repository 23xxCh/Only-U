# 开发基座从 vendored harness 切换到 dsh-TUI

官方 `dsh`（DeepSeek Harness）最新版本只内置 `web` 与 `headless` 入口，**没有 TUI 界面**。旧路线把整个 harness 源码 vendor 进 `dsh/` 本地构建（`pnpm install && pnpm run build && pnpm dsh --profile dsh-tui`）：Windows 构建慢、仓库体积大、评委机无法复现。决定删除 `dsh/`，改为**直接使用 [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI)**（npm `@deepseek-harness-tui/dsh-tui`）作为有网 Agent 壳与开发基座：运行时用 npm 官方 `dsh` CLI + profile `dsh-tui`（`dsh plugin` 安装），dsh-TUI 源码快照入库 `dsh-tui/`（v0.8.8，见 `dsh-tui/UPSTREAM.md`）作参考与定制基线。harness 内核不再 vendor、不再本地构建。

**Status:** superseded for USB delivery by [ADR-0005](0005-usb-baked-dsh-runtime.md)

`dsh/` 源码快照已恢复，烤盘仍用它。`dsh-tui/` 源码快照可留作改 TUI 界面的参考；U 盘跑的是 npm 插件 `@deepseek-harness-tui/dsh-tui@0.8.8`，不是直接跑这个目录。不要再删除 `dsh/`。

## Canonical commands

```bat
npm install -g @deepseek-ai/dsh
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
dsh --profile dsh-tui
```

升级：`dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@<版本>`（不要用 TUI 里的 `/update`）。

## Do

- Only-U 能力仍是 portable 脚本 + skill `only-u-ops`（范围不变，[ADR-0002](0002-canonical-hackathon-scope.md)）
- 定制 TUI 表面时遵守 `dsh-tui/ADAPTER.md` 的 adapter 边界（上游包只在 `src/dsh-adapter/` 内 import）
- U 盘烘焙：node.exe + dsh CLI（npm 包目录，含依赖树）+ `%DSH_HOME%\profiles\dsh-tui`；`DSH_HOME=portable\.dsh-home`
- 需求展开与风险表见 [`docs/prd.md`](../prd.md)

## Do not

- 不 vendor harness 源码（旧 `dsh/` 已删除）
- 不维护分叉：`dsh-tui/` 是快照不是 fork，改动以能回上游为前提
- 不把 `~/.dsh` vendor 进 Git
- 不以 Web UI 或 TUI 当无网唯一入口（无网仍走离线脚本，[ADR-0003](0003-dsh-tui-agent-shell.md)）

## Considered options

- 继续 vendor harness 全源码本地构建（否决：Windows 构建慢脆、体积大、评委机无法复现）
- 等官方 dsh 内置 TUI（否决：当前最新版明确没有，时间表不可控）
- npm 官方 CLI + dsh-TUI 插件 + 源码快照作基线（采纳）
