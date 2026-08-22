# Only-U PRD：dsh-TUI 开发路线

- 文档状态：**路线笔记，不是实现依据。** 交付以 [`plan.md`](plan.md) + [ADR-0005](adr/0005-usb-baked-dsh-runtime.md) 为准。冲突时以 ADR-0002（范围）和 ADR-0005（烤盘）为准。
- 日期：2026-08-22
- 路线决策：[ADR-0004](adr/0004-dev-base-dsh-tui.md)（本文是其需求展开）
- 取代关系：`docs/Only-U-项目需求文档.md`（长 PRD）仍是归档证据，不是基线（[ADR-0002](adr/0002-canonical-hackathon-scope.md)）。本文不扩范围，只换技术路线。

## 1. 路线变更：为什么是 dsh-TUI

**事实**：官方 DeepSeek Harness CLI（npm 包 `@deepseek-ai/dsh`，当前 0.1.1-rc.x）只内置 `web`（本地 Web UI）与 `headless`（一句退出）两个入口模板，**没有 TUI 界面**。

**旧路线（已废弃）**：把整个 harness 源码 vendor 进 `dsh/`，本地 `pnpm install && pnpm run build`，再 `pnpm dsh --profile dsh-tui`。问题：Windows 全量构建慢且脆；评委机不可能构建；仓库体积大。

**新路线（本文）**：直接采用 [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI)（npm 包 `@deepseek-harness-tui/dsh-tui`）作为有网 Agent 壳与开发基座：

- **运行时**：官方 `dsh` CLI 从 npm 安装（全局或 U 盘烘焙），profile `dsh-tui` 用 `dsh plugin` 安装插件；**不 vendor、不构建 harness 源码**。
- **源码**：dsh-TUI 源码快照入库 `dsh-tui/`（v0.8.8，来源见 `dsh-tui/UPSTREAM.md`），作为开发参考与定制基线；harness 内核始终以 npm 分发版为准。
- **能力**：Only-U 的全部能力仍然只有 portable 脚本 + skill `only-u-ops`（ADR-0002 锁定的范围不变）。

dsh-TUI 本身是 harness 之上的**纯插件**（零内核改动）：会话日志、模型调用、工具执行、fork/resume、compaction、持久化都由 DSH 服务层拥有；TUI 只做终端交互与呈现。会话 JSONL 落在 `$DSH_HOME/sessions`，与 `dsh web` 互通（`/resume` 互相可见）。

## 2. 产品定义（不变）

U盘即插即用的运维 Agent：插上就能做**诊断**和带**误删防护**的**清理**。术语一律用根目录 [`CONTEXT.md`](../CONTEXT.md)。无网走**离线路径**（只诊断），有网走**TUI 路径**。产品范围不因路线变更扩大：不做 41 条 FR、不做 Web 主入口、不做无线网卡（ADR-0001/0002）。

## 3. 架构

```text
评委/用户
 ├─ 无网（离线路径）: portable\diagnose.cmd / clean.cmd（预览）
 └─ 有网（TUI 路径）: portable\start.cmd
     └─ dsh CLI（npm @deepseek-ai/dsh，官方内核，不 vendor 源码）
         └─ profile: dsh-tui（$DSH_HOME\profiles\dsh-tui）
             ├─ bundle: @deepseek-ai/dsh-base（DSH 服务层）
             └─ bundle: @deepseek-harness-tui/dsh-tui（TUI 表面）
                 └─ skill: only-u-ops（Only-U 运维能力）
                     └─ 只调 portable\*.ps1（与离线路径同一套脚本）
```

要点：

- `dsh-tui/` 源码快照只作参考/定制基线；改它先读 `dsh-tui/ADAPTER.md`——上游 `@deepseek-ai/*` 包只允许在 `src/dsh-adapter/` 内 import。
- 配置叠加顺序：`dsh-base` bundle → dsh-tui bundle patch → profile 的 `cordis.patch.yml` → `--patch` 覆盖层。
- 会话与数据全部落在 `$DSH_HOME`（U 盘烘焙时由 `start.cmd` 指向 `portable\.dsh-home`），不污染评委机。
- 清理逻辑不写两份：TUI 里的 Agent 调的就是 `portable\clean.ps1`，与离线预览同一套脚本。

