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

## Round 5
1. **Smoke stats (src/main.gd, lead)**: `bot_dmg` counts only damage *to the player*. On arena02 (Control,
   3v3) the two ally bots stand in front and soak enemy fire (enemies target the nearest visible hero), and the
   Twin Tails autopilot holds its 10 m stand-off, so `bot_dmg` is naturally low (14-245 over 8 seeds with
   allies; 165-316 with `--allies=0`). Not an AI bug. Suggest adding `team0_dmg_taken` (damage to any team-0
   hero) and `ally_heal` to STATS so team-mode runs show enemy pressure and support activity.
2. **Smoke `forced` ability1 for twin_tails/arena02 (lead, FYI)**: the heal beam is situational (an ally < 80 %
   or self < 70 %); in seeds where nobody is hurt by 0.6 × smoke time, the force is expected.

## Round 5
1. **Smoke stats (src/main.gd, lead)**: `bot_dmg` counts only damage dealt *to the player*. On team maps
   (arena02 Control: player + 2 ally bots vs 3) enemies shoot the nearest visible hero, which is usually a
   front-line ally (Cob/The Best) while a Twin Tails autopilot stays ~10 m back, so player damage is low
   (seeds 4242,1-7: 14-170) and varies a lot by seed. With `--allies=0` the same runs give 165-316. This is
   intended team behaviour, not a bot bug. Please add `team_dmg_taken` (damage dealt by team 1 to any
   team-0 hero) and, if a damage gate is wanted on team maps, use that instead of `bot_dmg`.
2. **Smoke forcing (FYI)**: `forced:["ability1"]` for arena02/twin_tails means nobody needed healing in the
   first 21 s, so the heal beam was not used. That is correct for the support bot (it heals allies below
   80 % HP and itself when hurt).
3. **INTERFACES §5 (doc)**: support bots look for hurt allies within `support_radius` (35 m, no line of
   sight needed), walk over on the navmesh and channel the beam once in range with line of sight
   (`heal_below` 0.8). Bots ignore heroes in other World3Ds, because test SubViewports share the "heroes" group.
