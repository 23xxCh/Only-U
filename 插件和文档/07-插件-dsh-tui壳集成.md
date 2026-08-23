# ⑦ dsh-TUI 壳集成

## 1. 概述

功能域：**界面壳**。dsh-TUI 是 deepseek-harness 官方 CLI 的第三方终端 UI 插件（Claude Code 风格全屏 TUI），Only-U 有网时用它作为运维 Agent 的界面与入口。01–06 插件都装在 profile 里，由 dsh-TUI 呈现工具卡、审批确认条和对话。

- npm 包：`@deepseek-harness-tui/dsh-tui`（0.8.8）
- 上游：https://github.com/ccch1mneyyy/dsh-TUI
- 开发状态：已集成；仓库内 `dsh-tui\` 是源码快照（改界面用，非运行入口）

## 2. 构成

| 组件 | 位置 | 用途 |
|------|------|------|
| npm 包（运行时） | profile `dsh-tui` 的 node_modules | U 盘和开发机的实际运行壳 |
| 源码快照 | 仓库 `dsh-tui\`（0.8.8） | 定制界面时改它，改完回馈上游 |
| 适配层边界 | `dsh-tui\ADAPTER.md` | 上游 import 纪律 + 契约门禁 |

## 3. 集成要点

**安装 / 启动 / 升级**：

```bat
cd dsh
pnpm dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
pnpm dsh --profile dsh-tui          :: 启动
:: 升级：同 add 命令带版本号；禁止用 TUI 内 /update（会找全局 dsh.cmd）
pnpm dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@<版本>
```

**改界面约束**（改 `dsh-tui\` 源码前必读 ADAPTER.md）：
- 官方 `@deepseek-ai/*` 包只允许在 `src/dsh-adapter/` 内 import；UI 层（screens/components/ink/hooks/utils）一律经 adapter facade 间接访问。
- 门禁：`pnpm run verify:boundary`（越界 import 即失败，已挂进 build）。
- 上游契约：校验版本线 `0.1.1-rc.2`；patch 面变更由 `verify:patch-surface` 拦截。

## 4. TUI 插件开发接缝（给本项目的插件用）

dsh-TUI 为第三方插件提供运行时接缝（详见 `dsh-tui\docs\plugins.md`），与本项目相关的：

| 接缝 | 用途 | 本项目用法 |
|------|------|------------|
| `ctx.skills` | 技能注册表 | 06 挂 SKILL.md |
| `ctx.tools` | 工具注册（来自 dsh 内核） | 01–15 各功能插件注册工具 |
| `ctx.approval` | 审批服务 → TUI 确认条 | 02 的 -Execute、04/05/09–15 的写盘/压测/写系统工具确认 |
| `tuiShortcuts` | 注册额外组合键（必须带 Ctrl 或 Alt） | 可选：快捷触发诊断 |
| commands 注册表 | 斜杠命令（`/plan`、`/goal` 等，本地与注册表合并） | 可选：`/diagnose` 快捷命令 |
| 主题/技能静态资源 | Themes、skills 静态目录 | 可选：定制配色 |

**插件契约**（dsh-TUI 官方文档要求，写插件时遵守）：
- 导出三件面：`export const name` / `export type Config` + `export const Config`（Schemastery）/ `export function apply(ctx, config)`；无 default export。
- 每个 config 键必须有默认值；插件缺失时降级为「什么都不发生」，绝不拖垮 TUI 启动。
- 资源清理用 `ctx.effect(() => () => { … })`；探测可选接缝用 `ctx.get('service', false)` 静默降级，绝不 throw。

**权限存储**：`~/.dsh-tui/extension-grants.json`——8 个注册权限默认 7 拒 1 允（`commands.invoke` 默认允许），未注册权限名一律拒绝。文件缺失=全默认；损坏=fail-closed。本项目插件（01–15）走 dsh 内核的 tools/approval 通道，不申请 TUI 扩展权限，因此不需要动这个文件。

## 5. 应用场景（什么时候用得上）

| 场景 | 说明 |
|------|------|
| 有网运维会话 | 插盘双击 Start-Agent.cmd → TUI → 直接说人话（见 06 调度总表） |
| 无网 / TUI 起不来 | 退回离线脚本路径（`诊断.cmd` / `清理预览.cmd`），讲「Agent 层用同一套脚本」 |
| 定制界面 | 改 `dsh-tui\` 快照（守 ADAPTER.md 边界），改完可回馈上游 |

## 6. 安装方法（U 盘交付视角）

- 开发机：上面「集成要点」的 add 命令，装进 profile `dsh-tui`。
- U 盘：由 08 打包插件把整个 profile（含 dsh-TUI 包与 01–06 各插件）拷进盘，客户机零安装。详见 [08-插件-U盘打包迁移.md](08-插件-U盘打包迁移.md)。

## 7. 与 01–06 的关系

- ⑦ 只做呈现与交互（输入框、工具卡、确认条、状态行），不实现任何运维功能。
- 01–06 是 dsh 内核插件，与 ⑦ 解耦：没有 ⑦ 时（纯 harness/headless），工具仍可被调用（确认条则无人应答，fail-closed 拒绝）。
- 升级 ⑦ 不影响 01–06；升级 dsh 内核需跑 `pnpm run build` + 三道门禁（见 ADAPTER.md 升级流程）。
