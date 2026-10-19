extends Node3D
## Snag / stuck scan (maps queue 2, readability pass): real Jolt CharacterBody3D capsules driven with
## Motion.step_velocity over a sampled grid of standable points (MapGrid), 8 directions each.
##   stuck: the probe can't get 0.3 m away in any direction, even jumping   -> must be 0
##   lip:   blocked (< 0.5 m in 0.5 s) although MapGrid walks there with a step-up > 0.12 m per 0.5 m
##   ledge: like lip but > 0.3 m (needs a jump) or across a ramp's side edge: by design, reported only
##   gap:   blocked although MapGrid walks there level (thin gap / ramp seam / corner narrower than the collider)
## Expected = the MapGrid chain at 0.5, 1.0, 1.5 m along the direction is standable (up <= 0.6, down <= 5 per step)
## and the capsule fits at 1.5 m. Probe classes: widest (Cob r 0.65) and tallest/slimmest (Tomo r 0.36 h 1.85).
## Probes are on collision layer 0 (they never touch each other). Standalone, verbose listing:
##   godot --headless --path . -s tests/maps_snag_scan.gd [-- --spacing=1.0 --maps=arena01,arena02]
var results: Array = []
var done := false
var verbose := false
var spacing := 2.0
var map_files: Array = ["arena01.json", "arena02.json"]
var classes: Array = [
    {"id": "wide", "r": 0.65, "h": 1.5, "cfg": {"speed": 5.8, "accel_ground": 50, "accel_air": 10, "jump_velocity": 7.0, "gravity": 22}},
    {"id": "slim", "r": 0.36, "h": 1.85, "cfg": {"speed": 7.3, "accel_ground": 72, "accel_air": 16, "jump_velocity": 8.6, "gravity": 22}}]
var findings: Array = []      ## {map, cls, kind, pos, dir, dh, moved}
var counts := {}              ## "map/cls" -> {samples, stuck, lip, gap}

const DIRS := 8
const MOVE_FRAMES := 30
const BATCH := 1200
const LIP := 0.12
const LEDGE := 0.3

var _mi := 0
var _ci := 0
var _map: Node3D
var _grid: MapGrid
var _phase := "load"
var _wait := 0
var _samples: Array = []      ## [{pos, fit, exp: [bool x8], dh: [x8], moved: [x8], jmoved: [x8]}]
var _batch0 := 0
var _dir := 0
var _f := 0
var _probes: Array = []
var _stuck_idx: Array = []
var _jump := false

func _ready() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--spacing="):
            spacing = float(a.get_slice("=", 1))
        elif a.begins_with("--maps="):
            map_files = []
            for m in a.get_slice("=", 1).split(","):
                map_files.append(m + ".json")
    _load_map()

func _load_map() -> void:
    var path: String = "res://src/maps/" + map_files[_mi]
    _map = MapLoader.build(path, {"low_quality": true})
    add_child(_map)
    _grid = MapGrid.from_def(MapLoader.load_def(path))
    _ci = 0
    _phase = "wait"
    _wait = 3

func _cls() -> Dictionary:
    return classes[_ci]

func _key() -> String:
    return "%s/%s" % [map_files[_mi].get_basename(), _cls().id]

## Standable level in column at (x, z) nearest to `from_h` within [from_h - 5, from_h + 0.6]; NAN if none.
func _level(x: float, z: float, from_h: float) -> float:
    var ix := int(round((x - _grid.origin.x) / _grid.cell))
    var iz := int(round((z - _grid.origin.y) / _grid.cell))
    if ix < 0 or iz < 0 or ix >= _grid.nx or iz >= _grid.nz:
        return NAN
    var best := NAN
    for h in _grid.columns[iz * _grid.nx + ix]:
        var dh: float = h - from_h
        if dh <= 0.6 and dh >= -5.0 and (is_nan(best) or absf(dh) < absf(best - from_h)):
            best = h
    return best

