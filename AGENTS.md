# Only-U

U盘运维 agent，基于 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）开发。

Harness 源码在 `dsh/`，快照信息见 `dsh/UPSTREAM.md`。改 harness 或写 DSH 插件前先读 `dsh/AGENTS.md`。在 `dsh/` 里开发时用该目录下的 pnpm 工作区：

```sh
cd dsh
pnpm install
pnpm run build
pnpm dsh web
```

U盘相关能力做成 DSH 插件，不要直接改 harness 内核。

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `23xxCh/Only-U` (via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical five-role vocabulary; label strings match the role names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
