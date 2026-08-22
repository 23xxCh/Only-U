# Only-U

U盘运维 agent，有网 Agent 壳基于 [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI)（DeepSeek Harness 的终端壳插件）开发。

领域用语在根目录 `CONTEXT.md`。比赛计划在 `docs/plan.md`。需求基线在 `docs/prd.md`。已批准设计在 `docs/designs/only-u-hackathon.md`。已拍板决策在 `docs/adr/`。文档读序见 `docs/README.md`。dsh-TUI 源码快照在 `dsh-tui/`（见 `dsh-tui/UPSTREAM.md` 与 [ADR-0004](docs/adr/0004-dev-base-dsh-tui.md)）；harness 内核不 vendor，运行时来自 npm `@deepseek-ai/dsh`。改 `dsh-tui/` 前先读 `dsh-tui/ADAPTER.md`。

比赛交付是软件 **U盘包**（`portable/`）。无线网卡后续再做，不要在当前切片里加硬件。先按 `docs/plan.md` 对齐，再写功能代码。

`docs/Only-U-项目需求文档.md` 与 `docs/superpowers/specs/` 是需求归档，**不是**本场开发基线。冲突以 ADR-0002 为准：无网必须能跑 `portable\diagnose.cmd`；不要按长 PRD 做在线-only Web 产品或 41 条 FR。

```sh
npm install -g @deepseek-ai/dsh
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
dsh --profile dsh-tui
```

有网 Agent 壳是 **TUI 路径**（[ADR-0003](docs/adr/0003-dsh-tui-agent-shell.md)、[ADR-0004](docs/adr/0004-dev-base-dsh-tui.md)）：插件 `@deepseek-harness-tui/dsh-tui`，profile 名 `dsh-tui`。官方 dsh 最新版没有 TUI 界面，TUI 由 dsh-TUI 提供（源码快照在 `dsh-tui/`）。不要用 `github:deepseek-harness/turtle-ui`。升级用 `dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@版本`，不要用 TUI 里的 `/update`。

无网或 TUI 起不来时，直接跑 `portable\diagnose.cmd`。U盘能力用 skill / 插件，不要改 harness 内核。

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `23xxCh/Only-U` (via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical five-role vocabulary; label strings match the role names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
