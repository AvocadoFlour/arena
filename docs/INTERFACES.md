# Module contracts (owner: lead bot only — other bots propose changes, never edit)

Modules talk only through these shapes. Anything not listed here is private to its module.

## 0. Game loop & timing
- Physics: fixed **60 Hz** (`physics/common/physics_ticks_per_second=60`), max 8 steps/frame.
- Per tick, each `Hero._physics_process(dt)`: `frame = input_source.poll(hero)` → apply look →
  tick weapon & abilities → reload/abilities → `Motion.step_velocity` → dash override →
  `move_and_slide()` → landing hooks → fire → fall-out check.
- Render/HUD in `_process` (variable rate, vsync). Gameplay state is only mutated in physics ticks.
- Physics engine: Jolt. Collision layer 1 = world + live heroes (dead heroes use layer 0).

## 1. Input (src/core)
`InputFrame` (RefCounted), one per tick:
| field | type | meaning |
|---|---|---|
| move | Vector2 | x = strafe right, y = forward, length ≤ 1 |
| look | Vector2 | radians this tick: x = yaw (+ left), y = pitch (+ up) |
| fire | bool | held |
| jump, reload, ability1, ability2, ultimate | bool | pressed this tick (edge) |

**Input source interface**: any object with `poll(hero) -> InputFrame`.
Implementations: `Actions` (keyboard/mouse autoload), `BotBrain` (AI). Planned: touch, network.

**Action map** (`Actions.BINDINGS`, registered into Godot `InputMap`):
`move_forward/back/left/right, jump, fire, ability1, ability2, ultimate, reload, pause, scoreboard` (Tab; UI-only, never in InputFrame).
Adding a device = append `{contribute(frame: InputFrame)}` object to `Actions.sources`
(e.g. a TouchControls node that ORs its buttons and adds its stick to `frame.move`/`frame.look`).
Gameplay code never reads `Input` directly.

