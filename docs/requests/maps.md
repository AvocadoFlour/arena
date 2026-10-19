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

## Queue item 3 — health packs + jump pads (maps side done; needs core net/event hooks)
Map JSON: `"pickups": [{"kind":"health","pos","amount":50,"respawn":15,"radius"?:1}]`,
`"jump_pads": [{"pos","size":[x,y,z],"launch":[vx,vy,vz]}]`. Ids = index in each array (same on every peer).
Built into map root child `Objects` (`MapObjects`), visuals only — **no physics bodies** (triggers are fixed-tick
position checks in `_physics_process`, deterministic, independent of Area3D callback order), so the collision
golden is unchanged (0 additions). Low quality keeps them (gameplay objects).
Host/offline (`Net.is_authority()`): `step(heroes)` each physics tick — pack heals via `hero.heal(amount)` (only
consumed if it healed > 0), then respawns after `respawn` s counted in 60 Hz ticks; pads set `hero.velocity =
launch` when the hero is inside the pad box and not rising (re-arm 0.5 s per hero/pad). Clients: `step` no-ops.
Signals on `Objects`: `pickup_taken({id, hero, amount})`, `pickup_respawned({id})`, `pad_launched({id, hero, velocity})`.
Client entry points: `apply_pickup(id, active, respawn_left)`, late join `apply_state(state())`,
`state() = {"pickups": [[id, active, left], ...]}`.

Requests (core):
1. **Events + Net**: add `signal pickup_changed(ev)` (`{id, active, left}`) and `signal pad_launched(ev)`
   (`{id, hero, velocity}`) to events.gd, and both to `Net.EVENT_SIGNALS` (reliable). `Objects` already emits
   them on the host when they exist and, on clients, already listens to `pickup_changed` and calls `apply_pickup`.
   (`healed` from `hero.heal` already covers the HP change; pad_launched is for FX/sound only.)
2. **Late join**: add `"objects": map.get_node("Objects").state()` to the welcome info (only if the node exists);
   client after map build: `map.get_node("Objects").apply_state(info.get("objects", {}))`.
