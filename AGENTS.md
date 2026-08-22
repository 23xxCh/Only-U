# Only-U

U盘运维 agent，基于 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh/` 源码快照）+ [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI) 终端壳。

领域用语在根目录 `CONTEXT.md`。比赛计划在 `docs/plan.md`。已批准设计在 `docs/designs/only-u-hackathon.md`。已拍板决策在 `docs/adr/`。文档读序见 `docs/README.md`。Harness 源码在 `dsh/`（见 `dsh/UPSTREAM.md`）。dsh-TUI **npm 插件** 装进 profile `dsh-tui`；`dsh-tui/` 只是 0.8.8 源码快照，给改界面用，不是 U 盘启动路径。改 harness 前读 `dsh/AGENTS.md`；改 TUI 源码前读 `dsh-tui/ADAPTER.md`。

比赛交付是软件 **U盘包**（`portable/`）。无线网卡后续再做。先按 `docs/plan.md` 对齐，再写功能代码。

`docs/Only-U-项目需求文档.md`、`docs/prd.md` 与 `docs/superpowers/specs/` **不是**实现依据。冲突以 ADR-0002（产品范围）和 [ADR-0005](docs/adr/0005-usb-baked-dsh-runtime.md)（U 盘烤法）为准。不要按长 PRD 做在线-only Web，也不要删 `dsh/`。

开发机：

```sh
cd dsh
pnpm install
pnpm run build
pnpm dsh --profile dsh-tui
```

客户机不装 Node/pnpm。烤盘：

```bat
powershell -File scripts\bake-usb.ps1 -Dest F:\Only-U
```

有网 Agent 壳是 **TUI 路径**（ADR-0003）：插件 `@deepseek-harness-tui/dsh-tui` 0.8.8，profile 名 `dsh-tui`。不要用 `github:deepseek-harness/turtle-ui`。升级用 `pnpm dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@版本`，不要用 TUI 里的 `/update`。不要把 `dsh/node_modules` 整包拷上 FAT32。

无网或 TUI 起不来时，跑 `portable\diagnose.cmd`。运维插件在开发机 `plugin add` 后再烤盘。

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `23xxCh/Only-U` (via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical five-role vocabulary; label strings match the role names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
