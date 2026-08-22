# dsh-TUI snapshot

- Upstream: https://github.com/ccch1mneyyy/dsh-TUI
- npm: `@deepseek-harness-tui/dsh-tui`
- Version: 0.8.8
- Imported: 2026-08-22
- Layout: source snapshot without upstream `.git`; `vendor/dsh-std` included

Only-U develops on top of dsh-TUI as the online agent shell ([ADR-0004](../docs/adr/0004-dev-base-dsh-tui.md)). The harness kernel itself is **not** vendored: runtime comes from npm `@deepseek-ai/dsh` and the `dsh-tui` profile installed via:

```bat
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
```

Customizing the TUI: read `ADAPTER.md` first — upstream `@deepseek-ai/*` imports stay inside `src/dsh-adapter/`; keep changes upstreamable.

To refresh this snapshot later, re-import the same way and update this file.
