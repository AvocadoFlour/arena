# Requests from maps

## Round 1 (done in v0.2)
run_tests discovery, INTERFACES §6 optional keys, SpawnPicker respawn hook — all integrated.

## Round 2 — capture zone logic (src/maps/capture_zone.gd)
1. **Core: instantiate zones in main.gd** after `MapLoader.build`:
   `for z in CaptureZone.from_map(map): add_child(z)` (one `CaptureZone` Node per capture zone; it
   ticks itself in `_physics_process`, counting alive heroes of group "heroes" inside its AABB).
   No zones on arena01, so arena01 is unaffected.
2. **Core: Events bus** — add `signal zone_changed(ev)`, `signal zone_captured(ev)`, `signal zone_contested(ev)`
   and forward from each zone (`z.state_changed.connect(Events.zone_changed.emit)`, etc.), so UI only listens.
   Payloads: state `{zone, owner, capturing_team, progress, contested}`; captured `{zone, team, previous}`;
   contested `{zone, contested}`. Teams int, neutral = -1.
3. **INTERFACES §6**: zone keys `capture_time` (s, solo, default 8), `player_scale` (rate multiplier per player
   count, last = cap, default [1,1.5,2]), `decay_rate` (/s when empty, default 0.1), `revert_rate` (default 1).
   `zones` meta entries now also carry these extra keys. Rules: >= 2 teams present = contested, progress pauses;
   a lone team first reverts another team's partial progress; owner standing on its zone reverts enemy progress;
   empty zone decays; reaching 1.0 sets owner and resets progress.
4. **UI (later)**: HUD widget listening to `Events.zone_changed` (owner colour, progress bar, "CONTESTED").
5. **Match/score** (win condition, timers) is out of maps scope — lead to decide.

## Round 3 — visual pass (data-driven, deterministic)
1. **INTERFACES §6** — document optional visual keys (no gameplay effect; collision unchanged):
   - `"theme"`: `sky_top, sky_horizon, ground_horizon, ground_bottom` (#hex), `sun_rot` [x,y,z], `sun_color`,
     `sun_energy`, `ambient_energy`, `fog_density` (enables fog), `fog_color`, `fog_sky_affect`. Defaults = v0.1 look.
   - `"materials"`: name → `{color, roughness?, metallic?, pattern?: grid|tiles|planks|bricks|stripes, pattern_scale?,
     tint?, emission?, emission_energy?, alpha?}`; patterns are fixed procedural 16x16 textures (no RNG).
   - block `"mat"`: palette name (falls back to `color`/`grid` when missing).
   - `"props"`: `[{shape: box|cylinder|cone|sphere, pos, size | radius+height, rot_deg?, mat|color, no_shadow?}]`
     → MeshInstance3D children of a `Props` Node3D under the map root; **no collision bodies**.
   Props were generated once at authoring time and stored in the JSON (deterministic for networking).
2. Perf note: under Xvfb software GL, arena02 screenshot run ~15 fps vs ~18 fps on master (fog + ~170 props).
   If needed for mobile, a quality setting could skip `Props`/fog (UI/core toggle) — not required now.

## Round 4 — low quality + perf
1. **UI/core: `low_quality` flag** — not on master yet. MapLoader reads it defensively
   (`MapLoader.low_quality_flag()`: `Settings.low_quality`, then `GameConfig.low_quality`, default false).
   Please add `var low_quality := false` to Settings (persisted) and expose it in the options menu; a map
   rebuild/reload is needed after toggling. Optional `-- --low_quality` CLI flag for capture/perf runs.
2. **INTERFACES §6**: `MapLoader.build(path, opts := {})` — `opts.low_quality` overrides the flag (tests).
   Low quality skips `Props` and fog; collision identical. Props are now batched: `Props` children are one
   merged MeshInstance3D per (material, shadow) group, meta `prop_count`. New optional theme keys
   `shadow_mode` (default PSSM 2 splits) and `shadow_distance` (default 60).
3. Suggestion: in low quality also disable sun shadows (measured: shadows are ~40 % of frame time under
   software GL). Not done since the task scope was props + fog.
