# Requests from heroes (round 1)

Nothing here blocks the heroes branch; all gameplay code is inside src/heroes + src/abilities.

1. **tests/run_tests.gd (tests infra)** — register the heroes suites so ./build.sh runs them:
   add `"res://tests/heroes_test_defs.gd", "res://tests/abilities_test_projectile.gd"` to `SUITES`,
   and run the integration scene `res://tests/abilities_sim.gd` (same `done`/`results` shape as
   `physics_driver.gd`). Until then: `godot --headless --path . -s tests/heroes_run.gd`.
   (Better long term: auto-discover `tests/<owner>_test_*.gd`.)
2. **INTERFACES.md §2.2** — document new hero API used by abilities:
   `apply_slow(mult, dur)`, `slow_mult`, `heal(amount) -> float`, `effective_move_cfg()`,
   `eye_position()`, `aim_camera`, `yaw`, `team`, `damage_scale`, `get_parent()` (abilities spawn
   world nodes: projectiles, shield walls). Also new damage kinds `projectile`, `charge`.
3. **INTERFACES.md §2 (optional, v0.2)** — allow `"primary": {"type": "projectile", ...}` using the
   same params as the `projectile` ability (speed, damage, gravity, lifetime, hit_radius,
   splash_radius, slow). Firing lives in hero.gd (heroes-owned) but Weapon/schema are core;
   not implemented until approved.
4. **src/main.gd** — spawns only kestrel.json. Hero selection / mixed bot rosters needed to put
   rampart.json and willow.json in-game (e.g. bots pick from a list of hero JSONs).
5. **Bot AI / UI note** — shield walls are StaticBody3D on layer 1 (block everyone for `duration`);
   heal_beam is a channel; HUD may want `ability.channeling()` / `slow_left` later.
