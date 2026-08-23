# SDD ledger — plan: docs/superpowers/plans/2026-08-22-yandifei-issues-13-7-14.md

Merge base: 82b5bd3ca70e30c672c1a79cee98c96971854b37
Task 1: in progress (issue #13; branch fix/pester-env)
Task 1: fix round 1/5 started — restore encoding-safe coverage for scan skip, critical events, startup fallback, and confirmation gate; remove synchronous two-pipe deadlock risk; assert subprocess success.
Task 1: fix round 1/5 (6 addressed, 0 open; commits 904c802..3e16c62)
Task 1: complete (commits 82b5bd3..3e16c62, review clean)
Task 2: in progress (issue #7; branch feat/7-driver-code-translate; temporary base fix/pester-env)
Task 2: fix round 1/5 started — add bounded printer/PnP queries, classify WSD offline as connection evidence, and cover buckets/HardwareID/printer branches with controlled tests.
Task 2: fix round 1/5 (2 addressed, 1 open — timeout needs an aggregate shared budget; commits 82d9f5a..9e0f299)
Task 2: fix round 2/5 started — make directory scans and new printer/PnP evidence consume one shared remaining-time budget.
Task 2: fix round 2/5 (runtime timeout addressed; 1 open — aggregate-budget test did not consume the one-second budget; commits 9e0f299..d18e2d7)
Task 2: fix round 3/5 started — make the aggregate-budget test demonstrably consume its first bounded wait before asserting the next read is denied remaining time.
Task 2: fix round 3/5 (1 addressed, 0 open; commits d18e2d7..f7a8e19)
Task 2: complete (commits 3e16c62..f7a8e19, review clean; PR #26 stacked on #18 until #18 merges)
Task 3: in progress (issue #14; branch fix/14-tui-single-instance; base 483f47b after #13 and #7 merge)
Task 3: fix round 1/5 started — reserve a dedicated duplicate-match exit code, fail open for every other query error, quote temporary-path arguments, and strengthen duplicate/nonmatching/query-failure test cases.
Task 3: fix round 1/5 (3 addressed, 0 open; commits 20abe36..57e9bfc)
Task 3: complete (commits 483f47b..57e9bfc, review clean; PR #27 merged)
