# Requests from AI (branch ai)

1. **tests/run_tests.gd (lead, tests infra)**: add `"res://tests/ai_unit_tests.gd"` to `SUITES` and
   run `tests/ai_nav_driver.gd` (navmesh/cover integration, ~300 physics frames) alongside
   `physics_driver.gd` — or invoke `godot --headless --path . -s tests/ai_run_tests.gd` as an extra
   build.sh step. Until then AI tests run via `tests/ai_run_tests.gd` (15/15 pass) and are not in the gate.
2. **INTERFACES.md §5 (lead)**: document new BotBrain params `difficulty` ("easy"|"normal"|"hard",
   default "normal"; sets spread_deg, turn_rate, fire_cone, reaction_time, aim_jitter, ability_delay,
   low_hp_frac, cover_time; explicit params override), `use_navmesh`, `seek_cover`; state `cover`;
   `use_abilities` now defaults to true. Navmesh: BotNav lazily adds a `BotNavRegion`
   NavigationRegion3D under the map root (node with `spawns` meta) and bakes it from static colliders.
   **No MapLoader change needed.** Cover blocks are found by StaticBody3D name containing "cover"
   (MapLoader names bodies after `kind`) — please keep that naming in the map contract.
3. **src/main.gd (lead)**: optional — pass `"difficulty"` to enemy `BotBrain.new()` from a setting /
   `--difficulty=` arg (UI could expose it in the menu).
