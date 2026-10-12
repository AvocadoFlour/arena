class_name BotBrain
extends RefCounted
## Bot AI as an input source: poll(hero) -> InputFrame (INTERFACES.md section 5).
## States: wander -> chase (enemy visible) -> cover (low health). Movement follows a navmesh
## path (BotNav) with direct steering as fallback. Inaccuracy: hero.extra_spread_deg (set by the
## spawner from spread_deg) plus difficulty-dependent aim jitter and reaction delay.

const DIFFICULTY := {
    "easy":   {"spread_deg": 10.0, "turn_rate": 2.5, "fire_cone": 0.20, "reaction_time": 0.60, "aim_jitter": 0.12, "ability_delay": 1.2, "low_hp_frac": 0.20, "cover_time": 2.0},
    "normal": {"spread_deg": 6.0,  "turn_rate": 4.0, "fire_cone": 0.15, "reaction_time": 0.35, "aim_jitter": 0.05, "ability_delay": 0.6, "low_hp_frac": 0.35, "cover_time": 3.0},
    "hard":   {"spread_deg": 3.0,  "turn_rate": 7.0, "fire_cone": 0.10, "reaction_time": 0.18, "aim_jitter": 0.015, "ability_delay": 0.2, "low_hp_frac": 0.40, "cover_time": 3.5},
}
const ULT_RANGE := 8.0        ## Nova radius is 10; stay inside with margin
const SLAM_RANGE := 4.5       ## grounded slam radius is 5
const DASH_MIN_DIST := 11.0

var difficulty := "normal"
var spread_deg := 6.0         ## applied by the spawner to hero.extra_spread_deg
var turn_rate := 4.0          ## rad/s
var sight := 40.0
var fire_cone := 0.15         ## rad: fire when aim error below this
var bounds := 17.0            ## wander area half-size
var use_abilities := true     ## dash, slam, ultimate
var use_navmesh := true
var seek_cover := true
var reaction_time := 0.35     ## s before firing at a newly acquired target
var aim_jitter := 0.05        ## rad, random aim offset refreshed twice a second
var ability_delay := 0.6      ## mean s before an ability whose conditions hold is used
var low_hp_frac := 0.35
var cover_time := 3.0
var state := "wander"
var target = null
var nav_used := false         ## true once a navmesh path has been followed (tests/debug)

var _rng := RandomNumberGenerator.new()
var _wander := Vector3.ZERO
var _wander_left := 0.0
var _strafe := 1.0
var _strafe_left := 0.0
var _think := 0.0
var _react_left := 0.0
var _jitter := Vector2.ZERO
var _jitter_left := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF
var _repath := 0.0
var _cover = null             ## Vector3 or null
var _cover_left := 0.0
var _cover_cd := 0.0
var _map_root: Node3D = null

func _init(p: Dictionary = {}) -> void:
    _rng.randomize()
    set_difficulty(String(p.get("difficulty", "normal")))
    for k in p:
        if k != "difficulty":
            set(k, p[k])

func set_difficulty(d: String) -> void:
    if not DIFFICULTY.has(d):
        push_warning("BotBrain: unknown difficulty '%s', using normal" % d)
        d = "normal"
    difficulty = d
    for k in DIFFICULTY[d]:
        set(k, DIFFICULTY[d][k])

func poll(h) -> InputFrame:
    var f := InputFrame.new()
    var dt := 1.0 / float(Engine.physics_ticks_per_second)
    if use_navmesh and _map_root == null:
        _map_root = BotNav.find_map_root(h)
        if _map_root:
            BotNav.ensure_region(_map_root)
    _think -= dt
    _cover_cd -= dt
    _react_left -= dt
    _jitter_left -= dt
    if _jitter_left <= 0.0:
        _jitter_left = 0.5
        _jitter = Vector2(_rng.randf_range(-aim_jitter, aim_jitter), _rng.randf_range(-aim_jitter, aim_jitter) * 0.5)
    if target and (not is_instance_valid(target) or target.dead):
        target = null
    if _think <= 0.0:
        _think = 0.2
        var t = _find_target(h)
        if t != target and t != null:
            _react_left = reaction_time
        target = t
    var low: bool = h.health.hp < h.health.max_hp * low_hp_frac
    if target and seek_cover and low and _cover_cd <= 0.0 and state != "cover":
        _cover = BotNav.best_cover(BotNav.cover_blocks(_map_root), h.global_position, target.global_position)
        if _cover != null:
            state = "cover"
            _cover_left = cover_time + 4.0   # travel budget + hiding time
    if state == "cover":
        _do_cover(h, f, dt)
    elif target:
        _do_chase(h, f, dt, low)
    else:
        _do_wander(h, f, dt)
    if h.is_on_floor() and f.move.length() > 0.1 and Vector2(h.velocity.x, h.velocity.z).length() < 1.0 and _rng.randf() < 0.1:
        f.jump = true
    if h.weapon.ammo == 0:
        f.reload = true
    return f

