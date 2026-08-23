### Task 1: Issue #13 — Pester environment compatibility

**Files:**
- Modify: `portable/tests/diagnose.Tests.ps1`
- Test: `portable/tests/diagnose.Tests.ps1`

**Interfaces:**
- Consumes: UTF-8 output from `portable/diagnose.ps1` and the UTF-8 Only-U skill.
- Produces: Pester 3.4-compatible assertions that do not report false failures from Chinese text decoding.

#### Requirements

1. Add or retain regression coverage that invokes the test suite through Windows PowerShell 5.1 with Pester 3.4 and requires zero failures while retaining diagnostic-output coverage through ASCII anchors.
2. The existing three Chinese `BeLike` assertions currently fail as mojibake. Replace encoding-sensitive Chinese `BeLike` test assertions with stable ASCII output anchors or explicit UTF-8 decoding.
3. Do not weaken coverage of script execution, scan caps, diagnostic sections, or the TUI instruction sequence.
4. Verify the suite through Windows PowerShell 5.1 and the default PowerShell host. Both must report zero failures or explicit skips with a reason.
5. Make the smallest change. Do not modify production diagnostics, scripts, skill files, launcher files, `dsh/`, `dsh-tui/`, or any docs.
6. Commit only the test-environment fix on branch `fix/pester-env`. The controller will open the PR, whose first line must be `Closes #13`.
