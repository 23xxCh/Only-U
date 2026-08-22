# Only-U

U盘运维 agent，基于 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）开发。

领域用语在根目录 `CONTEXT.md`。比赛计划在 `docs/plan.md`。已批准设计在 `docs/designs/only-u-hackathon.md`。已拍板决策在 `docs/adr/`。文档读序见 `docs/README.md`。Harness 源码在 `dsh/`，快照见 `dsh/UPSTREAM.md`。改 harness 或写 DSH 插件前先读 `dsh/AGENTS.md`。

比赛交付是软件 **U盘包**（`portable/`）。无线网卡后续再做，不要在当前切片里加硬件。先按 `docs/plan.md` 对齐，再写功能代码。

`docs/Only-U-项目需求文档.md` 与 `docs/superpowers/specs/` 是需求归档，**不是**本场开发基线。冲突以 ADR-0002 为准：无网必须能跑 `portable\diagnose.cmd`；不要按长 PRD 做在线-only Web 产品或 41 条 FR。

```sh
cd dsh
pnpm install
pnpm run build
pnpm dsh --profile dsh-tui
```

有网 Agent 壳是 **TUI 路径**（[ADR-0003](docs/adr/0003-dsh-tui-agent-shell.md)）：插件 `@deepseek-harness-tui/dsh-tui`，profile 名 `dsh-tui`。不要 fork `dsh/`，不要把 dsh-TUI 源码 vendor 进仓库，不要用 `github:deepseek-harness/turtle-ui`。升级用 `pnpm dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@版本`，不要用 TUI 里的 `/update`。

无网或 DSH 未构建时，直接跑 `portable\diagnose.cmd`。U盘能力用 skill / 插件，不要改 harness 内核。

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `23xxCh/Only-U` (via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical five-role vocabulary; label strings match the role names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
