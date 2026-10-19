# tests
`godot --headless --path . -s tests/run_tests.gd` — unit tests + Jolt physics integration.
`./build.sh` = import → tests → 40 s autopilot smoke → Linux/Windows export → zip. Must pass to merge.
`tools/capture.sh` = Xvfb screenshots + MP4 of the demo from the Linux export.

Discovery: `tests/test_*.gd`, `tests/<owner>_test_*.gd`, `tests/<owner>_test.gd` (unit, methods `test_*`, extend test_base.gd);
`tests/physics_driver.gd` + `tests/<owner>_sim.gd` (integration Node with `done`/`results`, run sequentially, each in its own world).
Smoke runs once per hero JSON.

## Smoke timing (build.sh step 3/5)
build.sh prints each map x hero run's seconds and the step's start/end (Europe/Warsaw), appends
`timestamp,version,runs,seconds` to `build/smoke_durations.csv`, and when the whole step takes more than 600 s prints
`WARNING: SMOKE SLOW: <N>s > 600s (<runs> map x hero runs)` and appends a line to `build/smoke_alerts.log`. It never fails
the build. Each run takes about 36 s, so 10 min is crossed at about 17 runs: with 2 maps, 8 heroes = 16 runs
(about 9.6 min), 9 heroes = 18 runs (about 10.8 min). History: docs/smoke_test_history.md.
