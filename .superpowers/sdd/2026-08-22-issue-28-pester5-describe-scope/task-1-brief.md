# Task 1 — Pester 5 Describe scope compatibility

Perform this task in `C:\Users\yandifei\Desktop\黑客松-issue28` on branch `fix/28-pester5-describe-scope`, whose base is `b10de6419f2ac169281417affb87b7b7d38befa5`.

## Scope

Modify **only** `portable/tests/diagnose.Tests.ps1`. Do not change `portable/diagnose.ps1`, the skill, launcher, baking script, ADRs, `dsh/`, or `dsh-tui/`. Do not merge the branch or create a PR; the controller will independently review, verify, push, and create a PR that waits for team-lead approval.

## Required change

Pester 5 discovery and run use separate scopes. In the existing test file, move the entire contiguous setup block that is currently above `Describe 'Only-U offline diagnose'` into the body of that existing Describe immediately after its opening `{` and before its first `It`. The moved declarations must include `$repoRoot`, `$diagnoseScript`, `$skillFile`, `$windowsPowerShell`, `Get-Utf8Text`, every marker variable, and `Invoke-DiagnoseOutput`.

Do not alter helper bodies, marker bytes, existing `It` bodies, or test assertions. Do not add `#Requires` or lock either Pester major version. The existing suite currently has more tests than the original issue's historical 7/7 claim; preserve every current test.

## Encoding

Issue #28 requires UTF-8 BOM (`EF BB BF`). The current file was observed without one (`24 72 65`), so make the final file UTF-8 **with** BOM and verify its first three bytes. Do not corrupt the byte-decoded Chinese marker literals.

## Verification

First establish the Pester 3.4 baseline. If Pester 5.7.1 is not installed, you may obtain it only in a temporary external cache and import it by absolute module manifest path; do not modify global/user module installation. Run the complete file in Windows PowerShell 5.1 under Pester 3.4.0 and Pester 5.7.1, then record actual pass/fail counts and commands. Also check the BOM. Do not claim Pester 5 is green unless a fresh run supplies its output.

## Commit

Self-review the diff, stage only the test file, and make one focused commit with message `fix: scope diagnose tests for Pester 5`. Leave the worktree clean afterward.

## Report

Write a detailed report to `C:\Users\yandifei\Desktop\黑客松\.superpowers\sdd\2026-08-22-issue-28-pester5-describe-scope\task-1-report.md`: changed files, commit ID, each exact test command + results, BOM evidence, any unavailable prerequisite, and any concern. In your final reply return only `DONE`/`DONE_WITH_CONCERNS`/`BLOCKED`, commit, one-line test result, and concern summary.
