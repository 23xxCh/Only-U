# Task 2 report — Issue #7

## Scope

Implemented on branch `feat/7-driver-code-translate` in isolated worktree
`C:\Users\yandifei\Desktop\黑客松-issue7`.

Changed files:

- `portable/diagnose.ps1`
- `portable/tests/diagnose.Tests.ps1`

The pre-existing, unmerged Issue #13 Pester compatibility changes were not
amended or committed by this task. No other tracked file was changed in the
Issue #7 commit.

## Delivered behavior

- Adds Spooler state evidence, printer detected-error evidence, port hints,
  and per-printer conclusions without changing services, printers, devices, or
  drivers.
- Translates the required PnP ConfigManager error codes; groups findings into
  counted buckets and displays no more than five entries per bucket.
- Reads and redacts only the first hardware ID for missing-driver findings,
  when the read-only PnP property is available.
- Keeps the normal-machine PnP message exactly `未发现驱动状态异常的即插即用设备`.
- Adds deterministic Pester coverage for all required translations, the
  translated output-line contract, and PCI/USB hardware-ID redaction. Tests
  dot-source the script with `-NoRun`, so these cases do not depend on local
  printer or PnP state.

## Test-first record

1. Added the controlled mapping/output/hardware-ID tests before the new
   helpers existed.
2. Ran the full suite and observed the three new tests fail with
   `CommandNotFoundException` for `Get-PnpErrorDetail` and
   `Get-HardwareIdSummary`; existing tests continued to pass.
3. Implemented the minimal read-only helpers and reporting changes.
4. A Windows PowerShell compatibility run exposed an incorrectly encoded test
   expectation for code 48. Corrected the test fixture to the literal
   required translation `被策略阻止`, then reran both complete suites.

## Verification

| Command | Result | Elapsed |
| --- | --- | --- |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\portable\tests\diagnose.Tests.ps1 -PassThru"` | Pester 3.4 / Windows PowerShell 5.1: 10 passed, 0 failed | 29.60 s |
| `pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Script .\portable\tests\diagnose.Tests.ps1 -PassThru"` | Pester 3.4 / default PowerShell: 10 passed, 0 failed | 29.01 s |
| `cmd /c portable\diagnose.cmd` | exit 0; normal run completed and retained the exact healthy PnP message | 5.32 s |
| `git diff --check` | clean | < 1 s |
| UTF-8 BOM byte check on `portable/diagnose.ps1` | passed | < 1 s |
| read-only command scan for service/device/printer mutators and `pnputil` | passed | < 1 s |

The normal `diagnose.cmd` run and the full tests are both within the required
60-second limit. The existing directory scan cap remains 8 seconds and 20,000
files.

## Commit

- `82d9f5a3fd34f80ef6c6610691e473ebc335bf9f` — `feat(diagnose): translate driver and printer faults`

## Self-review

- Confirmed only the two requested Issue #7 files were included in the commit.
- Confirmed all new operations are evidence gathering only; no mutating PnP,
  driver, service, or printer command is present.
- Confirmed the hardware-ID output is restricted to `VEN_xxxx&DEV_xxxx` or
  `VID_xxxx&PID_xxxx` and is skipped silently when unreadable.
- Confirmed PnP bucket counts use all matching entries while output selects at
  most five entries per bucket.

## Concerns

None. Printer/PnP hardware-state branches are intentionally covered with
controlled helper fixtures rather than changing or relying on local device
state; the complete normal-machine run verifies integration and resilience.

## Review-fix round 1

### Changes

- Added `Invoke-BoundedRead`, which executes a read-only script block in a
  cancellable job and returns `TimedOut` or `Unreadable` rather than waiting
  indefinitely. It bounds the new Spooler, `Win32_Printer`, `Get-Printer`, and
  `Win32_PnPEntity` reads to 4, 4, 4, and 6 seconds respectively. Each
  missing-driver hardware-ID property read is separately bounded to 2 seconds;
  the existing five-entry bucket cap bounds those reads to at most ten seconds.
- Added controlled PnP bucket display and line helpers so counts retain all
  matching facts while entries remain capped at five, and so hardware-ID reads
  occur only for the missing-driver bucket.
- Made printer port classification consume `PrinterStatus`, and added a
  conclusion classifier. A WSD printer in `Offline` state (including serialized
  status value `7`) now returns connection evidence ahead of the
  driver-installed conclusion; a stopped Spooler remains the higher-priority
  software conclusion.

### Added deterministic coverage

