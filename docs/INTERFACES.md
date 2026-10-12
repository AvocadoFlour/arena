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
Ability types (registry): `dash, ground_slam, nova, projectile, shield_wall, charge, heal_beam, rally`.
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
match. Any test flag (`--demo --smoke --screenshot --hero --map`) bypasses the menu.

## 3. Damage & health
- `hero.take_damage(amount, source: Hero|null, pos: Vector3, kind: String) -> float applied`.
  `kind` ∈ `primary, slam, ultimate, fall, …`.
- Emits `Events.damage_dealt({source, target, amount, pos, kind, killed})`, then
  `source.on_damage_dealt(amount)` (charges ult 1:1), then on death
  `Events.killed({killer, victim, kind})`. Respawn after 3 s → `Events.respawned(hero)`.
- AoE falloff: `HitMath.aoe_damage` — 100 % at centre to 50 % at the edge.
- `hero.damage_scale` multiplies outgoing damage (bots use 0.3).

## 4. Event bus (`Events` autoload)
`damage_dealt(ev)`, `killed(ev)`, `respawned(hero)`, `ability_used(hero, slot, ability_id)`,
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
States: `wander`, `chase`, `cover`. Navmesh: `BotNav` lazily bakes a `BotNavRegion` (NavigationRegion3D)
under the map root from static colliders at first use. Cover = StaticBody3D whose **name contains "cover"**:
MapLoader names every block `<kind>_<index>` (e.g. `cover_08`) and sets meta `kind`; this naming is part of the map contract.
Dynamic shield walls are not in the navmesh: bots are blocked by them until they expire (tested, no stuck state).
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

## 8. Match config (`GameConfig` autoload, src/core/game_config.gd)
| member | meaning |
|---|---|
| `hero_id: String` | player hero (default `kestrel`); set with `set_hero(id) -> bool` (rejects unknown ids) |
| `map_id: String` | map file id in src/maps (default `arena01`) |
| `bot_difficulty: String` | `easy` / `normal` / `hard` → `difficulty()` = {spread_deg, turn_rate, damage_scale} |
| `bot_count: int` | default 3 |
| `hero_ids() -> Array` | every `src/heroes/*.json` id, sorted (hero select lists this) |
| `hero_path(id)`, `map_path()` | resource paths |
| signal `changed` | emitted by `set_hero` |
A future hero-select UI sets these, then (re)loads `res://src/main.tscn`. Bots use a mixed roster:
bot *i* gets `hero_ids()[i % n]`.

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
