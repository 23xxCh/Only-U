# 黑客松以队长当前方案为开发基线

队友 yandifei 于 2026-08-22 把长 PRD 和设计规格推进 `main`（`docs/Only-U-项目需求文档.md`、`docs/superpowers/specs/2026-08-22-only-u-design.md`）。其中若干条款与已经批准的比赛方案冲突。队长决定：**本场实现、演示、开票以现有方案为准**，长 PRD 降为需求证据，不覆盖 `docs/plan.md`。

**Status:** accepted

## Canonical docs

1. `CONTEXT.md`
2. `docs/plan.md`
3. `docs/designs/only-u-hackathon.md`（office-hours Approach B）
4. `docs/adr/0001-software-only-usb-pack.md`、本 ADR、以及后续的 `docs/adr/0003-dsh-tui-agent-shell.md`（有网壳）
5. 已有 `portable/` 脚本与 `.dsh/skills/only-u-ops`

## 冲突条款：不采用

| 长 PRD / 设计规格 | 本场方案 |
|---|---|
| V1 必须联网；无网只提示、禁止离线诊断 | **离线路径**必须能跑 `portable\diagnose.cmd` |
| 本地 Web 界面是主入口 | CLI / 脚本是地板；有网用 **TUI 路径**（ADR-0003），Web 不是本场必做 |
| 场景 D 用来证明「不会跑离线脚本」 | 无网出诊断报告，才是 whoa |
| P0 含完整性签名、动作目录、回退平台、41 条 FR | 本场只做诊断 + 带误删防护的清理 + 有网时 Agent 调同一脚本 |
| 团队 Key 静态写入交付 U 盘作为产品形态 | 运行时读 `portable/.env`；真实 Key 永不进 Git。介质怎么带 key 是制作步骤，不是本场范围膨胀理由 |

## 仍然采纳（两边一致）

- Windows 10/11 优先；macOS / Linux 本场不做
- 软件 **U盘包**；无线网卡赛后再做
- DSH **插件** / skill，不改 harness 内核
- 合法合规；不做后门、BadUSB、凭据窃取、攻击扫描
- **清理**必须先预览再确认
- 真实 Key、微信导出不进仓库

## Considered options

- 以长 PRD 为开发基线，把 `portable/` 改成在线-only Web 产品（否决：一天半交不出，且否定已批准的 whoa）
- 两套文档并行、实现时再选（否决：合作者的 agent 会按「已批准」PRD 扩范围）
- 以队长当前方案为基线，长 PRD 当痛点归档（采纳）