func _do_chase(h, f: InputFrame, dt: float, low: bool) -> void:
    state = "chase"
    var to: Vector3 = (target.global_position + Vector3(0, 1.1, 0)) - h.eye_position()
    var err := _aim(h, f, to, dt, true)
    var dist := to.length()
    _strafe_left -= dt
    if _strafe_left <= 0.0:
        _strafe = -1.0 if _rng.randf() < 0.5 else 1.0
        _strafe_left = _rng.randf_range(0.8, 2.0)
    var slam_ready: bool = use_abilities and _ab_ready(h, "ability2")
    var keep := 3.0 if slam_ready and not low else 10.0   # close in to use the slam
    var los: bool = _visible(h, target)
    if dist > keep + 2.0 or not los:
        f.move = _follow(h, target.global_position)
    else:
        var fwd := 1.0 if dist > keep else (-0.6 if dist < minf(5.0, keep - 1.0) else 0.0)
        f.move = Vector2(_strafe * 0.7, fwd).limit_length(1.0)
    f.fire = los and err < fire_cone and _react_left <= 0.0
    if use_abilities:
        var ctx := {
            "dist": dist, "flat_dist": Vector2(to.x, to.z).length(), "on_floor": h.is_on_floor(),
            "height_above": h.global_position.y - target.global_position.y, "los": los, "low_hp": low,
            "dash_ready": _ab_ready(h, "ability1"), "slam_ready": slam_ready,
            "ult_ready": _ult_ready(h), "ult_targets": _enemies_within(h, ULT_RANGE),
            "moving": f.move.length() > 0.5, "fleeing": false,
        }
        _apply_abilities(f, decide_abilities(ctx), dt)

func _do_cover(h, f: InputFrame, dt: float) -> void:
    _cover_left -= dt
    var cp: Vector3 = _cover
    var flat := Vector2(cp.x - h.global_position.x, cp.z - h.global_position.z).length()
    var threat = target
    if threat:
        var to: Vector3 = (threat.global_position + Vector3(0, 1.1, 0)) - h.eye_position()
        _aim(h, f, to, dt, true)
    if flat > 0.7:
        f.move = _follow(h, cp)
        if threat == null:
            _aim(h, f, _move_world(h, f.move), dt, false)
        if use_abilities and flat > 5.0:
            var ctx := {"dist": 99.0, "flat_dist": 99.0, "on_floor": h.is_on_floor(), "height_above": 0.0,
                "los": false, "low_hp": true, "dash_ready": _ab_ready(h, "ability1"), "slam_ready": false,
                "ult_ready": _ult_ready(h), "ult_targets": _enemies_within(h, ULT_RANGE),
                "moving": f.move.length() > 0.5, "fleeing": true}
            _apply_abilities(f, decide_abilities(ctx), dt)
    else:
        f.move = Vector2.ZERO
        _cover_left = minf(_cover_left, cover_time)
        if h.weapon.ammo < h.weapon.mag_size:
            f.reload = true
    if _cover_left <= 0.0:
        state = "chase" if target else "wander"
        _cover = null
        _cover_cd = 8.0   # peek out and fight before hiding again

func _do_wander(h, f: InputFrame, dt: float) -> void:
    state = "wander"
    _wander_left -= dt
    var flat := Vector3(_wander.x - h.global_position.x, 0, _wander.z - h.global_position.z)
    if _wander_left <= 0.0 or flat.length() < 1.5:
        _wander = Vector3(_rng.randf_range(-bounds, bounds), 0, _rng.randf_range(-bounds, bounds))
        _wander_left = _rng.randf_range(3.0, 6.0)
    f.move = _follow(h, _wander)
    var dir := _move_world(h, f.move)
    dir.y = -h.pitch * 3.0
    _aim(h, f, dir, dt, false)