## True when walking direction d at t runs up/down the surface (|cos| >= 0.85 to the steepest slope), or the
## surface is flat: a lip there is an accidental seam. False = the lip is a ramp's side edge (a ledge, by design).
func _along_slope(t: Vector3, h: float, d: Vector3) -> bool:
    var hx1 := _level(t.x + 0.5, t.z, h)
    var hx0 := _level(t.x - 0.5, t.z, h)
    var hz1 := _level(t.x, t.z + 0.5, h)
    var hz0 := _level(t.x, t.z - 0.5, h)
    if is_nan(hx1) or is_nan(hx0) or is_nan(hz1) or is_nan(hz0):
        return true
    var g := Vector2(hx1 - hx0, hz1 - hz0)
    if g.length() < 0.05:
        return true
    return absf(g.normalized().dot(Vector2(d.x, d.z))) >= 0.85

func _fits(p: Vector3) -> bool:
    var c: Dictionary = _cls()
    var cap := CapsuleShape3D.new()
    cap.radius = c.r
    cap.height = c.h
    var q := PhysicsShapeQueryParameters3D.new()
    q.shape = cap
    q.collision_mask = 1
    q.transform = Transform3D(Basis(), p + Vector3(0, c.h * 0.5 + 0.1, 0))
    return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func _dirv(k: int) -> Vector3:
    var a := TAU * float(k) / DIRS
    return Vector3(cos(a), 0, sin(a))

func _build_samples() -> void:
    _samples = []
    var step := maxi(1, int(round(spacing / _grid.cell)))
    for iz in range(0, _grid.nz, step):
        for ix in range(0, _grid.nx, step):
            var col: Array = _grid.columns[iz * _grid.nx + ix]
            for h in col:
                if h < -0.1 or h > 12.0:
                    continue
                var cp := _grid.cell_pos(ix, iz)
                var p := Vector3(cp.x, h, cp.y)
                if not _fits(p):
                    continue
                var s := {"pos": p, "exp": [], "dh": [], "moved": [], "jmoved": [], "along": []}
                for k in DIRS:
                    var d := _dirv(k)
                    var hh: float = h
                    var ok := true
                    var maxup := 0.0
                    for i in [1, 2, 3]:
                        var q: Vector3 = p + d * (0.5 * float(i))
                        var nh := _level(q.x, q.z, hh)
                        # the capsule must also fit along the way at the higher of the two levels (no walking
                        # "through" a crate or under a low overhang to drop to the level below)
                        if is_nan(nh) or not _fits(Vector3(q.x, maxf(hh, nh), q.z)):
                            ok = false
                            break
                        maxup = maxf(maxup, nh - hh)
                        hh = nh
                    if ok:
                        ok = _fits(Vector3(p.x + d.x * 1.5, hh, p.z + d.z * 1.5))
                    s.exp.append(ok)
                    s.dh.append(maxup)
                    s.along.append(_along_slope(p + d * 1.5, hh, d))
                    s.moved.append(0.0)
                    s.jmoved.append(0.0)
                _samples.append(s)
    counts[_key()] = {"samples": _samples.size(), "stuck": 0, "lip": 0, "gap": 0, "ledge": 0}

func _make_probes(n: int) -> void:
    for p in _probes:
        p.queue_free()
    _probes = []
    var c: Dictionary = _cls()
    for i in n:
        var b := CharacterBody3D.new()
        b.collision_layer = 0
        b.collision_mask = 1
        b.floor_snap_length = 0.25
        b.floor_max_angle = deg_to_rad(50)
        var cs := CollisionShape3D.new()
        var cap := CapsuleShape3D.new()
        cap.radius = c.r
        cap.height = c.h
        cs.shape = cap
        cs.position.y = c.h * 0.5
        b.add_child(cs)
        add_child(b)
        _probes.append(b)

func _batch_list() -> Array:
    if _jump:
        return _stuck_idx.slice(_batch0, mini(_batch0 + BATCH, _stuck_idx.size()))
    var out: Array = []
    for i in range(_batch0, mini(_batch0 + BATCH, _samples.size())):
        out.append(i)
    return out

func _reset_probes(lst: Array) -> void:
    for j in lst.size():
        var b: CharacterBody3D = _probes[j]
        b.global_position = _samples[lst[j]].pos + Vector3(0, 0.03, 0)
        b.velocity = Vector3.ZERO

