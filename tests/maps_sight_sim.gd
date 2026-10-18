extends Node3D
## Sightline / readability scan (maps queue 2), real physics rays (layer 1) on the built maps:
##   narrow: no passage narrower than the widest collider (Cob r 0.65) between two spots where it fits
##   lane:   longest stretch of a ground-level sightline (eye 1.6 m, 8 directions from a 2 m sample grid) along
##           which no cover (a block filling 0.3..1.2 m above ground) is within COVER_NEAR m -> <= LANE_MAX
##   camp:   per spawn-room door (first barrier of each team room), enemy-reachable standing spots farther than
##           CAMP_FAR m whose eye sees the door exit (chest 1.0 m, 1.5 m outside the barrier) -> <= CAMP_MAX
##   cover:  every "cover" block and free-standing wall piece (<= 3.5 m tall, <= 4 m long) hides something: from
##           one of its 4 sides, it is itself the occluder for >= COVER_MIN of the threat spots within 30 m
## Standalone listing: godot --headless --path . -s tests/maps_sight_scan.gd
var results: Array = []
var done := false
var verbose := false
var map_files: Array = ["arena01.json", "arena02.json"]
var report := {}

const EYE := 1.6
const CHEST := 1.0
const COVER_NEAR := 2.5
const LANE_MAX := {"arena01.json": 26.0, "arena02.json": 36.0}   # arena02: diagonals through the open capture zone (mid kept unchanged)
const CAMP_FAR := 20.0
const CAMP_MAX := 40     # before the pass: 185 / 180 spots on arena02
const COVER_MIN := 0.2
const SPACING := 2.0

var _mi := 0
var _wait := 0
var _map: Node3D
var _def: Dictionary
var _grid: MapGrid
var _samples: Array = []        ## Vector3 standing points (all levels)
var _near := {}                 ## Vector2i(1 m cell) -> true where cover is near (ground level)

func _ready() -> void:
    _load()

func _load() -> void:
    var path: String = "res://src/maps/" + map_files[_mi]
    _def = MapLoader.load_def(path)
    _map = MapLoader.build(path, {"low_quality": true})
    add_child(_map)
    _grid = MapGrid.from_def(_def)
    _wait = 3

func _physics_process(_dt: float) -> void:
    if done or _map == null:
        return
    _wait -= 1
    if _wait > 0:
        return
    _scan()
    _map.queue_free()
    _map = null
    _mi += 1
    if _mi < map_files.size():
        await get_tree().physics_frame
        _load()
    else:
        done = true

func _space() -> PhysicsDirectSpaceState3D:
    return get_world_3d().direct_space_state

func _ray(a: Vector3, b: Vector3) -> Dictionary:
    return _space().intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))

func _fits(p: Vector3, r := 0.4, h := 1.8) -> bool:
    var cap := CapsuleShape3D.new()
    cap.radius = r
    cap.height = h
    var q := PhysicsShapeQueryParameters3D.new()
    q.shape = cap
    q.collision_mask = 1
    q.transform = Transform3D(Basis(), p + Vector3(0, h * 0.5 + 0.1, 0))
    return _space().intersect_shape(q, 1).is_empty()