## 4. 需求范围

只做下列 FR（映射 [`plan.md`](plan.md) 第 5 节切片，编号供 Issue 引用）：

| # | 需求 | 切片 / Issue |
|---|---|---|
| FR-1 | 便携启动：`start.cmd` 包装 `dsh --profile dsh-tui`；盘上烘焙 node.exe + dsh CLI + dsh-tui profile；缺件时人话报错并指向 `diagnose.cmd` | 便携启动（Issue #1，按新烘焙路径更新） |
| FR-2 | 离线诊断地板：`diagnose.cmd` 只读体检，扫描限时限量不卡死 | 离线诊断（Issue #2） |
| FR-3 | 安全清理：`clean.cmd` 默认预览；`-Execute` 只清白名单临时目录 | 安全清理 |
| FR-4 | TUI 路径接线：profile `dsh-tui` + skill `only-u-ops`；Agent 只调 portable 脚本，预览后等人确认才执行 | DSH 接线 |
| FR-5 | 演示保障：3 分钟讲稿 + 失败退回脚本演示 | 演示机 + 讲稿 |

非功能需求（硬性）：

- **误删防护**：清理一律预览→确认；永不碰桌面/文档/下载/图片。
- **凭据安全**：Key 只在 `portable/.env`（gitignore），永不打印、不进 Git。
- **性能**：诊断全程 ≤60s；单目录扫描限时限量，超限跳过不卡死。
- **平台**：Windows 10/11 优先；PowerShell 5 兼容（ps1 用 UTF-8 BOM）。
- **合规**：不做后门/BadUSB/凭据窃取/攻击扫描/自媒体自动化。

## 5. 安装与启动（canonical commands）

前置：Node `^22.19 || >=24`、pnpm 10+（装 profile 用）、`DEEPSEEK_API_KEY`（可选 `DEEPSEEK_BASE_URL` 指向 AI Ping，只放 `portable/.env`）。

开发机一次性：

```bat
npm install -g @deepseek-ai/dsh
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
```

日常（在仓库根目录；运维会话的 workspace 就是当前目录）：

```bat
dsh --profile dsh-tui
rem 等价：dsh-tui\dsh-tui.cmd（--resume 恢复上次会话）
```

升级（不要用 TUI 里的 `/update`，它会找全局 `dsh.cmd`）：

```bat
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@<版本>
```

源码级开发（可选，仅当要定制 TUI 表面）：

```bat
cd dsh-tui
pnpm install --frozen-lockfile
pnpm build
pnpm smoke
```

## 6. 验收标准

1. 任意 Win 机无网能出诊断报告（地板）。
2. 清理默认预览；`-Execute` 只清白名单临时目录。
3. 有网时 `start.cmd` 拉起 TUI，Agent 按 skill 跑诊断/清理并先预览、等人确认。
4. dsh-TUI 起不来时演示仍成立（退回脚本，讲「Agent 层用同一套脚本」）。
5. 评委能复述「不用安装、不敢乱删」。

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| dsh-TUI 是 0.x rc，上游会 breaking | 锁版本；`upstream drift` 警告可忽略；地板是脚本 |
| Windows 无沙箱后端（dsh-TUI 在 win32 回落 `danger-full-access` + 免审批） | 安全边界放在脚本层：白名单 + 预览确认；演示时人盯 |
| TUI `/update` 找全局 `dsh.cmd` | 禁用；升级走 `dsh plugin add` |
| `/model` 切换 = 会话 fork 续聊 | 演示前选定模型，不在演示中切 |
| 演示机无网 / CLI 缺件 | `start.cmd` fail-fast 人话报错，指向 `diagnose.cmd` |
| profile 在本机 `~/.dsh`，不进 Git | U 盘烘焙拷到 `portable\.dsh-home\profiles\dsh-tui`，`start.cmd` 设 `DSH_HOME` |

## 8. 里程碑

对齐 [`plan.md`](plan.md) 第 7 节实现顺序；五张切片对应第 4 节 FR 表。本文不新增里程碑、不新增范围。
