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
`move_forward/back/left/right, jump, fire, ability1, ability2, ultimate, reload, pause`.
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

## 3. Damage & health
- `hero.take_damage(amount, source: Hero|null, pos: Vector3, kind: String) -> float applied`.
  `kind` ∈ `primary, slam, ultimate, fall, …`.
- Emits `Events.damage_dealt({source, target, amount, pos, kind, killed})`, then
  `source.on_damage_dealt(amount)` (charges ult 1:1), then on death
  `Events.killed({killer, victim, kind})`. Respawn after 3 s → `Events.respawned(hero)`.
- AoE falloff: `HitMath.aoe_damage` — 100 % at centre to 50 % at the edge.
- `hero.damage_scale` multiplies outgoing damage (bots use 0.3).

## 4. Event bus (`Events` autoload)
`damage_dealt(ev)`, `killed(ev)`, `respawned(hero)`, `ability_used(hero, slot, ability_id)`.
UI/FX/audio/network only listen; they never mutate gameplay.

## 5. Bot AI hooks (src/ai)
A bot is a normal `Hero` whose `input_source` is a `BotBrain` — bots get no special powers.
`BotBrain.new(params)` params: `spread_deg, turn_rate, sight, fire_cone, bounds, use_abilities`.
Spawner sets `hero.extra_spread_deg = brain.spread_deg` (inaccuracy). States: `wander`, `chase`.
Heroes are found via group `"heroes"` (`team`, `dead`, `eye_position()`).

## 6. Map format (src/maps/*.json)
```json
{ "name", "bounds": half-size for wandering,
  "spawns": {"<team>": [[x,y,z], ...]},
  "blocks": [{"kind":"floor|wall|cover|ramp|platform","pos":[x,y,z],"size":[x,y,z],
              "rot_deg":[x,y,z]?, "color":"#hex", "grid":bool?}] }
```
`MapLoader.build(path) -> Node3D` with metas `spawns` (Dictionary int → Array[Vector3]),
`bounds`, `map_name`. Every block is a StaticBody3D box (ramps are rotated boxes).

## 7. Command line (testing)
`-- --smoke=S` (autopilot S game-seconds, exit 1 on fail), `--demo=S`, `--screenshot=PATH --delay=S [--menu]`.