## 2. Hero definition (src/heroes/*.json)
```json
{ "id", "name", "role", "max_hp",
  "movement": {"speed","accel_ground","accel_air","jump_velocity","gravity"},
  "collider": {"radius","height"},
  "primary": {"type":"hitscan","damage","fire_rate","mag","reload_time","spread_deg","range"},
  "ultimate_cost": 500,
  "abilities": {"ability1": {...}, "ability2": {...}, "ultimate": {...}},
  "model": [{"shape":"capsule|sphere|box","radius","height","size":[x,y,z],"pos":[x,y,z],"color":"#hex|team","muzzle":bool}] }
```
Model parts (optional visual keys, approved v0.4, heroes round 3): `"rot"` [x,y,z] degrees, `"scale"` [x,y,z],
`"pivot"` [x,y,z] (part rotates about this point), `"metallic"`, `"roughness"`, `"emission"` (#hex),
`"anim"` ∈ `tail|weapon|leg_l|leg_r|arm_l|arm_r|head`. Parts live under a `Visual` child node animated in
`_process` from existing state (velocity, is_on_floor, weapon cooldown, combo_step, dash_time). **Visual-only and
client-side**: never replicated; on online clients puppets get a velocity derived from interpolation so run/lean
animates, while weapon/combo/dash state is not synced (swing/recoil may not animate on remote heroes).

Camera (optional, v0.7): `"camera": {"back": m, "up": m, "side": m}` offsets CameraRig's over-the-shoulder
camera for big models (added to the 3.2 m spring length, the 1.55 m pivot height and the 0.7 m shoulder offset).
Cob uses `{"back": 0.6, "up": 0.3}`.

### 2.1 Primary types
- `hitscan` (default): `damage, fire_rate, mag, reload_time, spread_deg, range` — core `Weapon`.
- `melee` (v0.3): `{"type":"melee","damage","fire_rate","mag" (999 = no ammo),"reload_time","range","arc_deg",
  "combo":[mult…],"combo_window","finisher_knockback","lunge"}`. `Weapon` still gates rate; hero.gd
  `melee_swing()` hits every enemy within `range` inside the frontal `arc_deg` (`MeleeMath.in_arc`), damage =
  `damage × combo[i] × damage_mult()`, combo index resets after `combo_window` s; the last combo hit knocks back
  by `finisher_knockback`. Damage kind `primary`. Bots should close to `primary.range`.
- `projectile` primary: still deferred.

### 2.2 Ability
Ability def: `{"id","type","name","cooldown", ...type params}`. `type` → script via
`AbilityRegistry.TYPES`. Script extends `Ability`: `_init(hero, def)`, `can_activate()`,
`activate() -> bool` (calls `_do()`, starts cooldown), `tick(dt)`, `on_landed()`.
Abilities may use the hero API: `velocity, last_wish, look_dir(), is_on_floor(), dash_time,
dash_vel, slam_pending, ult, aoe(center, radius, dmg, kind)`.

Hero API for abilities (v0.2, approved with the heroes merge):
| member | contract |
|---|---|
| `apply_slow(mult, dur)` | movement speed × `mult` for `dur` s; stronger (lower) mult wins, longest duration kept; cleared on death |
| `slow_mult`, `slow_left` | current slow (read-only for others; HUD may show) |
| `heal(amount) -> float` | restores HP (no overheal), returns amount healed; 0 if dead |
| `effective_move_cfg()` | `movement` dict with slows applied (what `Motion.step_velocity` gets) |
| `eye_position()`, `look_dir()`, `aim_camera`, `yaw`, `pitch`, `team`, `damage_scale` | aim/teaming; read-only for abilities |
| `get_parent()` | the world node: abilities may add transient nodes there (projectiles, shield walls, FX) |
v0.3 hero API (heroes round 2):
| member | contract |
|---|---|
| `damage_mult() -> float` | `damage_scale × active buff`; ALL hero/ability damage must use it |
| `apply_buff(mult, dur, kb_immune)` | outgoing damage × mult for dur s; optional knockback immunity |
| `knockback(v: Vector3)` | adds velocity; ignored while `knockback_immune` |
| `add_overheal(amount, dur)`, `overheal` | shield HP absorbed before health inside `take_damage`; the returned amount includes absorbed overheal |
| `clear_buffs()` | called on death |
Ability def option `"needs_ult": true`: any type can be an ultimate (requires and consumes a full meter).
Ability types (registry): `dash, ground_slam, nova, projectile, shield_wall, charge, heal_beam, rally, leap, team_buff`.
- `leap`: `{forward_speed, up_speed, air_time, radius, damage, knockback}` — jump forward, AoE + knockback on landing; query `leaping()`.
- `team_buff`: `{radius, duration, damage_mult, knockback_immune, overheal}` — buffs self + allies in radius.
- `ground_slam` now impacts only on landing after its own dive. Optional `color` on heal_beam / ground_slam.
Roles: `tank, support, brawler, duelist`. Selectable heroes = top-level `src/heroes/*.json` only
(v0.3: Twin Tails, The Best, Cob); retired defs live in `src/heroes/archive/` (tests only, not scanned).
Optional ability query methods: `channeling()` (heal_beam), `active()` (shield_wall), `charging()` (charge).
Shield walls are StaticBody3D on layer 1: they block movement, hitscan and projectiles of both teams.

Damage kinds (`kind`): `primary` (hitscan), `slam`, `ultimate`, `projectile` (ability projectiles, incl.
splash), `charge` (rush contact), `fall`.

### 2.3 Hero / map listing (approved v0.2, UI request)
`UiCatalog.list_heroes(dir=res://src/heroes) -> [{id,name,role,max_hp,path}]`, `UiCatalog.list_maps() -> [{name,path}]`
(src/ui/catalog.gd, folder scan, malformed files skipped). **Every `.json` in src/heroes and src/maps must be a
playable hero/map** — enforced by `tests/core_playable_sim.gd` (valid def, registered ability types, team 0/1 spawns,
every hero lands at a spawn on every map). Put non-hero data elsewhere.
Main menu: `MainMenu.play_requested(hero_path, map_path)` → main.gd sets `GameConfig.hero_id/map_id` and starts the
match. Any test flag (`--demo --smoke --screenshot --hero --map --net_host --autopilot`) bypasses the menu.
Menu hooks (approved v0.4, UI round 3): `main_menu.add_menu_entry(text, cb) -> Button` adds a button to
`MainMenu.network_slot` (hidden VBox under Play, shown on first entry); `main_menu.add_screen(name, control)`
registers a full-rect screen and `show_screen(name)` switches to it. Core uses them for "Host online" / "Join online"
(screens `net_host` / `net_join` = `NetPanel`, src/core/net/net_panel.gd, emitting `closed` → `show_screen("main")`).
View settings: `Settings.fov` is the base FOV; CameraRig starts from it and UI re-applies it on change; any future
FOV animation (zoom/sprint) must be relative to `Settings.fov`. Audio buses `Master`, `Music`, `SFX`
(res://default_bus_layout.tres, core-owned); `Settings` volumes apply to them by name.

- **Display-only model (UI)**: `HeroModel.create_display(hero_id, team_color = blue) -> Node3D` is the supported way
  to show a hero outside gameplay (hero select preview etc.): the GLB `HeroModel` from "model_scene" when it loads,
  otherwise the primitive "model" parts (built by `HeroModel.build_parts`, the same builder Hero uses). No collision,
  abilities, input, events or Net ids; null for an unknown id. `HeroModel.create_display_def(def, team_color)` does the same from a loaded def (used by the hero-select `HeroPreview`). Do not instantiate `Hero` for previews.

## 3. Damage & health
- Death visibility hook: `hero.keep_body_when_dead` (default false). If true, `_die()` leaves the hero visible
  (collision off, `dead = true`) so heroes can play a death animation on the live model, then sets `visible = false`
  itself. Online, `visible` is in the snapshot, so clients follow the host.
- `hero.take_damage(amount, source: Hero|null, pos: Vector3, kind: String, ability_id := "") -> float applied`.
  `kind` ∈ `primary, slam, ultimate, fall, …`; `ability_id` = the source ability's `id` (hero JSON ability id,
  else its type), `""` for the primary weapon and falls. `hero.aoe(center, radius, dmg, kind, ability_id := "")`.
- Emits `Events.damage_dealt({source, target, amount, pos, src_pos, kind, killed, ability_id, crit})`, then
  `source.on_damage_dealt(amount)` (charges ult 1:1). `src_pos` (Vector3 or null) = the attacker's host-side
  position at hit time; replicated to clients with the event (Net EVENT_SIGNALS), use it for hit direction, then on death
  `Events.killed({killer, victim, kind, ability_id})`. `crit: bool` is always false for now (no crits/headshots
  planned); UI may style it. Online both payloads replicate unchanged to clients (§10). Respawn after 3 s → `Events.respawned(hero)`.
- AoE falloff: `HitMath.aoe_damage` — 100 % at centre to 50 % at the edge.
- `hero.damage_scale` multiplies outgoing damage (bots use 0.3).

## 4. Event bus (`Events` autoload)
`damage_dealt({source, target, amount, pos, src_pos, kind, killed, ability_id, crit})`, `killed({killer, victim, kind, ability_id})`
(`ability_id` "" = primary/fall; `crit` always false for now; see §3), `respawned(hero)`, `healed({source, target, amount, ability_id})` (host/offline, from `hero.heal(amount, source, ability_id)`;
`amount` = HP actually restored; aggregated per target × (source, ability_id) and emitted about every 0.25 s
(`Hero.HEAL_EVENT_INTERVAL`), flushed early on the target's death; replicated reliably), `cover_broken({block_id, pos, map})`
(host/offline; replicated, clients apply it through `MapDestruction`), `ability_ready(hero, slot)` (host/offline: fired when a cooldown runs out while the hero
ticks; NOT on direct resets such as respawn or test hooks; replicated reliably to clients), `ability_used(hero, slot, ability_id)`,
`capture_progress({zone_id, team, progress 0..1, contested, owner})` (≤ 10 Hz, immediate when `contested` flips;
`team` = capturing team, or the owner when nobody is capturing), `capture_completed({zone_id, team, previous})`,
`match_score({mode, scores, target})`, `match_ended({winner_team (-1 = draw), reason ("score"|"forced"), mode, scores, time})`.
These are the **only** capture/match events (the earlier zone_changed/zone_captured/zone_contested names are retired).
Teams are ints; neutral = -1.
UI/FX/audio/network only listen; they never mutate gameplay.

## 5. Bot AI hooks (src/ai)
A bot is a normal `Hero` whose `input_source` is a `BotBrain` — bots get no special powers.
`BotBrain.new(params)`; `difficulty` is applied first, explicit params override it.
| param | default | meaning |
|---|---|---|
| `difficulty` | `"normal"` | `easy`/`normal`/`hard` preset (BotBrain.DIFFICULTY) for the aim params below |
| `spread_deg` | 6 | spawner copies to `hero.extra_spread_deg` |
| `turn_rate` | 4 | rad/s aim turn speed |
| `fire_cone` | 0.15 | rad aim error under which it fires |
| `reaction_time` | 0.35 | s before firing at a newly acquired target |
| `aim_jitter` | 0.05 | rad random aim offset |
| `ability_delay` | 0.6 | mean s before using an ability whose conditions hold |
| `low_hp_frac`, `cover_time` | 0.35, 3 | enter `cover` state below this HP fraction, for this long |
| `sight`, `bounds` | 40, 17 | target range; wander half-size (spawner passes the map's `bounds`) |
| `use_abilities`, `use_navmesh`, `seek_cover` | true | feature switches |
Navmesh: `BotNav` lazily bakes a `BotNavRegion` (NavigationRegion3D)
under the map root from static colliders at first use. Cover = StaticBody3D whose **name contains "cover"**:
MapLoader names every block `<kind>_<index>` (e.g. `cover_08`) and sets meta `kind`; this naming is part of the map contract.
`BotNav.sync_dynamic(map_root)` (called from bot path following, at most once per physics frame per map) rebakes
the navmesh when the set of layer-1 StaticBody3D boxes that are siblings of the map root changes (shield walls);
they become projected obstructions, so bots path around active walls; the navmesh is restored when they expire.
Convention: abilities adding transient world geometry add it as a direct child of the world node
(`hero.get_parent()`), StaticBody3D with BoxShape3D, so bots see it.
Cover detection: meta `kind == "cover"` (fallback: name prefix `cover`). States: `wander`, `chase`, `cover`, `support`.
Param `escort_allies` (true): idle bots escort teammates; support bots (Willow) heal hurt allies.
Ability policy is type-based: `BotBrain.want_ability(type, ctx)` for dash, charge, ground_slam, nova, rally,
shield_wall, projectile, heal_beam, leap, team_buff. Melee awareness (v0.4): for heroes with `primary.type ==
"melee"` BotBrain closes to ~0.6 × `primary.range` and only swings in reach (the old core MeleeCloser shim is
removed); ranged bots keep their ~10 m stand-off. `BotBrain.resolve_difficulty(name) -> Dictionary` is the pure
preset lookup (unknown names → `normal` with a runtime warning).
Stand-off (v0.5, AI round 4): ranged bots hold `standoff` (10 m) using a range-proportional radial term plus a
world-space tangential strafe (`BotBrain.standoff_dir`). When line of sight breaks they reverse the strafe and keep
the stand-off for `LOS_GRACE` (1 s) before pathing in, and remember an out-of-sight target for `TARGET_MEMORY`
(2 s) instead of wandering or switching to a farther enemy. Bench: `godot --headless --path . -s tests/ai_standoff_run.gd -- --n=30`.
Support (v0.6, AI round 5): support bots look for hurt allies within `support_radius` (default 35 m, no line of
sight needed), walk to them on the navmesh and channel the heal beam once in range with line of sight, healing
allies below `heal_below` (0.8 of max HP) and themselves when hurt. Bots only consider heroes in their own World3D
(test SubViewports share the `"heroes"` group), so tests in separate worlds don't interfere.
Cover + peek (v0.7, AI round 6): the `cover` state cycles travel → hide → peek → hide …. Difficulty-preset params:
`peek_time` (easy 1.4 / normal 1.0 / hard 0.7 s), `hide_min`/`hide_max` (1.6–2.4 / 1.0–1.8 / 0.5–1.3 s),
`peek_side_mode` (`same` / `random` / `mixed`), `cover_session` (8 s: leave after 8 s without a successful peek or
16 s in total, then an 8 s cooldown), `opportunistic_cover` (true: ranged bots under 70 % HP use cover within 6 m).
Cover is re-picked when the hiding bot has been seen for > 0.4 s (flank / shield wall) or its block node is freed;
with no cover available the bot fights. Helpers: `BotNav.peek_point()`, `BotNav.best_cover_block()`; cover block
dictionaries carry `node`. Input/ability interface unchanged.
Team play (v0.7, AI round 7): `src/ai/bot_team.gd` (`BotTeam`) keeps a per world+team board of enemies seen by
teammates (0.5 s), a shared focus = lowest HP fraction (`BotTeam.focus`) and zone owners from the bus (host only).
BotBrain param `team_play` (true): bots switch to the team focus when they see it and it is at most 8 m (melee 3 m)
farther than their own nearest target; idle bots regroup at a rally point (tank → zone centre; others → the tank,
else zone, else team centre); ranged bots drift back toward the rally point beyond 8 m while fighting; a hero with
`role: "tank"` holds the first zone its team doesn't own (fights from inside it, skips opportunistic cover there;
low-HP cover still applies). FFA (no zones): focus + grouping only. No core hooks. **Cob keeps `role: "tank"`**
(the tank behaviour keys off it; heroes must keep that role on tank heroes).
Smoke STATS: `bot_dmg` = damage to the player; `team_dmg_taken` = damage dealt by team 1 to any team-0 hero. On
maps with allies the smoke gate uses `team_dmg_taken` (allies soak fire) instead of `bot_dmg`. Team-0 bots are the player's allies (never target team 0).
Core sets difficulty from `GameConfig.bot_difficulty` (`-- --difficulty=` or `--bots=`) and scales bot damage
by `GameConfig.difficulty().damage_scale`. Heroes are found via group `"heroes"` (`team`, `dead`, `eye_position()`).

## 6. Map format (src/maps/*.json)
```json
{ "name", "bounds": half-size for wandering,
  "spawns": {"<team>": [[x,y,z], ...]},
  "blocks": [{"kind":"floor|wall|cover|ramp|platform","pos":[x,y,z],"size":[x,y,z],
              "rot_deg":[x,y,z]?, "color":"#hex", "grid":bool?}] }
```
`MapLoader.build(path) -> Node3D` with metas `spawns` (Dictionary int → Array[Vector3]),
`bounds`, `map_name`. Every block is a StaticBody3D box (ramps are rotated boxes), node name = its `kind`.

Optional keys (approved v0.2, maps request):
- `"zones": [{"id","kind":"capture","pos":[x,y,z],"size":[x,y,z]}]` → meta `zones` (Array of {id, kind, pos: Vector3, size: Vector3}). Data only for now.
- `"spawn_rooms": {"<team>": {"pos","size"}}` → meta `spawn_rooms` (Dictionary int → AABB).
- `SpawnPicker.pick_for(hero, candidates, default_index) -> Vector3` (src/maps/spawn_picker.gd): spawn no living
  enemy can see (layer-1 ray), else fewest watchers / farthest. **Core calls it 0.1 s before every respawn**
  (main.gd `_schedule_respawn_pick`) and sets `hero.spawn_point`.
- `MapGrid.from_def(def)` walkability grid + `flood()`.
Capture zones (approved v0.2 round 2): zone keys `capture_time` (s for one player, default 8),
`player_scale` (rate multiplier by player count, last value = cap, default [1, 1.5, 2]), `decay_rate`
(progress/s lost when empty, default 0.1), `revert_rate` (default 1); `zones` meta entries carry them.
Rules: ≥ 2 teams inside = contested, progress pauses; a lone team first reverts another team's partial
progress; an owner on its zone reverts enemy progress; an empty zone decays; progress 1.0 sets the owner and
resets progress. Core creates one `CaptureZone` node per zone (`CaptureZone.from_map(map)`) and forwards
its signals through `ZoneBridge` (src/core/zone_bridge.gd) to `Events.capture_progress` / `capture_completed`
(payloads in §4). CaptureZone's own signals (`state_changed`, `captured`, `contested_changed`) are maps-internal;
UI and AI must listen to the bus only. `zone_id` = `zones[].id` in the map JSON.
Map selection: `GameConfig.map_id` / `-- --map=ID`; smoke runs on every map JSON.
Visual keys (approved v0.4, maps round 3; no gameplay effect, collision unchanged):
- `"theme"`: `sky_top, sky_horizon, ground_horizon, ground_bottom` (#hex), `sun_rot` [x,y,z], `sun_color`,
  `sun_energy`, `ambient_energy`, `fog_density` (enables fog), `fog_color`, `fog_sky_affect`. Defaults = v0.1 look.
- `"materials"`: name → `{color, roughness?, metallic?, pattern?: grid|tiles|planks|bricks|stripes, pattern_scale?,
  tint?, emission?, emission_energy?, alpha?}`; patterns are fixed procedural 16×16 textures (no RNG).
- block `"mat"`: palette name (falls back to `color`/`grid` when missing).
- `"props"`: `[{shape: box|cylinder|cone|sphere, pos, size | radius+height, rot_deg?, mat|color, no_shadow?}]`
  → MeshInstance3D children of a `Props` Node3D under the map root, **no collision**. Props are stored in the
  JSON, so host and client build identical maps; nothing about maps is replicated.
Toon restyle (v0.7, maps queue 1; visual only, collision unchanged): theme `toon` (bool: palette materials use
`src/maps/toon/map_toon.gdshader`, flat 2-tone with sun shadows, no ambient/specular), `tonemap` (`"filmic"` default |
`"linear"`; map scenes use linear so unshaded toon heroes render at their authored colours), `outline_width` (m; > 0
enables merged inverted-hull outlines: one `Outlines` MeshInstance3D under the map root, front-culled, unshaded, no
shadow/collision, meta `hull_count`), `outline_color`. Per material: `shade` (shadow tone multiplier, default 0.74)
and `outline` (false = no hull, e.g. floors/decals); per block/prop `outline: false`. Low quality keeps block hulls and
drops prop hulls. `MapLoader.mat_color(mat)` returns the base colour of either material type.
Destructible cover (if ever added): it must stay a solid StaticBody3D block with meta `kind = "cover"` (name prefix
`cover_`), and breaking it frees the node (`queue_free`); bots then re-pick cover automatically (§5). Online, a
destructible block must be removed on clients too (replicate the break; maps are otherwise not replicated, §10).
Destructible cover (v0.8, maps queue 2): a `cover` block with `"hp": N` becomes a `DestructibleCover`
(StaticBody3D, meta kind `cover`, name `cover_NN`, group `destructible`, own outline hull). `block_id` = index in the
JSON `blocks` array (identical everywhere). Manager: map-root child `Destruction` (`MapDestruction`): host/offline
decides — `cover.take_damage(amount, source, pos, kind, ability_id)` (same signature as Hero; 0 on clients), at 0 HP
emits `Events.cover_broken` and frees the node. Core routes hitscan, melee arcs, projectile direct hits + splash and
`Hero.aoe()` to the `destructible` group (`Hero.damage_destructibles(...)`, HitMath falloff; no ult charge). Clients:
`Destruction.apply_break(block_id)` via the replicated event; late join: welcome info `broken_cover` =
`Destruction.broken_ids()` on the host → `Destruction.apply_broken(ids)` right after the client builds the map.
Build options (approved v0.4, maps round 4): `MapLoader.build(path, opts := {})`; `opts.low_quality` overrides
`MapLoader.low_quality_flag()` (= `Settings.low_quality` OR `GameConfig.low_quality`). Low quality skips `Props`
and fog and disables sun shadows; collision is identical. Props are batched: `Props` children are one merged
MeshInstance3D per (material, shadow) group, with meta `prop_count` (source prop count) on `Props`.
Extra theme keys: `shadow_mode` (DirectionalLight3D shadow mode, default PSSM 2 splits) and `shadow_distance`
(m, default 60). Floor/ground blocks don't cast shadows. After the merge pass fps went ~20 → ~25 (software GL).
Perf note: arena02 under Xvfb software GL dropped from ~18 to ~15 fps with fog + ~170 props; a low-quality
toggle (skip Props/fog) can come later via UI.

## 8. Match config (`GameConfig` autoload, src/core/game_config.gd)
| member | meaning |
|---|---|
| `hero_id: String` | player hero (default `DEFAULT_HERO` = `twin_tails`); set with `set_hero(id) -> bool` (rejects unknown ids) |
| `map_id: String` | map file id in src/maps (default `arena01`) |
| `bot_difficulty: String` | `easy` / `normal` / `hard` → `difficulty()` = {spread_deg, turn_rate, damage_scale} |
| `enemy_count: int` | team-1 bots, default 3 (`-- --enemies=N`); `bot_count` is an alias |
| `ally_count: int` | team-0 bots, default -1 = map default (`-- --allies=N`) |
| `allies_for(map) -> int` | allies actually spawned: 0 on maps without team-0 `spawn_rooms` (FFA, arena01); otherwise `ally_count`, default **2** (3v3 with the player on arena02 Control) |
| `hero_ids() -> Array` | every `src/heroes/*.json` id, sorted (hero select lists this) |
| `hero_path(id)`, `map_path()` | resource paths |
| signal `changed` | emitted by `set_hero` |
A future hero-select UI sets these, then (re)loads `res://src/main.tscn`. Bots use a mixed roster:
enemy *i* gets `hero_ids()[i % n]`; ally *i* gets the (i+1)-th hero after the player's in `hero_ids()`.

### 8.1 In-match controls (main.gd composition root; UI adapter src/ui/match_control.gd)
`const HERO_SWAP_DELAY := 3.0` (main.gd). The host (or offline game) runs every timer; UI only displays `delay`.
- Queries (every side): `match_bot_counts() -> {0: int, 1: int}` (clients: last value from the host, also in the
  welcome), `local_team() -> int`, `local_net_id() -> int`.
- `set_bot_count(team, n) -> bool`: offline/host only (clients: false). team in {0,1}, n clamped 0..5. Spawns bots
  live with the match roster at the team's next spawn slot, or despawns newest first; online through
  `Net.broadcast_spawn` / despawn, plus `_bot_counts`. Emits `bot_counts_changed(counts)`.
- `request_hero_change(hero_id) -> bool`, `request_team_change(team) -> bool`: offline/host validate at once (true =
  accepted); clients send the request and return true once sent. Host validation: requester owns a hero, no change
  already pending, match not ended; hero: known id and different from the current one; team: 0/1, different
  from the current one, and no stacking (humans on the target team must stay below the other team before the move).
  Rejects: `hero_swap_cancelled(net_id, reason)` to the requester only. Accept: `hero_swap_started(net_id, hero_id,
  delay)` on every peer; after the delay the old hero is replaced by a fresh one (same net id, owner, input
  stream and scoreboard row, full HP, `SpawnPicker.pick_for` at the team spawn), then `hero_swap_finished(net_id,
  hero_id)`. Dying during the delay keeps it pending; the respawn is the new hero (at the normal respawn time).
  The match ending cancels it ("match ended"). Team change: same flow with the current hero; one bot moves from the
  target team to the old team (team sizes kept), then `team_changed(net_id, team)`. Offline hero swaps also call
  `GameConfig.set_hero` so "Play again" keeps the new hero. The local hero is replaced: read `main.player` again (HUD,
  kill feed and scoreboard are rebound by core).
- Signals on main.gd: `hero_swap_started`, `hero_swap_finished`, `hero_swap_cancelled`, `bot_counts_changed`, `team_changed`.

## 9. Match modes & win condition (core: src/core/match_rules.gd, node "MatchRules" under main)
| mode | when | rule |
|---|---|---|
| `control` | map has ≥ 1 capture zone (arena02) | each zone owned by a team adds **1 % per second** to that team; first to **100 %** wins |
| `ffa` | no zones (arena01) | deathmatch vs bots, no end yet |
UI contract (scoreboard / match-end screen): listen to `Events.match_score` (~1 Hz, `scores` = {team: percent},
`target` = 100) and `Events.match_ended` (once; `winner_team` int, -1 = draw; `reason`). Two teams reaching 100 %
on the same tick = draw. `MatchRules.force_end(reason)` ends immediately (leader wins, tie = draw); smoke uses
`-- --force_end=S`. Match-end screen buttons: `play_again` → main.gd reloads main.tscn straight into a match with
the same GameConfig (`GameConfig.skip_menu_once`); `main_menu` → reload into the main menu. Live values: `MatchRules.mode, scores, ended,
winner, elapsed`. After `match_ended` core pauses the tree (outside test mode), sets `Actions.gameplay_enabled =
false` and frees the cursor; the end screen must use `process_mode = ALWAYS` and offer "back to menu"
(reload `res://src/main.tscn`).

## 7. Command line (testing)
`-- --hero=ID --map=ID --bots=easy|normal|hard` (GameConfig); `--smoke=S` (autopilot S game-seconds, exit 1 on fail), `--demo=S`, `--screenshot=PATH --delay=S [--menu]`.

Pause overlay (v0.7, UI queue 3): `PauseMenu` (Esc) emits `leave_requested`; main.gd connects it to
`_restart(false)` in both the offline/host and the online-client setup, which returns to the main menu (closing Net
when online). `resumed` is emitted on close. Online the overlay never pauses the tree.

## 10. Networking (v0.4, src/core/net/, autoload `Net`)
Godot high-level multiplayer over ENet, **host-authoritative**. Default port `Net.DEFAULT_PORT` = 24565/UDP,
up to `Net.MAX_HUMANS` = 6 humans; bots fill the other GameConfig slots (a joining human replaces one bot of the
team with fewer humans). Modes: `OFFLINE` (single player, unchanged), `HOST`, `CLIENT`.
- **Mode queries**: `Net.is_online()` (HOST or CLIENT), `Net.is_host()`, `Net.is_client()`, `Net.is_authority()`
  (= not CLIENT; OFFLINE or HOST). UI uses `is_online()` (e.g. the pause overlay never pauses the tree online).
- **Link status**: `Net.ping_ms() -> int` (client round-trip ms, smoothed, 1 ping/s; -1 until measured and on
  host/offline), `Net.last_packet_age() -> float` (client: s since the last packet from the host; 0 on host/offline).
  Signal `Net.disconnected(reason: String)` (client: "could not connect", "host closed the connection", "server full").
  In a match the HUD's `ConnectionLostScreen` stays up; it returns to the menu through `hud.conn_lost.return_requested`
  (main.gd → `_restart(false)`) or the pause overlay's `leave_requested`. Before a match the Join screen shows it.
- **Authority**: `Net.is_authority()` (= not CLIENT). The single gate is `Hero.take_damage` (returns 0 on a
  client). Clients build no MatchRules, no zone wiring, no bot brains and never pick spawns.
- **Hero roles** `hero.net_role`: `auth` (full sim, host/offline), `predicted` (client's own hero: look +
  movement only, then reconciled), `puppet` (snapshot-driven, no physics). `hero.net_id` = registry id.
- **Input** (client → host, every physics tick, unreliable_ordered): `[seq, view_tick, yaw, pitch, move: Vector2,
  fire, counters[jump, reload, a1, a2, ult]]`. Yaw/pitch absolute; buttons as cumulative press counters (no lost or
  doubled edges). Host side: `RemoteInput` (queue ≤ 8, pitch/move clamped); client side: `ClientInput(inner)`.
- **Snapshots** (host → clients, 20 Hz = every `SNAP_EVERY` = 3 ticks, unreliable_ordered):
  heroes `[id, pos, vel, yaw, pitch, hp, dead, visible, ammo, reloading, ult, cds×3, overheal, respawn_left,
  acked_seq, team, combo_step, dash_time, heal_target_id]` (the last three are visual only: remote finisher/dash animation and the
  Encore Beam target, `heal_target_id` = net id of the healed ally, -1 for none or self → `hero.heal_target_id` on clients), props `[id, pos, rot_y]` for every node in group `net_props`
  (projectile shots `shot`, shield walls `wall`; walls are solid StaticBody3D on clients too).
  Abilities adding networked transient geometry must add the node to `net_props` with metas `net_kind`,
  `net_size`, `net_color` and optionally `net_visual`.
- **Networked props (R9 visual hook)**: the first time the host sees a `net_props` node it sends a reliable
  `_s_prop_spawn({id, kind, size, color, visual})` (late joiners get every live one in the welcome `props`);
  snapshots then carry only the transform, and clients skip a prop until its spawn info arrived.
  `visual` = meta `net_visual` (Projectile / ShieldWall copy the ability def key `"visual"`), a res:// path to a
  PackedScene (instanced) or a script with `static func build_prop(kind, size, color) -> Node3D`. Clients build it
  with `Net.make_prop(kind, size, color, visual)`; walls keep a collision box of `size` around the visual; empty or
  unloadable visual → plain sphere/box. Visual only: the host's own gameplay node is unchanged.
- **Client rendering**: remote heroes are interpolated `INTERP_DELAY` = 0.1 s behind the estimated server
  Respawn: the client drops its pending inputs and ignores acks for inputs sent before death (host also clears the
  queued inputs of a respawned remote hero), so the death-spot → spawn snap is not counted as a correction (`Net.teleports`).
  clock; own hero is predicted and, when the predicted position at `acked_seq` differs by > 0.15 m, snapped to
  the server state and the pending inputs are replayed with `Motion.step_velocity` + `move_and_slide`.
- **Events**: every `Events` signal fires on the host only and is replicated (`reliable`, except
  `capture_progress` / `match_score` unreliable). Hero references are encoded as `{"__h": net_id}`.
  UI/AI keep listening to the bus exactly as offline. `Fx.tracer` / `Fx.ring` called on the host replay on clients.
- **Lag compensation**: the host keeps `HISTORY` = 60 ticks of hero positions; hitscan and melee from a remote
  shooter run with other heroes rewound to the shooter's `view_tick` (`Net.rewind_for` / `restore`).
- **Spread RNG**: online, `hero._rng` is seeded per shot with `hash([net_id, Net.tick, ammo])`.
- **Spawn / despawn**: `_s_welcome({map_id, you, tick, heroes})`, `_s_spawn(hero_info)`, `_s_despawn(id)`.
  Broadcasts go only to peers that completed hello/welcome.
- Smoke (`--smoke`) seeds the global RNG, hero spread and BotBrain RNGs from `--seed=N` (default 4242); it
  passes on damage dealt + taken, match_ended and every ability slot used (kills reported, not required).
- `Net.offline` (true under `--headless` or with `-- --net_offline`): skips the api.ipify.org public-IP lookup;
  `fetch_public_ip()` then reports `""` on the next frame, so the Host screen is testable.
- Command line: `--net_host=PORT`, `--net_join=IP:PORT`, `--autopilot` (bot-driven player), `--net_test=S`
  (prints `NETDUMP` JSON, quits). `tools/net_test.sh` (build.sh step) runs headless host + client on localhost.
- Not yet: rejoin/host migration, bot re-fill when a human leaves, ability-movement prediction (dash/leap are
  corrected by reconciliation), NAT traversal / relay.

- **In-match control RPCs** (§8.1 logic lives in main.gd): client -> host `_rq_hero(hero_id)`, `_rq_team(team)`
  (`Net.request_hero` / `request_team`); host -> requester `_swap_cancelled(net_id, reason)`; host -> all
  `_swap_started(net_id, hero_id, delay)`, `_swap_finished(net_id, hero_id)`, `_team_changed(net_id, team)`,
  `_bot_counts(counts)`. A swap is `_s_despawn(id)` + `_s_spawn(info)` with the same id (`Net.send_despawn_id`);
  `Net.hero_despawning(net_id, node)` fires on clients just before the node is dropped. Welcome info has `bot_counts`.
  tools/net_test.sh swaps the client's hero mid-match (`--net_swap=S --net_swap_hero=ID`) and checks both sides.

## 11. Player settings (`Settings` autoload, src/ui/settings.gd, owner UI)
Persisted by UI (user://settings.cfg). Read-only for everything outside UI; only UI writes them.
- `Settings.fov` — base camera FOV (see §2.3).
- `Settings.volumes` / `volume(bus)` — Master/Music/SFX.
- `Settings.low_quality: bool` + signal `Settings.low_quality_changed(on: bool)` (emitted only on change);
  only UI sets it, via `Settings.set_low_quality(on)`. Maps/FX read it (maps apply it on the next map build).
  Perf/capture runs use `-- --low_quality` → `GameConfig.low_quality` (CLI only, not persisted); MapLoader ORs both.
