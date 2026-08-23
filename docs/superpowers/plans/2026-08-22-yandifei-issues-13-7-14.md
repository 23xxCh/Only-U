# Yandifei Issues 13, 7, and 14 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the Pester 3.4 test-environment failure, upgrade read-only driver/printer diagnostics, and prevent duplicate TUI launches.

**Architecture:** #13 removes host-encoding-dependent Chinese assertions from the existing diagnosis tests so Windows PowerShell 5.1 with Pester 3.4 produces a true test result. #7 keeps all diagnosis in `portable/diagnose.ps1` and translates structured PnP/printer state into human-readable evidence. #14 puts a process-level single-instance guard in the portable launcher rather than in DSH runtime code.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4+/5, CMD batch, Windows CIM and device/printer cmdlets.

## Global Constraints

- Follow `CONTEXT.md`: U盘包、运维会话、诊断、清理、误删防护。
- Windows only; all new diagnostics are read-only and must not enable/disable devices, install drivers, or invoke `pnputil` writes.
- Keep `portable/diagnose.ps1` UTF-8 BOM and its existing 8-second / 20,000-file directory-scan cap.
- Never modify `dsh/` or `dsh-tui/`; do not put keys, runtime artifacts, or user data in Git.
- Each ticket uses its own branch and PR; #14 is based on merged #13.

---

### Task 1: Issue #13 — Pester environment compatibility

**Files:**
- Modify: `portable/tests/diagnose.Tests.ps1`
- Test: `portable/tests/diagnose.Tests.ps1`

**Interfaces:**
- Consumes: UTF-8 output from `portable/diagnose.ps1` and the UTF-8 Only-U skill.
- Produces: Pester 3.4-compatible assertions that do not report false failures from Chinese text decoding.

- [ ] **Step 1: Write failing regression tests**

Add assertions that invoke the test suite through `powershell.exe` with Pester 3.4 and require a zero-failure result while retaining diagnostic-output coverage through ASCII anchors.

- [ ] **Step 2: Run the regression test to verify failure**

Run: `powershell.exe -NoProfile -Command "Import-Module Pester -Force; Invoke-Pester portable\\tests\\diagnose.Tests.ps1"`

Expected: the current three Chinese `BeLike` assertions fail with mojibake.

- [ ] **Step 3: Implement the minimal compatibility fix**

Replace encoding-sensitive Chinese `BeLike` test assertions with stable ASCII output anchors or explicit UTF-8 decoding, without weakening coverage of script execution, scan caps, diagnostic sections, or the TUI instruction sequence.

- [ ] **Step 4: Verify both hosts**

Run the suite through Windows PowerShell 5.1 and the default PowerShell host. Both must report zero failures or explicit skips with a reason.

- [ ] **Step 5: Commit and open PR**

Commit only the test-environment fix on `fix/pester-env`; PR first line: `Closes #13`.

### Task 2: Issue #7 — Driver and printer diagnosis

**Files:**
- Modify: `portable/diagnose.ps1`
- Modify: `portable/tests/diagnose.Tests.ps1`

**Interfaces:**
- Consumes: `Win32_PnPEntity.ConfigManagerErrorCode`, `Get-PnpDeviceProperty`, `Get-Printer`, `Get-Service Spooler`, and `Win32_Printer`.
- Produces: capped Chinese PnP problem buckets, practical next-step text, and a printer conclusion that distinguishes driver, service, and connection/consumable evidence.

- [ ] **Step 1: Write failing behavior tests**

Add controlled Pester fixtures for code-to-text mapping and report output. Include assertions that no device-enable, device-disable, driver-install, or `pnputil` write command occurs.

- [ ] **Step 2: Run the tests to verify failure**

Run: `Invoke-Pester portable\\tests\\diagnose.Tests.ps1`

Expected: the translation/bucket assertions fail because the current report only prints raw error codes.

- [ ] **Step 3: Implement the minimal diagnosis additions**

Add the specified problem-code mapping and three buckets, limit each bucket to five entries, include HardwareID summaries for missing-driver entries when readable, and add Spooler/Win32_Printer/port evidence without modifying devices or printers.

- [ ] **Step 4: Verify diagnosis behavior**

Run the Pester suite and `portable\\diagnose.cmd`; confirm normal machines retain the no-PnP-problem message and the report completes within 60 seconds.

- [ ] **Step 5: Commit and open PR**

Commit only #7 files on `feat/7-driver-code-translate`; PR first line: `Closes #7`.

### Task 3: Issue #14 — TUI single-instance guard

**Files:**
- Modify: `portable/start.cmd`
- Modify: `tests/portable-start.tests.ps1`

**Interfaces:**
- Consumes: `node.exe` processes and their command lines.
- Produces: a non-zero launcher exit with a Chinese explanation when another DSH TUI process is already running; normal launch remains unchanged.

- [ ] **Step 1: Write a failing launcher test**

Create a short-lived fake `node.exe` process whose command line contains `dsh\\lib\\bin.js`, start `portable\\start.cmd`, and assert non-zero exit plus the duplicate-TUI message. Keep the existing no-process happy-path test.

- [ ] **Step 2: Run the test to verify failure**

Run: `Invoke-Pester tests\\portable-start.tests.ps1`

Expected: the current launcher starts another process because it has no single-instance guard.

- [ ] **Step 3: Implement the launcher guard**

Before the `:start` command, query `node.exe` command lines for the DSH CLI path. If found, print the recovery guidance, pause, and return exit code 1. Do not create PID files and do not touch `lib\\bin.js`.

- [ ] **Step 4: Verify both launch paths**

Run the focused tests. Confirm an existing matching process blocks launch and no matching process retains the existing launch behavior.

- [ ] **Step 5: Commit and open PR**

Rebase on merged #13, commit only #14 files on `fix/14-tui-single-instance`, and open a PR with first line `Closes #14`.

## Coverage Review

- #13 maps its cross-version acceptance condition to Task 1.
- #7 maps its PnP translations, buckets, printer evidence, HardwareID rule, and read-only boundary to Task 2.
- #14 maps its duplicate-process guard, recovery path, and happy path to Task 3.
- No task changes harness runtime, cleanup protections, credentials, or the user-owned assessment documents.
