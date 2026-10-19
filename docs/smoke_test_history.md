# Smoke test ([3/5]) duration history — night of 18→19 Oct 2026 (times Europe/Warsaw, CEST)

build.sh prints **no timestamps**. Durations below come from file mtimes in each tree's `build/`:
start = `build/tests.log` mtime (end of step 2), end = mtime of the last `build/smoke_<map>_<hero>.log`.
Only the **latest** run per tree leaves per-combo logs, so older runs (/tmp/*.log) give combo counts only.
"Measured" = both mtimes from the same run; "inferred" = tests.log was overwritten later, so start ≈ first combo log mtime − ~36 s (one combo).

| Build (tree) | Version | Smoke window | Combos (maps×heroes) | Duration | s/combo | Basis | Parallel builds |
|---|---|---|---|---|---|---|---|
| Tomo worktree | 0.9 | 00:24:12–00:28:57 | 8 (2×4) | 285 s (4:45) | 35.6 | measured | — |
| Niđo worktree | 0.9 | 00:44:12–00:50:08 | 10 (2×5) | 356 s (5:56) | 35.6 | measured | main /tmp/build.log & maps_build.log ended 00:48–00:49 (overlap) |
| AI worktree (ai_build4) | 0.9 | ~02:02:37–02:08:33 | 10 (2×5) | ~356 s | ~35.6 | inferred | — |
| Maps worktree (maps_build_run) | 0.9.1 | 03:02:42–03:08:40 | 10 (2×5) | 358 s (5:58) | 35.8 | measured | Heroes b_ubel.log ended 03:09:47 (overlap) |
| Heroes worktree (b_ubel) | 0.9.1+Übel | ~03:14:51–03:21:58 | 12 (2×6) | ~427 s | ~35.6 | inferred | — |
| **Main merge 0.9.3** (/tmp/build_m.out) | 0.9.3 | 04:17:17–04:21:00 | 6 of 12 run | 223 s, **stopped: SMOKE FAIL arena01/ubel** | 37.2 | measured | UI build.sh (started 04:12:11) in smoke at same time |
| UI worktree (/tmp/ui_build.log, running) | — | 04:18:00–(running) | 5+ of 12 at 04:20:23 | 143 s so far | ~28.6* | measured, partial | main 0.9.3 build |

\*UI per-combo looks faster only because the current combo isn't finished yet when sampled.

Other completed builds whose smoke ran (no per-step timing recoverable, combo count only): hb4 00:07 (6), build.log 00:48 (6), maps_build 00:49 (6), nbuild/nbuild2 00:27/00:38 (8), hb7 01:15 (8), maps_build2/3 01:01/01:48 (8), ai_build3 01:36 (8), nbuild3 00:51 (10), b_item1–3 01:58/02:21/02:43 (10), sfxvol_build 02:42 (10), build_hf (0.9.2) 02:52 (10). Aborted before/during smoke: build.out 00:13, ai_build 01:05, ai_build2 01:17 (EXIT 143).

## Trend
- Per combo cost is flat at ~35.6 s: each run is `--smoke=35` (forced end at 32 s) plus engine start/exit, far under the 180 s timeout.
- Total smoke time grows linearly with roster: 3 heroes (6 combos, ~3.5 min) → 4 (8, 4:45) → 5 (10, ~6 min) → 6 with Übel (12, ~7 min). Map count stayed at 2 (arena01, arena02).
- Parallel builds have only a small effect: the 0.9.3 main run averaged 37.2 s/combo while UI ran build.sh alongside (~+4%). Headless smoke is wall-clock bound, not CPU bound.
- Expect ~36 s × maps × heroes per build; each new hero adds ~72 s, each new map ~36 s × heroes.

## 0.9.3 status at time of writing (04:21)
Smoke ran 223 s, passed 5 combos on arena01, then **failed on arena01/ubel** ("SMOKE FAIL", ability1 = 0 although forced), build exited 1 at 04:21:00. No package/tag.
