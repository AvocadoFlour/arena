extends "res://tests/test_base.gd"
## Readability / snag pass (maps queue 2): ramp ends flush, arena01 cover variety, symmetric arena02 additions,
## new blocks clear of gameplay data, golden = v0.9 golden + additions (one documented exception).
## Physics checks (stuck points, snags, sightlines) live in tests/maps_snag_sim.gd and tests/maps_sight_sim.gd.

const MAPS := ["arena01.json", "arena02.json"]
const V09_BLOCKS := {"arena01.json": 16, "arena02.json": 44}
## Collision entries of v0.9 that this pass changed on purpose (see docs/requests/maps.md, queue 2):
const GOLDEN_EXCEPTIONS := {"arena01.json": ["ramp_07"], "arena02.json": ["ramp_18", "ramp_19"]}

func _def(f: String) -> Dictionary:
    return MapLoader.load_def("res://src/maps/" + f)

static func _basis(b: Dictionary) -> Basis:
    var r: Array = b.get("rot_deg", [0, 0, 0])
    return Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])), EULER_ORDER_YXZ)

## Top-surface midline end points of a ramp (rotated slab): [low_end, high_end].
static func ramp_ends(b: Dictionary) -> Array:
    var bs := _basis(b)
    var e := Vector3(b.size[0], b.size[1], b.size[2]) * 0.5
    var c := Vector3(b.pos[0], b.pos[1], b.pos[2])
    var ax := 0 if e.x > e.z else 2
    var along := Vector3.ZERO
    along[ax] = e[ax]
    var top: Vector3 = bs * Vector3(0, e.y, 0)
    var p1: Vector3 = c + top + bs * along
    var p2: Vector3 = c + top - bs * along
    return [p1, p2] if p1.y < p2.y else [p2, p1]

func test_ramp_ends_flush() -> void:
    # A ramp's top surface must meet the floor / the deck it leads to without a lip a capsule snags on
    # (> 0.1 m; arena01 ramp_07 had 0.19 m at the foot and 0.27 m at the platform edge before this pass, and
    # arena02 ramp_18/19 rose away from the dais: 1.03 m step at the outer end, 0.84 m drop at the dais).
    for f in MAPS:
        var d := _def(f)
        var g := MapGrid.from_def(d)
        for i in d.blocks.size():
            var b: Dictionary = d.blocks[i]
            if String(b.kind) != "ramp":
                continue
            var ends := ramp_ends(b)
            var dir: Vector3 = (ends[1] - ends[0])
            dir.y = 0
            dir = dir.normalized()
            check(ends[0].y <= 0.1 + _surface(g, ends[0] - dir * 0.3, ends[0].y), "%s ramp_%02d foot lip: corner %.3f" % [f, i, ends[0].y])
            var deck := _surface(g, ends[1] + dir * 0.3, ends[1].y)
            check(ends[1].y - deck <= 0.1, "%s ramp_%02d head lip %.3f above deck %.3f" % [f, i, ends[1].y - deck, deck])

## Standable height nearest y in the column at p (MapGrid), excluding nothing.
func _surface(g: MapGrid, p: Vector3, y: float) -> float:
    var ix := int(round((p.x - g.origin.x) / g.cell))
    var iz := int(round((p.z - g.origin.y) / g.cell))
    var best := 0.0
    var bd := INF
    for h in g.columns[iz * g.nx + ix]:
        if absf(h - y) < bd:
            bd = absf(h - y)
            best = h
    return best

func test_arena01_cover_variety() -> void:
    var d := _def("arena01.json")
    var covers := 0
    for b in d.blocks:
        if String(b.kind) == "cover":
            covers += 1
    check(covers == 8, "arena01 keeps exactly 8 'cover' blocks (ai_team_driver contract): %d" % covers)
    var heights := {}
    var rotated := false
    var tall := false
    var low := false
    var added: Array = d.blocks.slice(V09_BLOCKS["arena01.json"])
    for b in added:
        check(String(b.kind) == "wall", "new arena01 pieces are non-cover kind: %s" % [b.pos])
        heights[snappedf(float(b.size[1]), 0.1)] = true
        rotated = rotated or (b.has("rot_deg") and float(b.rot_deg[1]) != 0.0)
        tall = tall or float(b.size[1]) >= 3.0
        low = low or float(b.size[1]) <= 1.2
    check(added.size() >= 4, "arena01 got >= 4 new cover pieces: %d" % added.size())
    check(heights.size() >= 3 and rotated and tall and low, "varied heights %s, one rotated, one tall, one low" % [heights.keys()])
    var m := MapLoader.build("res://src/maps/arena01.json")
    for i in range(V09_BLOCKS["arena01.json"], d.blocks.size()):
        check(m.get_node_or_null("wall_%02d" % i) is StaticBody3D, "arena01 wall_%02d built" % i)
    m.free()

