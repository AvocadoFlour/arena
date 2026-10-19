extends Node3D
## Out-of-bounds integration sim (maps queue 3): real Jolt CharacterBody3D capsules (Tomo-sized, the slimmest/
## tallest hero) driven by Motion.step_velocity, with the map's own Objects (jump pads) and Bounds stepped as host
## each 60 Hz tick.
##   pads:   every jump pad, holding air control in 8 directions -> never out of bounds, lands inside
##   pushes: worst-case Force Push (15 m/s toward the nearest outer wall + jump 8.8 + lift 5.5 up at once, air
##           control held outward) from safe points near the walls and from every raised level -> nobody is ever
##           more than one tick outside the playable box, and everyone ends standing inside it (recovered if needed)
var results: Array = []
var done := false

const TICK := 1.0 / 60.0
const CFG := {"speed": 7.3, "accel_ground": 72, "accel_air": 16, "jump_velocity": 8.6, "gravity": 22}
const PAD_TICKS := 180
const PUSH_TICKS := 170
const PUSH := 15.0
const UP := 8.8 + 5.5       ## jumped at the moment of the push (worst case)
const LIFT := 5.5            ## standing still when pushed
const STEER_TICKS := 60      ## air control held outward for 1 s, then released so everyone settles

class Probe extends CharacterBody3D:
    var team := 0
    var dead := false
    var hp := 1000.0
    var wish := Vector3.ZERO
    var tag := ""
    var escaped := 0
    var recovered := 0
    var pad_t := -1000
    func heal(_a: float) -> float:
        return 0.0
    func take_damage(amount: float, _source, _pos: Vector3, _kind: String, _ability_id := "") -> float:
        var d := minf(amount, hp)
        hp -= d
        if hp <= 0.0:
            dead = true
        return d

var _maps: Array = ["arena01.json", "arena02.json"]
var _mi := 0
var _map: Node3D
var _bounds: MapBounds
var _objs: MapObjects
var _probes: Array = []
var _t := 0
var _phase := "load"
var _wait := 0
var reasons := {}

func _ready() -> void:
    _load()

func _load() -> void:
    _map = MapLoader.build("res://src/maps/" + _maps[_mi], {"low_quality": true})
    add_child(_map)
    _bounds = _map.get_node("Bounds")
    _bounds.authority_override = 1
    _bounds.set_physics_process(false)
    _objs = _map.get_node("Objects")
    _objs.authority_override = 1
    _objs.set_physics_process(false)
    _objs.pad_launched.connect(func(ev): ev.hero.pad_t = _t)
    _bounds.out_of_bounds.connect(func(ev):
        ev.hero.recovered += 1
        reasons[ev.reason + ":" + String(ev.volume_id)] = int(reasons.get(ev.reason + ":" + String(ev.volume_id), 0)) + 1)
    _wait = 3
    _phase = "wait"

func _probe(pos: Vector3, vel: Vector3, wish: Vector3, tag: String) -> void:
    var p := Probe.new()
    var cs := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = 0.36
    cap.height = 1.85
    cs.shape = cap
    cs.position.y = cap.height * 0.5
    p.add_child(cs)
    p.collision_layer = 0
    p.collision_mask = 1
    p.floor_snap_length = 0.25
    p.floor_max_angle = deg_to_rad(50)
    p.velocity = vel
    p.wish = wish
    p.tag = tag
    add_child(p)
    p.global_position = pos
    _probes.append(p)

func _outward(p: Vector3) -> Vector3:
    var lo := _bounds.lo
    var hi := _bounds.hi
    var c := [[p.x - lo.x, Vector3(-1, 0, 0)], [hi.x - p.x, Vector3(1, 0, 0)], [p.z - lo.z, Vector3(0, 0, -1)], [hi.z - p.z, Vector3(0, 0, 1)]]
    c.sort_custom(func(a, b): return a[0] < b[0])
    return c[0][1]

