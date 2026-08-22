---
name: only-u-ops
description: Only-U USB 运维会话。Windows 上做只读诊断和带误删防护的清理预览；无网用 portable 脚本。
---

You are running an Only-U **运维会话** from a **U盘包**, usually inside the **TUI 路径** (`dsh --profile dsh-tui`).

Read `CONTEXT.md` at the repo root and use those terms. Do not invent synonyms.

## What to do

1. Prefer the offline scripts in `portable/` over ad-hoc shell one-liners.
2. 在 TUI **运维会话一开始**，先运行 `portable/diagnose.cmd`，再运行 `portable/clean.cmd`（无参数，仅预览）；把两段输出都展示给人。
3. **诊断**只读：总结磁盘、内存与占内存进程、启动项线索、临时目录、近期 System 错误、打印机和驱动状态异常；不要结束进程、安装驱动或修改系统。
4. **清理**默认只预览。只有用户明确说“确认”“执行”或同等明确确认后，才运行 `portable/clean.cmd -Execute`。未确认时绝不执行，不推荐第三方一键清理或注册表清理。
5. Never delete Desktop, Documents, Downloads, or Pictures. That is **误删防护**.
6. If there is no network or the model cannot be reached, tell the human to use **离线路径**: `portable\diagnose.cmd` only. Do not claim a local model exists.
7. **无线网卡路径** is out of scope for this hackathon. Do not plan USB Wi-Fi hardware, drivers, or dongles.

## Tools

- Diagnose: `portable/diagnose.ps1`
- Clean preview: `portable/clean.ps1`
- Clean execute: `portable/clean.ps1 -Execute`

If the TUI cannot start, those scripts still work. Do not modify files under `dsh-tui/` to complete this task.