- forced completion of a timed-out read;
- bucket count and five-entry cap;
- hardware versus disabled remediation;
- first-entry-only PCI/USB ID redaction, missing-driver-only property access,
  and unreadable-property resilience;
- Spooler stopped conclusion, printer error mappings, WSD/TCP-IP/USB port
  classification, and offline conclusion priority (including status `7`).

### Review-fix verification

| Command | Result | Elapsed |
| --- | --- | --- |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\portable\tests\diagnose.Tests.ps1 -PassThru"` | Pester 3.4 / Windows PowerShell 5.1: 16 passed, 0 failed | 32.82 s |
| controlled `Invoke-BoundedRead` test (`Start-Sleep 4`, timeout 1) | returned `TimedOut`; forced completion verified | 1.17 s |
| `cmd /c portable\diagnose.cmd` | exit 0 | 6.78 s |
| `git diff --check`; UTF-8 BOM byte check; read-only mutator scan | all passed | < 1 s |

### Review-fix commit

- `9e0f2995c208ca41fdafcd38c7b94b7273d55e3a` — `fix(diagnose): bound device evidence reads`

### Review-fix concerns

None. The new evidence reads are individually bounded and cancellable; the
normal run remains far below the 60-second contract.

## Review-fix round 2 — aggregate budget

### Changes

- Added a 50-second shared monotonic budget at script start using
  `System.Diagnostics.Stopwatch`, leaving ten seconds of headroom below the
  60-second diagnosis contract.
- Both calls to `Wait-Job` in the existing TEMP directory scan and every new
  `Invoke-BoundedRead` obtain their effective timeout from that same remaining
  budget. Each checks the remaining time before starting and again before
  waiting; if no full second remains, it stops/skips rather than starting or
  extending another read.
- Preserved each job's existing `Stop-Job`/`Remove-Job` cleanup and resilient
  result paths (`Skipped` for directory scans and `TimedOut`/unreadable output
  for device evidence).

### Test-first record

The new controlled Pester test set a one-second shared budget and requested
two five-second reads whose bodies each sleep four seconds. Before this fix it
failed after 8.48 seconds (`Complete` rather than `TimedOut`), proving that
the operations used independent timeouts. With the shared monotonic budget it
passes in 54 ms on Windows PowerShell and 13 ms on default PowerShell; the
second read is not allowed to extend the aggregate deadline.

### Verification

| Command | Result | Elapsed |
| --- | --- | --- |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\portable\tests\diagnose.Tests.ps1 -PassThru"` | Pester 3.4 / Windows PowerShell 5.1: 17 passed, 0 failed | 33.11 s |
| `pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Script .\portable\tests\diagnose.Tests.ps1 -PassThru"` | Pester 3.4 / default PowerShell: 17 passed, 0 failed | 33.09 s |
| `cmd /c portable\diagnose.cmd` | exit 0 | 6.81 s |
| `git diff --check`; UTF-8 BOM byte check; read-only mutator scan | all passed | < 1 s |

### Commit

- `d18e2d7615b1eceeed6771d04e27e4ef32f6609e` — `fix(diagnose): share the read time budget`

### Concerns

None. The shared budget is intentionally limited to the existing TEMP waits
and the new printer/PnP/property reads requested in review; unrelated
diagnostic behavior remains unchanged.

## Review-fix round 3 — aggregate-test strengthening

### Test-only change

Replaced the shared-budget regression's one-second budget, which could expire
before its first job started, with a deterministic three-second sequence:

1. The first five-second bounded read sleeps for one second and must complete;
   the test asserts a 0.7-second lower bound to prove it actually waited.
2. The second five-second bounded read sleeps for four seconds and must return
   `TimedOut` using the shared remaining budget.
3. A four-second total upper bound proves the second read did not receive a
   fresh independent five-second timeout.

No production code changed.

### Verification

| Command | Result | Elapsed |
| --- | --- | --- |
| focused shared-budget Pester path | first read completed; second timed out; controlled sequence passed | 2.48 s |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script .\portable\tests\diagnose.Tests.ps1 -PassThru"` | Pester 3.4 / Windows PowerShell 5.1: 17 passed, 0 failed | 36.82 s |
| `git diff --check` | clean | < 1 s |

### Commit

- `f7a8e19ca4176d94f64a6ffbf42df05f0ae1f3a0` — `test(diagnose): strengthen shared budget coverage`

### Concerns

None. The upper bound retains enough scheduling headroom to avoid a flaky
filesystem or clock-dependent assertion while still failing if the second read
is given an independent timeout.
