# Design: Only-U 黑客松演示（U盘包）

- 来源：gstack `/office-hours`（Builder）
- 状态：**已批准**（队长，2026-08-22）
- 仓库：https://github.com/23xxCh/Only-U
- 方案：**Approach B — 脚本地板 + TUI 调同一套脚本**
- 基线：本文件 + [`docs/plan.md`](../plan.md) + [`docs/prd.md`](../prd.md) + [ADR-0001](../adr/0001-software-only-usb-pack.md) + [ADR-0002](../adr/0002-canonical-hackathon-scope.md) + [ADR-0003](../adr/0003-dsh-tui-agent-shell.md) + [ADR-0004](../adr/0004-dev-base-dsh-tui.md)

gstack 只在本机当设计工作流，**不要**把 gstack 源码 vendor 进仓库。

## Problem

普通人不会装 Agent、不会配 Skill/MCP。修机现场常见 C 盘满、卡死、打印机异常。现状是队长用 U 盘跑 Claude Code 一台一台修。比赛要一个能插上就跑、评委 10 秒看懂的东西。

## Whoa

插上，双击，诊断报告出来。这台电脑上没有安装步骤。清理永远先预览。有网才打开 **TUI 路径**（dsh-TUI），用自然语言走同一套脚本。

## Constraints

- 一天半；Windows 优先
- 现场可能没网，DSH 可能编不过
- 无无线网卡（ADR-0001）
- 合法合规；不做后门、爬虫、BadUSB

## Premises

1. 产品是软件 **U盘包**。评委记住：插上、双击、出诊断，不用安装 Agent。
2. `portable\diagnose.cmd` 是地板。Agent 说「C 盘满了」再预览清理是加分。
3. 网卡、后门、自媒体本场不做。清理必须先预览。

## Approaches

| 方案 | 内容 | 本场 |
|---|---|---|
| A 脚本即产品 | 只演 diagnose/clean，Agent 只在讲稿 | 保底 |
| **B 脚本地板 + TUI 调同一脚本** | 双击诊断；有网 `dsh --profile dsh-tui`（`start.cmd` 包装它）调同一套 ps1，确认后才 `-Execute`；失败退回 A | **已选** |
| C TUI / 本地 Web 作为无网唯一入口 | 没编过 DSH 就演不了 | 本场不做 |

B 的地板等于 A。有网壳是 [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI)，不是 headless，也不是长 PRD 的 Web。清理逻辑不写两份。

## Demo（3 分钟）

1. 插盘或打开 `portable\`
2. `diagnose.cmd`：磁盘、临时目录、系统错误、打印机
3. `clean.cmd` 预览（不删桌面/文档/下载）
4. 有网：`dsh --profile dsh-tui`（交付用 `start.cmd` 包装同一 profile）。Agent 读 `CONTEXT.md` + skill `only-u-ops`，只调现有脚本
5. 收束：即插即用、不敢乱删。无线网卡是下一阶段

## Success

- 任意 Win 机无网能出诊断
- 清理默认预览；`-Execute` 只打白名单临时目录
- DSH 挂了演示仍成立
- 评委能复述「不用安装」

## Distribution

U 盘拷贝仓库 `portable/`，可选烘焙 node.exe + dsh CLI（npm 包目录）+ dsh-tui profile（ADR-0004）。本场不发 npm / 商店。密钥只放 `portable/.env`（gitignore），不进 Git。

## Out of scope（本场）

- 无线网卡、流量卡、PE、重装、BIOS
- 无网时禁止跑诊断（这是队友长 PRD 的条款，本场不采用）
- 以本地 Web UI 或 TUI 当无网唯一入口
- 41 条 FR 全量产品、完整动作目录/回退/快照平台
- 把 Codex / CC Switch 做成终端用户依赖
- 后门、凭据窃取、攻击扫描、自媒体自动化

## Open questions

- 现场 DeepSeek / AI Ping key 用主办方还是自带
- 演示机烘焙后 `dsh --profile dsh-tui` 能否在 10 分钟内起来（不要用 TUI 的 `/update`）

有网加分路径可以接 AI Ping，但不把「没网就不能诊断」写进产品承诺。