func _build_samples() -> void:
    _samples = []
    var sp: Array = _def.spawns["0"][0]
    var reach := _grid.flood(_grid.node_at(Vector3(sp[0], sp[1], sp[2])))
    var step := maxi(1, int(round(SPACING / _grid.cell)))
    for iz in range(0, _grid.nz, step):
        for ix in range(0, _grid.nx, step):
            var col: Array = _grid.columns[iz * _grid.nx + ix]
            for li in col.size():
                var h: float = col[li]
                if h < -0.1 or h > 12.0 or not reach.has((iz * _grid.nx + ix) * 16 + li):
                    continue
                var cp := _grid.cell_pos(ix, iz)
                var p := Vector3(cp.x, h, cp.y)
                if _fits(p):
                    _samples.append(p)
    # cover-near map (ground level): blocks whose world box spans 0.3..1.2 m, within COVER_NEAR (2D)
    _near = {}
    var boxes: Array = []
    for b in _def.blocks:
        if String(b.get("kind", "")) == "floor":
            continue
        var rot: Array = b.get("rot_deg", [0, 0, 0])
        var basis := Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2])), EULER_ORDER_YXZ)
        var e := Vector3(b.size[0], b.size[1], b.size[2]) * 0.5
        var c := Vector3(b.pos[0], b.pos[1], b.pos[2])
        var ylo := INF
        var yhi := -INF
        for sx in [-1, 1]:
            for sy in [-1, 1]:
                for sz in [-1, 1]:
                    var w: Vector3 = c + basis * Vector3(e.x * sx, e.y * sy, e.z * sz)
                    ylo = minf(ylo, w.y)
                    yhi = maxf(yhi, w.y)
        boxes.append({"c": c, "b": basis, "e": e, "ylo": ylo, "yhi": yhi})
    var x0 := int(floor(_grid.origin.x))
    var z0 := int(floor(_grid.origin.y))
    for iz in range(z0, z0 + int(_grid.nz * _grid.cell) + 1):
        for ix in range(x0, x0 + int(_grid.nx * _grid.cell) + 1):
            var p := Vector3(ix + 0.5, 0.5, iz + 0.5)
            var g := _ground(p.x, p.z)
            for o in boxes:
                if not (o.ylo <= g + 0.3 and o.yhi >= g + 1.2):
                    continue
                var l: Vector3 = (o.b as Basis).transposed() * (p - o.c)
                var dx := maxf(0.0, absf(l.x) - o.e.x)
                var dz := maxf(0.0, absf(l.z) - o.e.z)
                if Vector2(dx, dz).length() <= COVER_NEAR:
                    _near[Vector2i(ix, iz)] = true
                    break

## Highest standable level <= 1.5 m in the column (ground-level lanes; dais top counts).
func _ground(x: float, z: float) -> float:
    var ix := clampi(int(round((x - _grid.origin.x) / _grid.cell)), 0, _grid.nx - 1)
    var iz := clampi(int(round((z - _grid.origin.y) / _grid.cell)), 0, _grid.nz - 1)
    var g := 0.0
    for h in _grid.columns[iz * _grid.nx + ix]:
        if h <= 1.5:
            g = maxf(g, h)
    return g

func _covered(p: Vector3) -> bool:
    return _near.has(Vector2i(int(floor(p.x)), int(floor(p.z))))