func _start_pads() -> void:
    for pad in _objs.pads:
        for k in 8:
            var a := TAU * k / 8.0
            _probe(pad.pos + Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(cos(a), 0, sin(a)), "pad%d/%d" % [pad.id, k])
    _t = 0
    _phase = "pads"

func _start_pushes() -> void:
    var pts := _bounds.safe_points()
    var lo := _bounds.lo
    var hi := _bounds.hi
    var i := 0
    for p in pts:
        var edge := minf(minf(p.x - lo.x, hi.x - p.x), minf(p.z - lo.z, hi.z - p.z))
        var raised: bool = p.y > 1.0
        if (edge < 6.0 and i % 3 == 0) or (raised and i % 2 == 0):
            var dirs: Array = [_outward(p)]
            if raised:
                dirs = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
            for d in dirs:
                _probe(p, d * PUSH + Vector3(0, UP, 0), d, "push %s %s" % [p, d])
                _probe(p, d * PUSH + Vector3(0, LIFT, 0), d, "lift %s %s" % [p, d])
        i += 1
    _t = 0
    _phase = "pushes"

func _physics_process(_dt: float) -> void:
    if done:
        return
    if _phase == "wait":
        _wait -= 1
        if _wait <= 0:
            _start_pads()
        return
    if _phase == "pushes" and _t == STEER_TICKS:
        for p in _probes:
            p.wish = Vector3.ZERO
    for p in _probes:
        p.velocity = Motion.step_velocity(p.velocity, p.wish, p.is_on_floor(), false, CFG, TICK)
        p.move_and_slide()
    _objs.step(_probes)
    _bounds.step(_probes)
    var lo := _bounds.lo - Vector3(0.6, 1.0, 0.6)
    var hi := _bounds.hi + Vector3(0.6, 1.0, 0.6)
    for p in _probes:
        var q: Vector3 = p.global_position
        if q.x < lo.x or q.x > hi.x or q.z < lo.z or q.z > hi.z or q.y < lo.y or q.y > hi.y:
            p.escaped += 1
    _t += 1
    if _phase == "pads" and _t >= PAD_TICKS:
        _report("pads")
        _start_pushes()
    elif _phase == "pushes" and _t >= PUSH_TICKS:
        _report("pushes")
        _map.queue_free()
        _mi += 1
        if _mi >= _maps.size():
            done = true
        else:
            _load()

func _report(kind: String) -> void:
    var m: String = _maps[_mi].get_basename()
    var esc: Array = []
    var oob: Array = []
    var bad_end: Array = []
    var rec := 0
    var lift_rec: Array = []
    for p in _probes:
        if p.recovered > 0 and p.tag.begins_with("lift"):
            lift_rec.append(p.tag)
        if p.escaped > 0:
            esc.append(p.tag)
        if p.recovered > 0:
            rec += 1
            oob.append(p.tag)
        if p.dead or not _bounds.in_bounds(p.global_position) or (not p.is_on_floor() and _t - p.pad_t > 90):   # mid-air only right after a pad
            bad_end.append("%s @%s v=%s rec=%d floor=%s" % [p.tag, p.global_position, p.velocity, p.recovered, p.is_on_floor()])
    var n := _probes.size()
    if kind == "pads":
        results.append(["%s_pads_never_out_of_bounds" % m, n >= 8 and oob.is_empty() and esc.is_empty(), "%d launches, oob=%s" % [n, oob.slice(0, 3)]])
        results.append(["%s_pads_land_inside" % m, bad_end.is_empty(), "%s" % [bad_end.slice(0, 3)]])
    else:
        results.append(["%s_push_never_escapes" % m, n >= 20 and esc.is_empty(), "%d pushes, %d recovered %s, escaped=%s" % [n, rec, reasons, esc.slice(0, 3)]])
        results.append(["%s_lift_push_never_needs_recovery" % m, lift_rec.is_empty(), "%s" % [lift_rec.slice(0, 3)]])
        results.append(["%s_push_ends_standing_inside" % m, bad_end.is_empty(), "%s" % [bad_end.slice(0, 3)]])
    for p in _probes:
        p.queue_free()
    _probes = []
    reasons = {}