## Pure ability policy (unit-tested). Returns {ability1, ability2, ultimate} wishes.
static func decide_abilities(c: Dictionary) -> Dictionary:
    var out := {"ability1": false, "ability2": false, "ultimate": false}
    # Ultimate: only when an enemy is well inside the burst radius.
    out.ultimate = c.ult_ready and int(c.ult_targets) >= 1 and float(c.dist) < ULT_RANGE
    # Slam: grounded shockwave in range, or dive onto an enemy below us.
    if c.slam_ready and not c.get("fleeing", false):
        if c.on_floor and float(c.dist) < SLAM_RANGE:
            out.ability2 = true
        elif not c.on_floor and float(c.height_above) > 1.0 and float(c.flat_dist) < 5.0:
            out.ability2 = true
    # Dash: escape to cover, or close a long gap on a visible enemy (never while hurt).
    if c.dash_ready and c.moving:
        if c.get("fleeing", false):
            out.ability1 = true
        elif c.los and not c.low_hp and float(c.dist) > DASH_MIN_DIST:
            out.ability1 = true
    return out

func _apply_abilities(f: InputFrame, want: Dictionary, dt: float) -> void:
    # Each wish fires with a per-tick chance -> mean delay `ability_delay` (difficulty).
    var p := 1.0 if ability_delay <= 0.0 else clampf(dt / ability_delay, 0.0, 1.0)
    for k in want:
        if want[k] and _rng.randf() < p:
            f.set(k, true)

func _ab_ready(h, slot: String) -> bool:
    return h.abilities.has(slot) and h.abilities[slot].can_activate()

func _ult_ready(h) -> bool:
    return h.abilities.has("ultimate") and h.abilities["ultimate"].can_activate()

func _enemies_within(h, r: float) -> int:
    var n := 0
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o != h and not o.dead and o.team != h.team and h.global_position.distance_to(o.global_position) < r:
            n += 1
    return n

## Move input toward `goal` along the navmesh path (direct line if no path).
func _follow(h, goal: Vector3) -> Vector2:
    var pos: Vector3 = h.global_position
    _repath -= 1.0 / float(Engine.physics_ticks_per_second)
    if use_navmesh and (_repath <= 0.0 or goal.distance_to(_path_goal) > 1.5):
        _repath = 0.4
        _path_goal = goal
        _path = BotNav.path(h, goal)
        _path_i = 0
        if _path.is_empty():
            _repath = 0.1   # nav map not synced yet / off-mesh: retry soon
    var wp := goal
    if use_navmesh and _path.size() > 0:
        while _path_i < _path.size() - 1 and Vector2(_path[_path_i].x - pos.x, _path[_path_i].z - pos.z).length() < 0.6:
            _path_i += 1
        wp = _path[_path_i]
        nav_used = true
    return world_to_move(h.global_transform.basis, Vector3(wp.x - pos.x, 0, wp.z - pos.z))

## World-space direction -> InputFrame.move for a hero with basis `b` (pure; unit-tested).
static func world_to_move(b: Basis, dir: Vector3) -> Vector2:
    dir.y = 0.0
    if dir.length() < 0.05:
        return Vector2.ZERO
    var l := b.inverse() * dir.normalized()
    return Vector2(l.x, -l.z).limit_length(1.0)

func _move_world(h, mv: Vector2) -> Vector3:
    if mv.length() < 0.01:
        return h.look_dir() * Vector3(1, 0, 1)
    return h.global_transform.basis * Vector3(mv.x, 0, -mv.y)

## Turns toward `to` (rate-limited, plus aim jitter when `jitter`). Returns remaining aim error (rad).
func _aim(h, f: InputFrame, to: Vector3, dt: float, jitter: bool) -> float:
    var want_yaw := atan2(-to.x, -to.z)
    var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
    if jitter:
        want_yaw += _jitter.x
        want_pitch += _jitter.y
    var dy := wrapf(want_yaw - h.yaw, -PI, PI)
    var dp: float = want_pitch - h.pitch
    var lim := turn_rate * dt
    f.look = Vector2(clampf(dy, -lim, lim), clampf(dp, -lim, lim))
    return Vector2(dy - f.look.x, dp - f.look.y).length()

func _visible(h, o) -> bool:
    var q := PhysicsRayQueryParameters3D.create(h.eye_position(), o.global_position + Vector3(0, 1.1, 0))
    q.exclude = [h.get_rid()]
    var hit: Dictionary = h.get_world_3d().direct_space_state.intersect_ray(q)
    return hit.is_empty() or hit.collider == o

func _find_target(h):
    var best = null
    var best_d := sight
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o == h or o.dead or o.team == h.team:
            continue
        var d: float = h.global_position.distance_to(o.global_position)
        if d < best_d and _visible(h, o):
            best = o
            best_d = d
    return best