func _scan() -> void:
    var f: String = map_files[_mi]
    _build_samples()
    var rep := {"samples": _samples.size()}
    # --- lanes
    var best := 0.0
    var best_line := []
    var lanes: Array = []
    for p in _samples:
        if p.y > 0.6:
            continue
        for k in 8:
            var d := Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0))
            var a: Vector3 = p + Vector3(0, EYE, 0)
            var hit := _ray(a, a + d * 90.0)
            var L: float = 90.0 if hit.is_empty() else a.distance_to(hit.position)
            var run := 0.0
            var run0 := 0.0
            var t := 0.0
            while t <= L:
                var q: Vector3 = p + d * t
                if _covered(q):
                    run = 0.0
                    run0 = t + 1.0
                else:
                    run += 1.0
                    if run > best:
                        best = run
                        best_line = [p + d * run0, p + d * t]
                    if run >= LANE_MAX[f] and verbose:
                        var key := "%s->%s" % [snapped(p + d * run0, Vector3(4, 1, 4)), snapped(p + d * t, Vector3(4, 1, 4))]
                        if not lanes.has(key):
                            lanes.append(key)
                t += 1.0
    rep["lane_max"] = best
    rep["lanes"] = lanes
    rep["lane_line"] = best_line
    results.append(["%s_no_long_uncovered_lane" % f.get_basename(), best <= LANE_MAX[f], "longest %.0f m (max %.0f) %s" % [best, LANE_MAX[f], str(best_line)]])
    # --- spawn-door camping lines
    var sr: SpawnRooms = _map.get_node_or_null("SpawnRooms")
    var rooms: Dictionary = _def.get("spawn_rooms", {})
    for t in rooms:
        var bars: Array = rooms[t].get("barriers", [])
        if bars.is_empty():
            continue
        var team := int(t)
        var rc := Vector3(rooms[t].pos[0], 0, rooms[t].pos[2])
        var bp := Vector3(bars[0].pos[0], 0, bars[0].pos[2])
        var out := (bp - rc)
        out.y = 0
        out = out.normalized()
        var door := bp + out * 1.5 + Vector3(0, CHEST, 0)
        var far: Array = []
        for p in _samples:
            if sr != null and sr.owner_at(p) == team:
                continue
            var e: Vector3 = p + Vector3(0, EYE, 0)
            var dist := e.distance_to(door)
            if dist < CAMP_FAR or dist > 60.0:
                continue
            if _ray(e, door).is_empty():
                far.append(p)
        rep["camp_%d" % team] = far.size()
        rep["camp_%d_pts" % team] = far.slice(0, 40)
        results.append(["%s_door%d_camping_lines" % [f.get_basename(), team], far.size() <= CAMP_MAX, "spots > %.0f m seeing the door: %d (max %d)" % [CAMP_FAR, far.size(), CAMP_MAX]])
    # --- passages narrower than the widest collider (Cob r 0.65) between two spots where it fits
    var narrow: Array = []
    var sp0: Array = _def.spawns["0"][0]
    var reach := _grid.flood(_grid.node_at(Vector3(sp0[0], sp0[1], sp0[2])))
    for n in reach:
        var p := _grid.node_pos(n)
        if p.y > 12.0 or _fits(p, 0.65, 1.5) or not _fits(p, 0.36, 1.85):
            continue
        for ax in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
            var a: Vector3 = p + ax * 1.0
            var b: Vector3 = p - ax * 1.0
            var na := _grid.node_at(a, 0.4)
            var nb := _grid.node_at(b, 0.4)
            if na < 0 or nb < 0 or absf(_grid.node_pos(na).y - p.y) > 0.15 or absf(_grid.node_pos(nb).y - p.y) > 0.15:
                continue
            var perp := Vector3(ax.z, 0, ax.x) * 0.35   # sliding sideways doesn't help: blocked on both sides
            if _fits(p + perp, 0.65, 1.5) or _fits(p - perp, 0.65, 1.5):
                continue
            if _fits(_grid.node_pos(na), 0.65, 1.5) and _fits(_grid.node_pos(nb), 0.65, 1.5):
                narrow.append(snapped(p, Vector3(0.5, 0.5, 0.5)))
                break
    rep["narrow"] = narrow
    results.append(["%s_no_passage_narrower_than_widest_hero" % f.get_basename(), narrow.is_empty(), "%d spots %s" % [narrow.size(), str(narrow.slice(0, 6))]])
    # --- cover usefulness
    var weak: Array = []
    var info: Array = []
    for c in _map.get_children():
        if not (c is StaticBody3D) or not c.has_meta("block_id"):
            continue
        var b: Dictionary = _def.blocks[int(c.get_meta("block_id"))]
        var sz := Vector3(b.size[0], b.size[1], b.size[2])
        var kind := String(c.get_meta("kind", ""))
        # cover blocks, plus free-standing wall pieces used as cover (not perimeter/room/lane walls)
        if not (kind == "cover" or (kind == "wall" and sz.y <= 3.5 and maxf(sz.x, sz.z) <= 4.0)):
            continue
        var cpos := (c as Node3D).global_position
        var base := cpos.y - sz.y * 0.5
        var bestf := 0.0
        for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
            var ext: float = absf(side.x) * sz.x * 0.5 + absf(side.z) * sz.z * 0.5
            var spot: Vector3 = cpos + side * (ext + 0.6)
            spot.y = base + CHEST
            if not _fits(Vector3(spot.x, base, spot.z)):
                continue
            var n := 0
            var by_self := 0
            for p in _samples:
                var e: Vector3 = p + Vector3(0, EYE, 0)
                if e.distance_to(spot) > 30.0 or e.distance_to(spot) < 3.0:
                    continue
                n += 1
                var hit := _ray(e, spot)
                if not hit.is_empty() and hit.collider == c:
                    by_self += 1
            if n > 0:
                bestf = maxf(bestf, float(by_self) / float(n))
        info.append("%s:%.2f" % [c.name, bestf])
        if bestf < COVER_MIN:
            weak.append("%s %.2f" % [c.name, bestf])
    rep["cover"] = info
    results.append(["%s_every_cover_hides_something" % f.get_basename(), weak.is_empty(), "weak=%s" % [weak]])
    report[f] = rep
    if verbose:
        print("SIGHT %s %s" % [f, JSON.stringify(rep)])
