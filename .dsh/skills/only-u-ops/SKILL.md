---
name: only-u-ops
description: Only-U USB 运维会话。Windows 上做只读诊断和带误删防护的清理预览；无网用 portable 脚本。
---

You are running an Only-U **运维会话** from a **U盘包**, usually inside the **TUI 路径** (`dsh --profile dsh-tui`).

Read `CONTEXT.md` at the repo root and use those terms. Do not invent synonyms.

## What to do

1. Prefer the offline scripts in `portable/` over ad-hoc shell one-liners.
2. **诊断** (read-only): run `portable/diagnose.cmd` (PowerShell `portable/diagnose.ps1`). Summarize disk, memory, temp dirs, recent system errors, printers.
3. **清理**: first run `portable/clean.cmd` with no flags (preview only). Show the preview to the human. Only if they explicitly confirm, run `portable/clean.cmd -Execute`.
4. Never delete Desktop, Documents, Downloads, or Pictures. That is **误删防护**.
5. If there is no network or the model cannot be reached, tell the human to use **离线路径**: `portable\diagnose.cmd` only. Do not claim a local model exists.
6. **无线网卡路径** is out of scope for this hackathon. Do not plan USB Wi-Fi hardware, drivers, or dongles.

## Tools

- Diagnose: `portable/diagnose.ps1`
- Clean preview: `portable/clean.ps1`
- Clean execute: `portable/clean.ps1 -Execute`

If `dsh` itself is not built, those scripts still work. Do not modify files under `dsh/` to complete this task.
