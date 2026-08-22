# Only-U 文档

比赛开发以队长当前方案为准，不要按后写的长 PRD 扩范围。

## 读这个顺序

1. 根目录 [`CONTEXT.md`](../CONTEXT.md) — 领域用词
2. [`plan.md`](plan.md) — 黑客松交付与演示
3. [`designs/only-u-hackathon.md`](designs/only-u-hackathon.md) — 已批准的产品设计（Approach B）
4. [`adr/`](adr/) — 已拍板决策
   - [0003](adr/0003-dsh-tui-agent-shell.md) 有网壳是 dsh-TUI 插件
   - [0005](adr/0005-usb-baked-dsh-runtime.md) **U 盘密封运行时（已采纳）**
   - [0004](adr/0004-dev-base-dsh-tui.md) 是把 TUI 源码快照入库的提案，**不覆盖 0005**
5. [`agents/`](agents/) — Issue / 标签 / 给合作者 agent 的入口

## 不是本场开发基线

下面由队友写入，**只作需求证据或路线笔记**。实现以 `plan.md` + ADR-0002 + ADR-0005 为准。

- [`Only-U-项目需求文档.md`](Only-U-项目需求文档.md)
- [`prd.md`](prd.md)
- [`superpowers/specs/2026-08-22-only-u-design.md`](superpowers/specs/2026-08-22-only-u-design.md)
- [`requirements-source/突击深圳黑客松_聊天记录.md`](requirements-source/突击深圳黑客松_聊天记录.md)

实现前读 `plan.md` 和 ADR，不要直接按 PRD 开票。不要删除 `dsh/`。
