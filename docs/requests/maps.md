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

## Round 5 — runner hardening
1. **tests/run_tests.gd gap**: a unit test that raises a runtime script error (e.g. invalid key access) just
   returns early with no `check()` errors and is reported `ok`; build.sh does not grep tests.log for
   `SCRIPT ERROR`. tests/maps_run.gd now catches this with a `Logger` (`OS.add_logger`, counts non-warning
   errors per test). Suggest the same in run_tests.gd (or grep tests.log for SCRIPT ERROR in build.sh).
2. Discovery quirk: run_tests.gd skips any file whose name contains "run" — e.g. `*_runtime_test.gd` would be
   silently ignored. Suggest matching `_run.gd` / `_run_tests.gd` suffixes instead.

## Queue item 1 — toon restyle
1. **INTERFACES §6** (visual-only theme/material keys, collision unchanged):
   theme `toon` (bool: palette materials use `src/maps/toon/map_toon.gdshader`, flat 2-tone with sun shadows,
   no ambient/specular), `tonemap` ("filmic" default | "linear"), `outline_width` (m, >0 enables merged
   inverted-hull outlines: one `Outlines` MeshInstance3D, front-culled unshaded, no shadow/collision, meta
   `hull_count`), `outline_color`; per material `shade` (shadow tone multiplier, default 0.74) and `outline`
   (false = no hull; floors/decals); per block/prop `outline: false`. Low quality keeps block hulls, drops prop hulls.
   `MapLoader.mat_color(mat)` returns the base colour of either material type.
2. **Heroes (FYI, no change needed)**: ToonKit's normal-push outline leaves gaps on hard-edged box meshes, so
   maps grow hulls per shape instead (same visual: black inverted hull). Map scenes now use linear tonemapping
   (theme `tonemap: "linear"`) so unshaded toon heroes render at their exact authored colours too; please
   confirm with the heroes owner that this is fine (it slightly darkens heroes vs filmic).

## Queue item 2 — destructible cover (maps side done; needs core net hooks)
Maps side: block `{"kind":"cover", ..., "hp": N}` → `DestructibleCover` (StaticBody3D, meta kind "cover",
name `cover_NN`, group `destructible`, own outline hull child). `block_id` = index in the JSON `blocks` array
(identical on host and clients). Manager: map root child `Destruction` (`MapDestruction`).
Host/offline decides: `cover.apply_damage(amount, source) -> applied` (alias `take_damage(amount, source, pos,
kind, ability_id)`, same signature as Hero) returns 0 when `Net.is_authority()` is false. At 0 HP:
`Destruction.cover_broken({block_id, pos, map})` is emitted and, if `Events` has a `cover_broken` signal, also
`Events.cover_broken(ev)`. Removal: collision off + hidden immediately, then `queue_free` (§6 rule).
Clients: `Destruction.apply_break(block_id)` (idempotent); late join: `Destruction.apply_broken(ids)`,
host side `Destruction.broken_ids()`. If `Events.cover_broken` exists, `Destruction` already listens and calls
`apply_break` on non-authority peers — so with request 1 no extra client code is needed.

Requests (core / heroes):
1. **Events + Net**: add `signal cover_broken(ev: Dictionary)` to src/core/events.gd and `"cover_broken": 1`
   to `Net.EVENT_SIGNALS` (reliable). That replicates the host's break to clients through the existing event path.
2. **Late join**: in `_c_hello` add `"broken_cover": map.get_node("Destruction").broken_ids()` to the welcome
   info; on the client after the map is built: `map.get_node("Destruction").apply_broken(info.get("broken_cover", []))`.
3. **Damage routing (heroes/core)**: hitscan (hero.gd ~L434), melee, projectiles and `aoe()` currently only
   damage `Hero`. Add: `elif c.is_in_group("destructible"): c.take_damage(dmg, self, end, kind)` (hitscan/
   projectile hit collider); for AoE, `for c in get_tree().get_nodes_in_group("destructible")` within radius
   (use `HitMath.aoe_damage` falloff on distance to `c.global_position`). Host only (take_damage already no-ops
   on clients). Damage to cover should not charge ult (`on_damage_dealt`) — suggestion, your call.
4. **INTERFACES §6**: document the `hp` key, `DestructibleCover`, `MapDestruction` API above.
5. **Golden file**: tests/maps_collision_golden.json regenerated; only additions in arena02 `cover_42`..`cover_45`
   (new blocks appended at the end of `blocks`, so every existing block keeps its index, name and collision;
   verified: 0 entries removed/changed). arena01: unchanged golden — the two existing low walls `cover_10`,
   `cover_11` (z=10) got `"hp": 300` instead of adding blocks, because tests/ai_team_driver.gd (ai-owned)
   hardcodes 8 cover blocks on arena01. AI: if you'd like extra breakables on arena01, relax that count.
