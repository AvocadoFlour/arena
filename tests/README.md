# tests
`godot --headless --path . -s tests/run_tests.gd` — unit tests + Jolt physics integration.
`./build.sh` = import → tests → 40 s autopilot smoke → Linux/Windows export → zip. Must pass to merge.
`tools/capture.sh` = Xvfb screenshots + MP4 of the demo from the Linux export.

Discovery: `tests/test_*.gd`, `tests/<owner>_test_*.gd`, `tests/<owner>_test.gd` (unit, methods `test_*`, extend test_base.gd);
`tests/physics_driver.gd` + `tests/<owner>_sim.gd` (integration Node with `done`/`results`, run sequentially, each in its own world).
Smoke runs once per hero JSON.
