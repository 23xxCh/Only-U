# Issue #28 Pester Describe Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the diagnosis Pester tests run in both Windows PowerShell 5.1/Pester 3.4.0 and Pester 5.7.1 without scope-discovery failures.

**Architecture:** Pester 5 discovers a test file in a different scope from its execution. Move every test helper and marker variable currently defined at file scope into the body of the existing `Describe 'Only-U offline diagnose'` block, before its first `It`. The `Describe` body is evaluated during run in both Pester versions, so helper names and values remain available to every `It` while no product behavior changes.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4.0 and 5.7.1, UTF-8 BOM PowerShell source.

## Global Constraints

- Change only `portable/tests/diagnose.Tests.ps1`.
- Preserve the UTF-8 BOM (`EF BB BF`), every existing test assertion, all byte-decoded Chinese markers, and the existing test count.
- Do not add `#Requires` or lock the suite to either Pester major version.
- Work on branch `fix/28-pester5-describe-scope`; push and open a PR, but do not merge it. The team lead must approve it.

---

### Task 1: Move test-run helpers into the executable Describe scope

**Files:**
- Modify: `portable/tests/diagnose.Tests.ps1`
- Test: `portable/tests/diagnose.Tests.ps1`

**Interfaces:**
- Consumes: `portable/diagnose.ps1`, `.dsh/skills/only-u-ops/SKILL.md`, Windows PowerShell executable.
- Produces: within the `Describe` body, `$repoRoot`, `$diagnoseScript`, `$skillFile`, `$windowsPowerShell`, `Get-Utf8Text`, every marker variable, and `Invoke-DiagnoseOutput` for all following `It` blocks.

- [ ] **Step 1: Write the failing regression test**

Run the untouched test file with Pester 5.7.1 in Windows PowerShell 5.1. It must fail because an `It` cannot see a top-level helper or marker, rather than because `diagnose.ps1` fails.

```powershell
powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester portable\tests\diagnose.Tests.ps1"
```

- [ ] **Step 2: Verify the Pester 3.4 baseline**

Run the existing Windows PowerShell/Pester 3.4 suite and record its passing count before editing.

```powershell
powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script portable\tests\diagnose.Tests.ps1"
```

- [ ] **Step 3: Make the minimum scope-only change**

Move the contiguous pre-`Describe` setup block into the `Describe` immediately after its opening line and before the first `It`; do not rename it or change its marker bytes, helper implementation, or assertions.

```powershell
Describe 'Only-U offline diagnose' {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    # existing helper and marker declarations, unchanged
    function Invoke-DiagnoseOutput { # existing body, unchanged }

    It 'translates recognized PnP driver and device states into actionable buckets' {
        # existing body, unchanged
    }
}
```

- [ ] **Step 4: Verify both Pester majors and encoding**

Run the entire suite once with Pester 3.4.0 and once with Pester 5.7.1 in Windows PowerShell 5.1. Confirm the expected count is the same in both runs and inspect the first three bytes.

```powershell
$bytes = [IO.File]::ReadAllBytes('portable\tests\diagnose.Tests.ps1')
if ($bytes[0..2] -notcontains 0xEF) { throw 'UTF-8 BOM missing' }
```

- [ ] **Step 5: Commit and open, but do not merge**

```powershell
git add portable/tests/diagnose.Tests.ps1
git commit -m "fix: scope diagnose tests for Pester 5"
git push -u origin fix/28-pester5-describe-scope
```

Create a PR whose first body line is `Closes #28`, include both measured Pester runs, and explicitly state that it awaits team-lead review.

