### Task 3: Issue #14 — TUI single-instance guard

**Files:**
- Modify: `portable/start.cmd`
- Modify: `tests/portable-start.tests.ps1`

**Requirements**

1. This task starts only after Issue #13 is merged into `main`; create branch `fix/14-tui-single-instance` from that merged `main`.
2. Before the normal DSH TUI launch, detect an already running `node.exe` whose **command line** contains this launcher's exact `%DSH_BIN%` (`runtime\\dsh\\lib\\bin.js`) path. It must not block unrelated `node.exe` processes.
3. `tasklist` lists image names but not command lines, so do not rely on a `tasklist | findstr` command-line match. Use a read-only Windows process query that can inspect the `node.exe` command line (for example PowerShell/CIM `Win32_Process`) and fail open if that query itself is unavailable.
4. If a matching process is found, print a clear Chinese message that DSH TUI is already running, tell the user to close the existing window or end the stale `node.exe` in Task Manager, pause, and `exit /b 1`. No PID files; do not modify `lib\\bin.js`, DSH runtime, or processes.
5. Normal launch without a matching command line must retain the existing runtime/key/network behavior.
6. Preserve `portable/start.cmd` as ANSI/GBK without a UTF-8 BOM; it is a CMD launcher. Do not change `Start-Agent.cmd`.
7. Extend the repository's existing custom `tests/portable-start.tests.ps1` harness (it is not a Pester file) with a deterministic fake `node.exe` whose command line contains the test fixture's `bin.js`. Assert that a second `start.cmd` invocation returns nonzero and produces the duplicate-TUI message. Ensure teardown stops only the spawned fake process. Retain happy-path coverage.
8. Add static test coverage for exact command-line process inspection and for the absence of PID-file logic. Keep all test output decoding explicit GBK/UTF-8 as appropriate.
9. Verify focused launcher tests. The controller opens the PR with `Closes #14` as its first body line.
