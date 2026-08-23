# Issue #29 Bake USB Maintenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the USB baking script parse in Windows PowerShell 5.1, copy the canonical launcher byte-for-byte, apply the FAT32 symlink patch to LF deploy output, and validate the baked CLI without pipeline-induced false failures.

**Architecture:** Change only the baking script. Preserve the project source launcher by copying it directly to the destination instead of maintaining an inline duplicate. Normalize the deploy JavaScript and patch templates to LF before matching, write the patched JavaScript consistently, and capture CLI help before trimming output so the CLI process exit code is authoritative.

**Tech Stack:** Windows PowerShell 5.1, PowerShell 7, CMD/GBK launcher bytes, Node CLI, pnpm deploy, FAT32-compatible runtime preparation.

## Global Constraints

- Change only `scripts/bake-usb.ps1`; do not bake `F:\Only-U` or modify runtime artifacts, `portable/start.cmd`, `dsh/`, or `dsh-tui/`.
- Store `scripts/bake-usb.ps1` as UTF-8 with BOM (`EF BB BF`).
- The baked `portable/start.cmd` must be byte-for-byte identical to the repository `portable/start.cmd`.
- Preserve deploy, profile-copy, FAT32 patch, and portable Node semantics in ADR-0005.
- Work on branch `fix/29-bake-usb-maintenance`; push and open a PR, but do not merge it. The team lead must approve it.

---

### Task 1: Make launcher copying and FAT32 patching encoding-safe

**Files:**
- Modify: `scripts/bake-usb.ps1`
- Test: manual parse and temporary-destination dry-run evidence only; no new test file is permitted by Issue #29 scope.

**Interfaces:**
- Consumes: `$Repo\portable\start.cmd`, deployed `$bootJs`, `$Dest`.
- Produces: byte-identical `$Dest\portable\start.cmd` and an LF-normalized patched `$bootJs` where the old symlink guard is present.

- [ ] **Step 1: Establish failing evidence**

Record the original bake script BOM state, show that the source launcher differs from the inline here-string output, and identify CRLF/LF mismatch in the symlink patch input.

```powershell
$bytes = [IO.File]::ReadAllBytes('scripts\bake-usb.ps1')
Format-Hex -Path scripts\bake-usb.ps1 -Count 3
```

- [ ] **Step 2: Replace the stale inline launcher template**

Remove only the `$start` here-string and its `WriteAllText` call. Keep `$gbk` for the root launcher wrappers. Assert the source exists, then copy the source launcher without decoding or re-encoding it.

```powershell
$startSrc = Join-Path $Repo 'portable\start.cmd'
$startDst = Join-Path $Dest 'portable\start.cmd'
Assert-Path $startSrc '找不到 portable\start.cmd'
Copy-Item -LiteralPath $startSrc -Destination $startDst -Force
```

- [ ] **Step 3: Normalize LF before applying the deploy-only patch**

Convert CRLF in the loaded JavaScript and both patch templates to LF before `Contains`/`Replace`, then write the patched deploy artifact with UTF-8 without BOM. Preserve all FAT32 behavior and keep the warning when the upstream target really is absent.

```powershell
$normalizeLf = { param([string]$text) $text -replace "`r`n", "`n" }
$js = & $normalizeLf ([IO.File]::ReadAllText($bootJs))
$old = & $normalizeLf $old
$new = & $normalizeLf $new
if ($js.Contains($old)) {
  [IO.File]::WriteAllText($bootJs, $js.Replace($old, $new), (New-Object Text.UTF8Encoding($false)))
}
```

- [ ] **Step 4: Capture CLI help before selecting display lines**

Do not pipeline a live Node process into `Select-Object -First`. Collect the entire output and exact exit code first, then display at most eight lines.

```powershell
$helpOutput = & $nodeOut $binOut --help 2>&1
$helpExit = $LASTEXITCODE
$helpOutput | Select-Object -First 8 | ForEach-Object { Write-Host $_ }
if ($helpExit -ne 0) { throw 'baked CLI --help failed' }
```

- [ ] **Step 5: Restore UTF-8 BOM and verify without baking F:\Only-U**

Write the modified script with UTF-8 BOM, run Windows PowerShell parsing/preflight against a temporary destination only, and verify the source/temporary-destination launcher byte equality, patch message, and CLI exit behavior when development prerequisites are available.

```powershell
$bytes = [IO.File]::ReadAllBytes('scripts\bake-usb.ps1')
if ($bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) { throw 'UTF-8 BOM missing' }
```

- [ ] **Step 6: Commit and open, but do not merge**

```powershell
git add scripts/bake-usb.ps1
git commit -m "fix: maintain USB bake launcher and patch"
git push -u origin fix/29-bake-usb-maintenance
```

Create a PR whose first body line is `Closes #29`, include PS 5.1 parse/preflight evidence, source/target launcher byte comparison, LF patch evidence, and CLI help exit evidence. State explicitly that it waits for team-lead review.
