# Requests from AI (branch ai)

## Round 1 (done by lead in 0480509, thanks)
Test discovery, INTERFACES §5 params, GameConfig difficulty -> BotBrain.

## Round 2
1. **GameConfig team sizes (src/core/game_config.gd, INTERFACES §8, lead)**: add
   `ally_count: int` (bots on the player's team, default 0 for now; 2 for 3v3) and
   `enemy_count: int` (replaces/aliases `bot_count`, default 3), plus `-- --allies=N --enemies=N`.
2. **Spawner (src/main.gd, lead)**: spawn `GameConfig.ally_count` ally bots with `set_team(0)`,
   `spawn_point = spawns[0][(i + 1) % spawns[0].size()]`, same roster cycling and
   `BotBrain.new({"bounds": ..., "difficulty": GameConfig.bot_difficulty})`; ally damage_scale 1.0
   (or the difficulty scale; your call). Nothing else is needed: BotBrain already treats team 0 bots
   as allies (no friendly targeting, escorts teammates when idle, Willow bots heal hurt allies), and the
   heal beam (`heal_beam.pick_target`) already targets any same-team hero, so the player's support
   beam heals ally bots (tested in tests/ai_team_driver.gd). Smoke: `ok` should not require allies.
3. **Maps (Arena Maps, via lead)**: arena01 has only 1 team-0 spawn; 3v3 needs >= 3 team-0 spawns.
4. **INTERFACES §5 (lead)**: replace "Dynamic shield walls are not in the navmesh: bots are blocked by
   them until they expire" with: "`BotNav.sync_dynamic(map_root)` (called from bot path following, at
   most once per physics frame per map) rebakes the navmesh when the set of layer-1 StaticBody3D
   boxes that are siblings of the map root changes (shield walls); they become projected
   obstructions, so bots path around active walls; the navmesh is restored when they expire."
   Cover detection is now meta `kind == "cover"` (fallback: name prefix `cover`). New state `support`;
   new param `escort_allies` (true). Ability policy is type-based (`BotBrain.want_ability(type, ctx)`)
   for dash, charge, ground_slam, nova, rally, shield_wall, projectile, heal_beam.
   Convention for abilities adding transient world geometry: add it as a direct child of the world
   node (hero.get_parent()), StaticBody3D with BoxShape3D, so bots see it.

## Round 3
1. **tests/expected_warnings.txt (lead, tests infra)**: remove the `BotBrain: unknown difficulty 'bogus'`
   line (empty the file). AI tests no longer trigger it: they check `BotBrain.DIFFICULTY.has()` and the
   pure `BotBrain.resolve_difficulty()` instead. The runtime warning for a really unknown preset stays.
2. **src/core/melee_closer.gd + src/main.gd lines wrapping `MeleeCloser.wrap(...)` (lead)**: can be
   deleted. BotBrain now closes melee heroes (`primary.type == "melee"`) to ~0.6 × `primary.range`
   and only swings in reach; tests/ai_melee_driver.gd checks this with a plain, unwrapped BotBrain
   (The Best reaches 0.8 m and lands 9 hits in 6 s; a ranged bot still holds ~9-10 m).
   Input/ability interface unchanged: still `poll(hero) -> InputFrame` with the same fields.
3. **INTERFACES §5 (lead)**: add `leap` and `team_buff` to the type-based policy list; note melee
   awareness (stand-off = 0.6 × melee range) and `BotBrain.resolve_difficulty(name)`.

## Round 4 (stand-off fix)
1. **INTERFACES §5 (lead, doc only)**: ranged bots hold `standoff` (10 m) with a range-proportional radial
   term and a world-space tangential strafe (`BotBrain.standoff_dir`); when line of sight breaks they reverse
   strafe and keep the stand-off for `LOS_GRACE` (1 s) before pathing in, and remember an out-of-sight target
   for `TARGET_MEMORY` (2 s) instead of wandering or switching to a farther enemy.
   No interface change (still `poll(hero) -> InputFrame`). tests/ai_melee_driver.gd threshold back to 8.0 m
   (closest gap to the engaged target); bench: `godot --headless --path . -s tests/ai_standoff_run.gd -- --n=30`.
