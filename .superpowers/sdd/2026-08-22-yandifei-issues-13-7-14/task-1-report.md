# Task 1 report — Issue #13

## Changed files

- `portable/tests/diagnose.Tests.ps1`
  - Added a test-local process runner that explicitly decodes redirected stdout and stderr as UTF-8 for Windows PowerShell 5.1/Pester 3.4.
  - Replaced encoding-sensitive Chinese output assertions with stable ASCII anchors and section-structure checks.
  - Replaced remaining Chinese fallback/skill assertions with ASCII anchors while retaining scan-cap, diagnostic-section, and TUI sequence coverage.

No production, launcher, skill, documentation, `dsh/`, `dsh-tui/`, or other files were changed.

## Test commands and results

- Windows PowerShell 5.1 + Pester 3.4:
  - `powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script 'portable/tests/diagnose.Tests.ps1'"`
  - Passed: 7; Failed: 0; Skipped: 0.
- Default PowerShell host (PowerShell 7.6.4) + Pester 3.4:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script 'portable/tests/diagnose.Tests.ps1'"`
  - Passed: 7; Failed: 0; Skipped: 0.

The unchanged Windows PowerShell baseline reproduced the issue with two mojibake Chinese-output failures; the updated suite passes on both hosts.

## Commit

`904c802d19754d163d37c4a7f77dda2a775aa7c4`

## Concerns

The initial implementation used an ASCII section-header count for critical events; that concern was addressed in review round 1 by explicit UTF-8 decoding and a direct critical-event marker assertion.

## Review round 1 fixes

Commit: `3e16c628de10440785986802d6b29deb7bd3aa9c`

- Added explicit UTF-8 byte-decoded markers for scan start, skipped-cap explanation, critical events, startup fallback, and TUI confirmation/execution ordering.
- Read the UTF-8 skill file explicitly and restored the confirmation-before-`-Execute` ordering assertion.
- Changed child process capture to concurrent `ReadToEndAsync()` calls to avoid stdout/stderr pipe deadlocks.
- Made the helper return `Output`, `Error`, and `ExitCode`; all four diagnose execution tests assert exit code zero.
- Restored startup-entry coverage for either the normal ASCII result or the UTF-8-decoded fallback message.

Verification after review fixes:

- Windows PowerShell 5.1 + Pester 3.4: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script 'portable/tests/diagnose.Tests.ps1'"` — Passed: 7; Failed: 0; Skipped: 0.
- Default PowerShell host (PowerShell 7.6.4) + Pester 3.4: `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script 'portable/tests/diagnose.Tests.ps1'"` — Passed: 7; Failed: 0; Skipped: 0.

Review concerns: none remaining after the two-host verification; only `portable/tests/diagnose.Tests.ps1` changed in the review fix commit.
