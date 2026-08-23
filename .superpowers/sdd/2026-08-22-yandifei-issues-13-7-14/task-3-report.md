# Task 3 Report — Issue #14 TUI single-instance guard

## Delivered

- Worktree: `C:\Users\yandifei\Desktop\黑客松-issue14`
- Branch: `fix/14-tui-single-instance`
- Commit: `20abe365c1e2605e9a73cc3bcc7b922868ad51eb` (`fix: guard against duplicate DSH TUI launch`)
- Committed files only:
  - `portable/start.cmd`
  - `tests/portable-start.tests.ps1`

`portable/start.cmd` now asks CIM for `node.exe` processes and compares each
process command line with this launcher's exact `%DSH_BIN%` path. A match
shows a Chinese duplicate-TUI message, pauses, and returns 1. CIM-query
errors fail open. The launcher neither changes processes nor uses PID files.

## Test-first evidence

1. Baseline command:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\portable-start.tests.ps1
   ```

   Result: 16 passed, 1 failed (pre-existing `.gitignore` expectation for
   `portable/.dsh-home/`).

2. After adding the regression tests and before adding the guard, the same
   command reported the expected new failures for missing CIM command-line
   inspection and for allowing the duplicate fake `node.exe` to launch, in
   addition to that baseline `.gitignore` failure.

3. Final focused launcher command:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\portable-start.tests.ps1
   ```

   Result: 19 passed, 1 failed. The 19 passing checks include:

   - CIM `Win32_Process` command-line inspection scoped to `node.exe` and the
     exact launcher DSH path.
   - no `tasklist` command-line matching and no PID-file logic.
   - a deterministic held fake `node.exe` with the fixture `bin.js` in its
     command line; the second launcher returns nonzero and prints the
     duplicate-TUI message.
   - normal no-match happy path, root wrapper path, runtime checks, and key
     behavior.

   Teardown verified `LEFTOVER_TEST_NODE_COUNT=0`; the test stops only the
   fake process created through its stored process object and ID.

4. Static encoding/path validation command (run immediately after the final
   launcher suite):

   ```powershell
   $bytes = [IO.File]::ReadAllBytes('portable\start.cmd')
   $text = [IO.File]::ReadAllText('portable\start.cmd', [Text.Encoding]::GetEncoding(936))
   ```

   Result: `START_CMD_UTF8_BOM=False`, `START_CMD_FIXED_DRIVE=False`, and the
   GBK-decoded Chinese duplicate message is present.

5. Scope/whitespace validation:

   ```powershell
   git diff --check
   git status --short
   git diff --name-only
   ```

   Result: no diff-check errors; only the two required task files were staged
   and committed. Git emitted its normal CRLF conversion warning for the
   PowerShell test file.

## Concern

The focused custom harness exits nonzero because of one pre-existing,
out-of-scope assertion: `.gitignore` does not contain `portable/.dsh-home/`.
It failed before this task began and was deliberately not changed because this
task is restricted to the two launcher files. All Issue #14-specific checks
pass.

## Task-review fix round 1

- Commit: `57e9bfc0c2c76f2eae99db884b6d716f211795b1`
  (`fix: fail open when TUI guard query fails`)
- Committed files only:
  - `portable/start.cmd`
  - `tests/portable-start.tests.ps1`

### Changes

- A positive exact command-line match is now the sole path that returns the
  dedicated PowerShell exit code `42`. CMD captures that result immediately
  in `DSH_GUARD_EXIT` and enters the duplicate block only when it is exactly
  `42`; missing PowerShell, policy restrictions, CIM errors, and other
  nonzero results continue to normal launch.
- The deterministic fake-node arguments are all quoted before
  `Start-Process`, and the complete fixture directory now has spaces in its
  name. This exercises the real launcher, normal launch, unrelated-node, and
  duplicate-node paths with space-containing paths.
- Coverage now verifies a failed process query launches normally without the
  duplicate block, an unrelated held `node.exe` command line does not block,
  exact duplicate matching does block, and the GBK-decoded message includes
  both the already-running text and the full close-window/Task-Manager stale
  `node.exe` guidance. Fake process cleanup remains by the exact spawned
  process object and ID.

### Commands and results

1. Test-first regression command:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\portable-start.tests.ps1
   ```

   Before the guard change: 19 passed, 3 failed. The two new Issue #14
   failures were the absent dedicated exit-code behavior and the query-failure
   path exiting 7; the third was the known `.gitignore` baseline failure.

2. Final focused launcher command:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tests\portable-start.tests.ps1
   ```

   Result: 21 passed, 1 failed. Passing new regressions cover the query
   failure fail-open path, unrelated fake `node.exe`, exact duplicate fake
   `node.exe`, and fixture paths containing spaces. The sole failure remains
   the unchanged `.gitignore` assertion for `portable/.dsh-home/`.

3. Encoding/path/teardown checks:

   ```powershell
   $bytes = [IO.File]::ReadAllBytes('portable\start.cmd')
   $text = [IO.File]::ReadAllText('portable\start.cmd', [Text.Encoding]::GetEncoding(936))
   Get-CimInstance -ClassName Win32_Process -Filter "Name = 'node.exe'"
   ```

   Result: `START_CMD_UTF8_BOM=False`, `START_CMD_FIXED_DRIVE=False`, full
   CP936 duplicate recovery text present, and `LEFTOVER_TEST_NODE_COUNT=0`.

4. Scope check:

   ```powershell
   git diff --check
   git diff --name-only
   ```

   Result: no diff-check errors; exactly the two requested task files were
   committed. Git emitted its normal CRLF conversion warning for the
   PowerShell test file.
