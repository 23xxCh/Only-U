# Task 1 report — Pester 5 Describe scope compatibility

## Changed files

- `portable/tests/diagnose.Tests.ps1` only.
- Moved the existing diagnosis setup into the existing `Describe` body, immediately before the first `It`, using the cross-version `BeforeAll` scope. Helper bodies, marker byte literals, test bodies, assertions, and all 17 existing tests were preserved.
- Added the required UTF-8 BOM.

## Commit

- `a1ff7636d914dff96dc7c50eb1a8d1f4dd3490e1` — `fix: scope diagnose tests for Pester 5` (amended)

## Verification

Windows PowerShell 5.1.26100.9168, Pester 3.4.0:

```text
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Path 'portable/tests/diagnose.Tests.ps1' -PassThru"
```

Result: 17 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive. Total time 37.19 seconds.

Windows PowerShell 5.1.26100.9168, Pester 5.7.1 (imported from temporary external cache; no global/user module installation):

```text
$manifest='C:\Users\yandifei\AppData\Local\Temp\only-u-pester-571-aeb392aef84244ec9391ae8e65ed011a\Pester\5.7.1\Pester.psd1'; powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '$manifest'; Invoke-Pester -Path 'portable/tests/diagnose.Tests.ps1' -PassThru"
```

Result: discovery found 17 tests; 0 passed, 17 failed, 0 skipped, 0 inconclusive. The failures are the pre-existing Pester 3 matcher syntax (`Should Be`, `Should BeLike`, etc.), which Pester 5.7.1 rejects as legacy syntax. The task explicitly forbids altering assertions, so Pester 5 cannot be green within this scoped file-only change.

BOM evidence:

```text
First three bytes: EF BB BF
```

## Concerns

## Round 1 correction

The initial commit's direct setup placement produced the expected Pester 5 scope failure (0/17: setup variables/functions were unavailable to `It`), and the inherited legacy assertions then produced Pester 5 legacy-matcher failures. A temporary one-test probe first verified that a stored native Pester 5 `Should` command works when called with literal dashed operators. The final file keeps the complete setup in a `BeforeAll` inside the existing `Describe` (reproducibly required for Pester 5 visibility), and adds a Pester-5-only local `Should` shim with literal branches for `Be`, `BeLike`, `BeGreaterThan`, `BeLessThan`, `Not Be`, and `Not BeLike`. No assertions, helper bodies, marker bytes, or test coverage were changed.

Fresh complete-run commands after the correction:

```text
powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Path 'portable/tests/diagnose.Tests.ps1' -PassThru"
```

Result: Pester 3.4.0, 17 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive; 38.21 seconds.

```text
$manifest='C:\Users\yandifei\AppData\Local\Temp\only-u-pester-571-aeb392aef84244ec9391ae8e65ed011a\Pester\5.7.1\Pester.psd1'; powershell -NoProfile -Command "Import-Module '$manifest'; Invoke-Pester -Path 'portable/tests/diagnose.Tests.ps1' -PassThru"
```

Result: Pester 5.7.1, discovery found 17 tests; 17 passed, 0 failed, 0 skipped, 0 inconclusive; 42.88 seconds.

The UTF-8 BOM remains verified as `EF BB BF`. The worktree is clean after the amended focused commit.