func test_arena02_additions_symmetric() -> void:
    # arena02 is point-symmetric (x, z) -> (-x, -z); every new block has its mirror (team colour may differ).
    var d := _def("arena02.json")
    var added: Array = d.blocks.slice(V09_BLOCKS["arena02.json"])
    check(added.size() >= 10, "arena02 additions: %d" % added.size())
    for b in added:
        check(String(b.kind) != "cover", "arena02 additions avoid the AI 'cover' kind: %s" % [b.pos])
        var found := false
        for o in added:
            if is_equal_approx(float(o.pos[0]), -float(b.pos[0])) and is_equal_approx(float(o.pos[2]), -float(b.pos[2])) \
                    and is_equal_approx(float(o.pos[1]), float(b.pos[1])) and o.size == b.size:
                found = true
        check(found, "arena02 block %s has a mirrored twin" % [b.pos])

func test_new_blocks_clear_of_gameplay_data() -> void:
    for f in MAPS:
        var d := _def(f)
        var s := SpawnRooms.from_def(d)
        for b in d.blocks.slice(V09_BLOCKS[f]):
            var c := Vector3(b.pos[0], b.pos[1], b.pos[2])
            var e := Vector3(b.size[0], b.size[1], b.size[2]) * 0.5
            var r := Vector2(e.x, e.z).length()
            for v in s.volumes:
                var bb: AABB = v.aabb
                check(not bb.grow(0.1).intersects(AABB(c - Vector3(r, e.y, r), Vector3(r, e.y, r) * 2.0)), "%s block %s clear of team %d %s volume" % [f, c, v.team, v.kind])
            for z in d.get("zones", []):
                var zb := AABB(Vector3(z.pos[0], z.pos[1], z.pos[2]) - Vector3(z.size[0], z.size[1], z.size[2]) * 0.5, Vector3(z.size[0], z.size[1], z.size[2]))
                check(not zb.intersects(AABB(c - e, e * 2.0)), "%s block %s outside capture zone %s" % [f, c, z.id])
            for key in ["pickups", "jump_pads"]:
                for o in d.get(key, []):
                    var op := Vector2(o.pos[0], o.pos[2])
                    check(op.distance_to(Vector2(c.x, c.z)) > r + 1.0, "%s block %s clear of %s at %s" % [f, c, key, op])
            for t in d.spawns:
                for p in d.spawns[t]:
                    check(Vector2(p[0], p[2]).distance_to(Vector2(c.x, c.z)) > r + 1.0, "%s block %s clear of spawn %s" % [f, c, p])
        s.free()

func test_golden_is_v09_plus_additions() -> void:
    var old = JSON.parse_string(FileAccess.get_file_as_string("res://tests/maps_collision_golden_v09.json"))
    var cur = JSON.parse_string(FileAccess.get_file_as_string("res://tests/maps_collision_golden.json"))
    check(old is Dictionary and cur is Dictionary, "goldens load")
    if not (old is Dictionary and cur is Dictionary):
        return
    for f in old:
        var ex: Array = GOLDEN_EXCEPTIONS.get(f, [])
        for entry in old[f]:
            var name := String(entry).get_slice("|", 0)
            if ex.has(name):
                check(not (cur[f] as Array).has(entry), "%s %s was moved on purpose (exception listed)" % [f, name])
                continue
            check((cur[f] as Array).has(entry), "%s v0.9 collision kept: %s" % [f, name])
        var added := 0
        for entry in cur[f]:
            if not (old[f] as Array).has(entry):
                added += 1
        check(added == (cur[f] as Array).size() - (old[f] as Array).size() + ex.size(), "%s only additions besides the exceptions" % f)

func test_reachability_after_pass() -> void:
    # every spawn reaches every zone and every enemy spawn (MapGrid); arena01: every new piece's surroundings
    # are reachable from the player spawn (no sealed pockets behind the L-wall / rotated slab).
    for f in MAPS:
        var d := _def(f)
        var g := MapGrid.from_def(d)
        var sp: Array = d.spawns["0"][0]
        var r := g.flood(g.node_at(Vector3(sp[0], sp[1], sp[2])))
        for b in d.blocks.slice(V09_BLOCKS[f]):
            var c := Vector3(b.pos[0], 0.0, b.pos[2])
            var e := Vector2(b.size[0], b.size[2]).length() * 0.5 + 1.0
            for k in 8:
                var p := c + Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * e
                var n := g.node_at(p, 0.6)
                if n >= 0:
                    check(r.has(n), "%s ground around new block %s reachable (%s)" % [f, c, p])