3. **Jump pad prediction (client's own `predicted` hero)**: launch is a pure function of the map data. In the
   predicted step (and in reconciliation replay), before `Motion.step_velocity`, call
   `hero.velocity = objects.predict_pad(hero.global_position, hero.velocity)` — identical rule to the host
   (inside pad box, `velocity.y <= 0.5`), so prediction and host agree and no correction happens. Without this
   hook the client keeps walking over the pad until the host snapshot arrives, error exceeds 0.15 m and the
   existing reconcile snaps it up (~1 RTT late, visible pop). Puppets need nothing (snapshot-driven).
4. **INTERFACES §6**: document the two keys and the `MapObjects` API above.
5. **UI (optional)**: show pack respawn timers from `pickups[i].left` / `pickup_changed.left`.
6. **Fix bundled with item 3 (master was red)**: master 9eff0fd fails `ai_teamplay_driver::team_groups_up`
   (and, after a first relocation attempt, `focus_fire_concentration`) because of item 2's two mid-lane
   breakables on arena02 at (−6,13)/(6,−13). Verified with the driver seeded exactly as run_tests.gd (4242):
   no breakables → pass (5.1 m vs 6.2 m; focus 0.85 vs 0.72); flank pair only → identical pass; mid pair (at
   either spot tried) → fail. So the mid pair (`cover_44`, `cover_45`, last in `blocks`) is removed; the flank pair
   `cover_42`/`cover_43` stays. Golden: exactly those two entries dropped vs master, nothing else changed.
   **AI (FYI)**: those two checks are single-seed comparisons that flip on small geometry changes near mid; a
   multi-seed mean or a margin would make them robust to future map edits.

## Maps queue (1.0) item 1 — protected spawn rooms + spawn-shield hook (maps side done; needs core hooks)
Data (map JSON, deterministic, no RNG):
- `spawn_rooms."<team>".barriers`: `[{"pos","size"}]` boxes on the room openings (arena02: the front door and the
  two 1.5 m back-corner gaps behind the side walls, per team). Room `pos`/`size` unchanged (meta `spawn_rooms` as before).
- `spawn_areas`: `{"<team>": [{"pos","size"}]}` open protected spawn areas for maps without room geometry (arena01:
  player area around (0, 15), bot corners around (±13, −16); the central platform spawn stays unprotected). Kept
  out of `spawn_rooms` on purpose: `GameConfig.allies_for` treats a team-0 spawn room as a team map, and arena01
  must stay FFA (meta `spawn_rooms` on arena01 is still `{}`).
- `spawn_shield` (s, default 2.0); optional theme `team_colors` (default `["#5a8ad8", "#e06a6a"]`).

Node: map-root child `SpawnRooms` (src/maps/spawn_rooms.gd, `process_physics_priority = 100`, after heroes move).
Keep-out volumes per team = room box + its barrier boxes + its areas (xz, from 0.5 m below to 3 m above the top).
**Why not per-team collision layers:** every hero ray (hitscan `hero.gd`, `projectile_shot.gd`, `BotBrain._visible`)
uses `PhysicsRayQueryParameters3D.create(from, to)` with the default all-layers mask, so a team-layer StaticBody
would also stop bullets, projectiles and bot sight for both teams (the owner couldn't shoot out of its own door).
So the host resolves positions instead: each fixed tick, a living hero of team T inside a volume of team ≠ T
(grown by its collider radius) is moved to the exit face nearest its previous tick position (union-aware, so the
overlapping room + door boxes resolve in one step) and its inward velocity is zeroed. Owners pass freely. No
physics bodies → **collision golden unchanged (0 additions, 0 changes)**; navmesh, SpawnPicker and rays unchanged.
Low quality keeps the barrier visuals (3 merged meshes per team: alpha fill, team-colour frame, black hulls).

Host/offline API (`Net.is_authority()`; clients: `step` no-ops):
- `resolve(team, pos, vel, prev_pos, radius = 0.4) -> [pos, vel, pushed_by_team (-1 none)]` — pure rule, also for prediction.
- `owner_at(pos, radius = 0) -> team|-1`, `in_team_volume(team, pos)`, `in_own_room(hero)`.
- Spawn shield: a hero that becomes alive (match start, respawn, hero swap, new bot) gets `spawn_shield` s; if it
  spawned inside its own room/area the shield ends early when it leaves; death ends it. `is_shielded(hero) -> bool`,
  `shield_left(hero) -> float`. Signals: `spawn_shield_changed({hero, active, left, reason: spawn|timeout|left_room|died})`,
  `own_room_changed({hero, inside})`, `pushed_out({hero, team, pos})`. If `Events` has `spawn_shield`, the same
  payload is emitted there too (host only).

Requests (core):
1. **Damage gate (the shield itself)**: in `Hero.take_damage` (after the authority check) skip damage while
   shielded: `var sr = <map>.get_node_or_null("SpawnRooms"); if sr and sr.is_shielded(self): return 0.0`
   (map lookup like `Net.map_objects()`; a `Net.spawn_rooms()` helper would do). Suggest also ending the
   shield when the hero fires/uses an ability — say if you want a `drop_shield(hero)`
   call and I'll add it.
2. **Events + Net**: `signal spawn_shield(ev)` in events.gd and `"spawn_shield": 1` in `Net.EVENT_SIGNALS`
   (reliable) so HUD/FX on clients can show the shield (UI: e.g. a team-colour bubble / "Spawn shield" HUD tag).
3. **Client prediction** (own `predicted` hero): after `move_and_slide()` in the predicted step and in reconcile
   replay: `var r = sr.resolve(team, global_position, velocity, pos_before_move, radius); global_position = r[0];
   velocity = r[1]` — identical to the host, so walking into an enemy door never causes a correction. Without it
   the client is snapped back by normal reconciliation (~1 RTT, visible pop). Puppets need nothing.
4. **INTERFACES §6**: document `barriers`, `spawn_areas`, `spawn_shield`, `team_colors` and the `SpawnRooms` API.
5. **AI (FYI)**: enemy volumes aren't in the navmesh (no bodies), so a bot told to go into an enemy spawn just gets
   held at the door. Suggest skipping wander/chase targets where `SpawnRooms.owner_at(p) not in [-1, my team]`.
   No AI suite failed with this change (see build).

## Maps queue (1.0) item 2 — sightline / readability / snag pass (maps side done; no core hooks needed)
Tools (tests, deterministic): `tests/maps_snag_sim.gd` — real Jolt CharacterBody3D capsules (widest: Cob r 0.65 h 1.5;
slimmest/tallest: Tomo r 0.36 h 1.85) driven by `Motion.step_velocity` in 8 directions from a sampled MapGrid
(2 m in the suite; `tests/maps_snag_scan.gd -- --spacing=1.0` lists every hit): stuck points (can't get 0.3 m away
even jumping), lips (blocked on a ≤ 0.3 m step-up along a slope or onto a flat deck) and level gaps/seams/corners
narrower than the collider. `tests/maps_sight_sim.gd` (+ `maps_sight_scan.gd`): longest ground sightline with no
cover within 2.5 m, spawn-door camping spots (> 20 m, eye sees the door exit), passages narrower than Cob between
two spots where Cob fits, and "cover that hides nothing" (every cover / free-standing wall piece is the occluder for
≥ 20 % of threat spots from one side). `tests/maps_read_test.gd`: ramp ends flush (≤ 0.1 m lip), arena01 cover
variety, arena02 additions point-symmetric, new blocks clear of rooms/zones/pickups/pads/spawns, golden = v0.9 golden
(`tests/maps_collision_golden_v09.json`) + additions except the listed exceptions, reachability around new blocks.

Findings → fixes (before → after, spacing 1 m scan):
- arena01 snag: `ramp_07` (side ramp to the platform) had a 0.19 m lip at its foot and a 0.27 m lip where it meets the
  platform top (slim heroes stopped dead walking off the platform onto it). → 0 stuck / 0 lips / 0 gaps on both maps.
- arena02 dais: `ramp_18` / `ramp_19` (east/west) were rotated the wrong way — they rose AWAY from the dais
  (1.03 m step at the outer end, 0.84 m drop at the dais edge), so the capture point had only 2 working ramps.
- arena02 sightlines: longest uncovered ground lane 74 m (z = 0 straight across the map through the flank openings)
  and 56 m along the outer corridors / x = ±12 → 36 m (the remaining one is the mid diagonal across the open
  capture dais, left alone on purpose). Spawn-door camping spots > 20 m: 185 / 180 → 27 / 30 (all remaining are on
  the 4 m balconies looking down).
- arena01 sightlines: 34 m along the strip in front of the player spawn → 23 m. Narrow passages: 0 (both maps).

**Collision changes to existing blocks (explicit exceptions to "golden additions only"):**
1. arena01 `ramp_07`: pos (−8.05, 1.55, −10) → (−7.94, 1.27, −10); size/rotation unchanged. Moves the top-surface
   end flush with the platform edge (corner 3.27 → 2.99 at x = −5.0) and buries the foot 0.09 m below the floor
   (corner 0.185 → −0.095). Only way to remove both lips without new geometry on the platform.
2. arena02 `ramp_18` rot_deg z 14 → −14 and `ramp_19` −14 → 14 (pos/size unchanged): flips them so they rise to the
   dais like `ramp_16`/`ramp_17`. Checked: ai_teamplay_driver (seed 4242) still passes (focus 0.90 vs 0.69, team
   groups up 5.0 m vs 8.0 m, tank holds point 60 %).
Everything else is appended at the end of `blocks` (indices, names and collision of all other blocks unchanged).

Additions (all non-`cover` kind, so AI cover counts are unchanged):
- arena01 (cover variety, south strip; away from the AI test spots, x = −3.5 walker lane and (15, 15)): `wall_16`/`wall_17`
  L-shaped 1.1 m half wall at (−9.5…−11.3, 14.5…15.6); `wall_18` 3.5 m slim column (8, 16.5); `wall_19` 1.3 m slab rotated
  45° at (10.2, 14.2). arena01 still has exactly 8 `cover` blocks.
- arena02 (point-symmetric pairs): balcony support pillars under the outer balcony edge (±31.5, z ±6); 1.2 m low walls
  in the outer corridors (±36, ±12) and the x = ±11 side lanes (±11, ±16); 1.2 m blockers in the flank openings
  (±20, 0); 2.4 m team-colour wing walls beside each spawn door (±5, ±19.75) that cut the sideways camping lines
  along the room fronts. Clear of barriers/keep-out volumes, zones, pickups, pads and spawns (tested).

Requests:
1. **AI (FYI / optional)**: `tests/ai_team_driver.gd` asserts exactly 8 cover blocks on arena01; the new pieces use
   kind `wall` to respect that, so bots don't treat them as cover. If you relax it to `>= 8` I can retag the arena01
   half wall / slab and the arena02 low walls as `cover` (better bot cover use). The flipped dais ramps change mid
   pathing slightly; teamplay still passes at seed 4242, but it remains a single-seed check (see queue 3 note).
2. **Core (FYI)**: no hooks needed. INTERFACES §6 could note "ramp ends must be flush (≤ 0.1 m)" and the scan tools.