func _physics_process(dt: float) -> void:
    if done:
        return
    match _phase:
        "wait":
            _wait -= 1
            if _wait <= 0:
                _build_samples()
                _jump = false
                _batch0 = 0
                _start_batch()
        "move":
            var lst := _batch_list()
            var c: Dictionary = _cls()
            var d := _dirv(_dir)
            for j in lst.size():
                var b: CharacterBody3D = _probes[j]
                var jump := _jump and _f < 3
                b.velocity = Motion.step_velocity(b.velocity, d, b.is_on_floor(), jump, c.cfg, dt)
                b.move_and_slide()
            _f += 1
            if _f >= (MOVE_FRAMES + 15 if _jump else MOVE_FRAMES):
                for j in lst.size():
                    var b: CharacterBody3D = _probes[j]
                    var s: Dictionary = _samples[lst[j]]
                    var dv: Vector3 = b.global_position - s.pos
                    var mv := Vector2(dv.x, dv.z).length()
                    if dv.y < -6.0:
                        mv = 99.0
                    if _jump:
                        s.jmoved[_dir] = mv
                    else:
                        s.moved[_dir] = mv
                _dir += 1
                _f = 0
                if _dir >= DIRS:
                    _batch0 += BATCH
                    var total := _stuck_idx.size() if _jump else _samples.size()
                    if _batch0 >= total:
                        if not _jump:
                            _collect_stuck_candidates()
                            if not _stuck_idx.is_empty():
                                _jump = true
                                _batch0 = 0
                                _start_batch()
                                return
                        _classify()
                        _next_class()
                        return
                    _start_batch()
                    return
                _reset_probes(lst)

func _start_batch() -> void:
    var lst := _batch_list()
    _make_probes(lst.size())
    _reset_probes(lst)
    _dir = 0
    _f = 0
    _phase = "move"

func _collect_stuck_candidates() -> void:
    _stuck_idx = []
    for i in _samples.size():
        if (_samples[i].moved as Array).max() < 0.3:
            _stuck_idx.append(i)

func _classify() -> void:
    var cnt: Dictionary = counts[_key()]
    for i in _samples.size():
        var s: Dictionary = _samples[i]
        if _stuck_idx.has(i) and (s.jmoved as Array).max() < 0.3:
            cnt.stuck += 1
            findings.append({"map": map_files[_mi], "cls": _cls().id, "kind": "stuck", "pos": s.pos, "dir": -1, "dh": 0.0, "moved": 0.0})
            continue
        for k in DIRS:
            if s.exp[k] and s.moved[k] < 0.5:
                var kind := "lip" if s.dh[k] > LIP else "gap"
                if kind == "lip" and (s.dh[k] > LEDGE or not s.along[k]):
                    kind = "ledge"   # deliberate step (> 0.3 m, jump) or a ramp's side edge: reported, allowed
                cnt[kind] += 1
                findings.append({"map": map_files[_mi], "cls": _cls().id, "kind": kind, "pos": s.pos, "dir": k, "dh": s.dh[k], "moved": s.moved[k]})

func _next_class() -> void:
    for p in _probes:
        p.queue_free()
    _probes = []
    var c: Dictionary = counts[_key()]
    if verbose:
        print("SCAN %s samples=%d stuck=%d lip=%d gap=%d ledge=%d" % [_key(), c.samples, c.stuck, c.lip, c.gap, c.ledge])
    results.append(["%s_samples" % _key(), c.samples > 50, "samples=%d" % c.samples])
    results.append(["%s_no_stuck_points" % _key(), c.stuck == 0, "stuck=%d %s" % [c.stuck, _first("stuck")]])
    results.append(["%s_no_snags" % _key(), c.lip + c.gap == 0, "lip=%d gap=%d %s" % [c.lip, c.gap, _first("")]])
    _ci += 1
    if _ci < classes.size():
        _phase = "wait"
        _wait = 1
        return
    _map.queue_free()
    _mi += 1
    if _mi < map_files.size():
        _phase = "idle"
        await get_tree().physics_frame
        _load_map()
        return
    done = true

func _first(kind: String) -> String:
    var out: Array = []
    for f in findings:
        if f.map == map_files[_mi] and f.cls == _cls().id and (f.kind == kind or (kind == "" and f.kind != "ledge")) and out.size() < 4:
            out.append("%s@(%.1f,%.1f,%.1f)d%d" % [f.kind, f.pos.x, f.pos.y, f.pos.z, f.dir])
    return str(out)
