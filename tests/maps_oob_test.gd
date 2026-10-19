extends "res://tests/test_base.gd"
## Out-of-bounds kill volumes + fall recovery (maps queue 3, src/maps/map_bounds.gd).

const MAPS := ["arena01.json", "arena02.json"]
const G := 22.0

class FakeHero:
    var team := 0
    var dead := false
    var global_position := Vector3.ZERO
    var velocity := Vector3.ZERO
    var hp := 100.0
    var immune := false
    var hits: Array = []   ## [amount, source, kind]
    func take_damage(amount: float, source, _pos: Vector3, kind: String, _ability_id := "") -> float:
        if dead or immune:
            return 0.0
        var d := minf(amount, hp)
        hp -= d
        hits.append([d, source, kind])
        if hp <= 0.0:
            dead = true
        return d

func _def(f: String) -> Dictionary:
    return MapLoader.load_def("res://src/maps/" + f)

func _bounds(d: Dictionary, auth := 1) -> MapBounds:
    var b := MapBounds.from_def(d)
    b.authority_override = auth
    return b

func _hero(pos: Vector3, team := 0, hp := 100.0) -> FakeHero:
    var h := FakeHero.new()
    h.global_position = pos
    h.team = team
    h.hp = hp
    return h

static func _v(a) -> Vector3:
    return Vector3(a[0], a[1], a[2])

## Full 0.5 m walk grid flood from every spawn (what a hero can reach by walking/dropping).
static func reach_nodes(d: Dictionary) -> Array:
    var g := MapGrid.from_def(d)
    var reach := {}
    for team in d.spawns:
        for s in d.spawns[team]:
            var n := g.node_at(_v(s))
            if n >= 0 and not reach.has(n):
                reach.merge(g.flood(n))
    return [g, reach]

func test_bounds_node_from_data() -> void:
    for f in MAPS:
        var d := _def(f)
        for lq in [false, true]:
            var m := MapLoader.build("res://src/maps/" + f, {"low_quality": lq})
            var b: MapBounds = m.get_node_or_null("Bounds")
            check(b != null, "%s lq=%s has Bounds" % [f, lq])
            if b != null:
                check(b.lo == _v(d.out_of_bounds.bounds.min) and b.hi == _v(d.out_of_bounds.bounds.max), "%s box from data" % f)
                check(b.volumes.size() == d.out_of_bounds.volumes.size(), "%s volumes from data" % f)
                check(b.get_child_count() == 0, "%s Bounds adds no nodes (no bodies, no visuals)" % f)
            m.free()

func test_box_matches_outer_walls() -> void:
    # x/z = inside faces of the 4 outer walls; ceiling above every wall top
    for f in MAPS:
        var d := _def(f)
        var b := _bounds(d)
        var faces := []
        var wall_top := 0.0
        for blk in d.blocks:
            var p := _v(blk.pos)
            var s := _v(blk.size)
            if String(blk.kind) == "wall" and (s.x >= 30.0 or s.z >= 30.0):
                wall_top = maxf(wall_top, p.y + s.y * 0.5)
                if s.x >= 30.0:
                    faces.append(absf(p.z) - s.z * 0.5)
                else:
                    faces.append(absf(p.x) - s.x * 0.5)
        check(faces.size() == 4, "%s 4 outer walls" % f)
        check(faces.has(b.hi.x) and faces.has(b.hi.z) and -b.lo.x == b.hi.x and -b.lo.z == b.hi.z, "%s box = wall faces %s" % [f, faces])
        check(b.hi.y > wall_top + 1.0, "%s ceiling %.1f above wall top %.1f" % [f, b.hi.y, wall_top])
        check(b.lo.y < -1.0, "%s kill plane below the floor" % f)
        b.free()

func test_default_box_without_data() -> void:
    var d := _def("arena01.json")
    d.erase("out_of_bounds")
    var b := _bounds(d)
    check(b.lo == Vector3(-20, -3, -20) and b.hi == Vector3(20, 20, 20), "floor extent fallback %s %s" % [b.lo, b.hi])
    check(b.below.mode == "recover" and b.outside.mode == "recover" and b.volumes.is_empty(), "fallback modes")
    b.free()

func test_golden_unchanged_by_bounds() -> void:
    var g = JSON.parse_string(FileAccess.get_file_as_string("res://tests/maps_collision_golden.json"))
    for f in MAPS:
        var m := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
        check(load("res://tests/maps_visual_test.gd").signature(m) == g[f], "%s collision identical" % f)
        check(m.get_node("Bounds").find_children("*", "CollisionObject3D", true, false).is_empty(), "%s no bodies" % f)
        m.free()

func test_gameplay_data_in_bounds() -> void:
    # spawns, spawn rooms, zones, pickups, pads are never out of bounds and never inside a volume
    for f in MAPS:
        var d := _def(f)
        var b := _bounds(d)
        var pts: Array = []
        for team in d.spawns:
            for s in d.spawns[team]:
                pts.append(_v(s))
        for team in d.get("spawn_rooms", {}):
            var r = d.spawn_rooms[team]
            var lo := _v(r.pos) - _v(r.size) * 0.5
            for k in 9:
                pts.append(Vector3(lo.x + r.size[0] * (0.1 + 0.4 * (k % 3)), 0.2 + 1.5 * float(k / 3), lo.z + r.size[2] * (0.1 + 0.4 * (k % 3))))
        for z in d.get("zones", []):
            pts.append(_v(z.pos))
        for p in d.get("pickups", []) + d.get("jump_pads", []):
            pts.append(_v(p.pos))
        for p in pts:
            check(b.classify(p, 0.0).is_empty(), "%s %s in bounds" % [f, p])
        for v in b.volumes:
            for z in d.get("zones", []):
                check(not (v.aabb as AABB).intersects(AABB(_v(z.pos) - _v(z.size) * 0.5, _v(z.size))), "%s %s clear of zone" % [f, v.id])
            for team in d.get("spawn_areas", {}):
                for a in d.spawn_areas[team]:
                    check(not (v.aabb as AABB).intersects(AABB(_v(a.pos) - _v(a.size) * 0.5, _v(a.size))), "%s %s clear of spawn area" % [f, v.id])
        b.free()

func test_walkable_surfaces_in_bounds() -> void:
    # every surface a hero can walk to from a spawn is in bounds (standing still, so stand volumes count too)
    for f in MAPS:
        var d := _def(f)
        var b := _bounds(d)
        var gr := reach_nodes(d)
        var g: MapGrid = gr[0]
        var bad: Array = []
        for n in gr[1]:
            var p := g.node_pos(n) + Vector3(0, 0.05, 0)
            if not b.classify(p, 0.0).is_empty():
                bad.append(p)
        check((gr[1] as Dictionary).size() > 1000, "%s reach %d" % [f, (gr[1] as Dictionary).size()])
        check(bad.is_empty(), "%s walkable but out of bounds: %d %s" % [f, bad.size(), bad.slice(0, 5)])
        b.free()

func test_ceiling_above_every_launch() -> void:
    # highest walkable surface + strongest vertical launch (best jump + biggest lift/up_speed knockback stacked on
    # it; a pad launch + lift) stays below the ceiling, so jumping/pads/Force Push never trip it.
    var jump := 0.0   # vertical speed a hero can give itself: jump, or a leap (sets velocity.y = up_speed)
    var lift := 4.0   # vertical speed knockback ADDS on top: shockwave lift, pull up_speed, leap/charge +4
    for hf in DirAccess.get_files_at("res://src/heroes"):
        if not hf.ends_with(".json"):
            continue
        var h = JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/" + hf))
        jump = maxf(jump, float(h.get("movement", {}).get("jump_velocity", 8.5)))
        for slot in h.get("abilities", {}):
            var a: Dictionary = h.abilities[slot]
            lift = maxf(lift, float(a.get("lift", 0.0)))
            if String(a.get("type", "")) == "leap":
                jump = maxf(jump, float(a.get("up_speed", 9.0)))
            else:
                lift = maxf(lift, float(a.get("up_speed", 0.0)))
    for f in MAPS:
        var d := _def(f)
        var b := _bounds(d)
        var gr := reach_nodes(d)
        var top := 0.0
        for n in gr[1]:
            top = maxf(top, (gr[0] as MapGrid).node_pos(n).y)
        var apex := top + pow(jump + lift, 2) / (2.0 * G)
        for p in d.get("jump_pads", []):
            apex = maxf(apex, float(p.pos[1]) + pow(float(p.launch[1]) + lift, 2) / (2.0 * G))
        check(apex + 0.5 < b.hi.y, "%s apex %.2f < ceiling %.1f" % [f, apex, b.hi.y])
        b.free()

func test_safe_points() -> void:
    for f in MAPS:
        var d := _def(f)
        var b := _bounds(d)
        var pts := b.safe_points()
        check(pts.size() > 300, "%s %d safe points" % [f, pts.size()])
        var gr := reach_nodes(d)
        var g: MapGrid = gr[0]
        var keep: Array = []
        for team in d.get("spawn_rooms", {}):
            var r = d.spawn_rooms[team]
            keep.append(AABB(_v(r.pos) - _v(r.size) * 0.5, _v(r.size)))
            for br in r.get("barriers", []):
                keep.append(AABB(_v(br.pos) - _v(br.size) * 0.5, _v(br.size)))
        for team in d.get("spawn_areas", {}):
            for a in d.spawn_areas[team]:
                keep.append(AABB(_v(a.pos) - _v(a.size) * 0.5, _v(a.size)))
        for z in d.get("zones", []):
            keep.append(AABB(_v(z.pos) - _v(z.size) * 0.5, _v(z.size)))
        var bad := 0
        for p in pts:
            var n := g.node_at(p - Vector3(0, 0.05, 0))
            if n < 0 or not gr[1].has(n) or not b.in_bounds(p):
                bad += 1
                continue
            for k in keep:
                if (k as AABB).grow(0.5).has_point(p):
                    bad += 1
            for o in d.get("pickups", []) + d.get("jump_pads", []):
                if Vector2(p.x - o.pos[0], p.z - o.pos[2]).length() < 1.5 and absf(p.y - float(o.pos[1])) < 2.0:
                    bad += 1
        check(bad == 0, "%s safe points reachable, in bounds, clear of rooms/zones/objects (bad %d)" % [f, bad])
        var b2 := _bounds(d)
        check(b2.safe_points() == pts, "%s safe points deterministic" % f)
        b.free()
        b2.free()

func test_recover_outside_walls() -> void:
    var b := _bounds(_def("arena02.json"))
    var evs: Array = []
    b.out_of_bounds.connect(func(e): evs.append(e))
    var h := _hero(Vector3(36, 0.2, 4))
    b.step([h])
    check(evs.is_empty(), "in bounds: nothing")
    h.global_position = Vector3(41.5, 9.0, 4)
    h.velocity = Vector3(10, 3, 0)
    b.step([h])
    check(evs.size() == 1 and evs[0].mode == "recover" and evs[0].reason == "outside", "recovered %s" % [evs])
    check(b.in_bounds(h.global_position) and h.velocity == Vector3.ZERO, "back inside, stopped: %s" % h.global_position)
    check(h.global_position.distance_to(Vector3(36, 0.2, 4)) < 3.0, "near where it left: %s" % h.global_position)
    check(h.hits.size() == 1 and h.hits[0][0] == 10.0 and h.hits[0][1] == null and h.hits[0][2] == "fall", "10 fall damage, no credit %s" % [h.hits])
    check(not h.dead and evs[0].to == h.global_position and evs[0].from == Vector3(41.5, 9.0, 4), "event payload")
    b.free()

func test_recover_below_and_ceiling() -> void:
    for f in MAPS:
        var b := _bounds(_def(f))
        var evs: Array = []
        b.out_of_bounds.connect(func(e): evs.append(e))
        var h := _hero(Vector3(-2, 0.2, 3))
        b.step([h])
        h.global_position = Vector3(-2, -3.5, 3)
        b.step([h])
        h.global_position = Vector3(-2, b.hi.y + 1.0, 3)
        b.step([h])
        check(evs.size() == 2 and evs[0].reason == "below" and evs[1].reason == "ceiling", "%s below + ceiling %s" % [f, evs.map(func(e): return e.reason)])
        check(b.in_bounds(h.global_position) and h.hp == 80.0, "%s recovered twice, 10 each" % f)
        b.free()

func test_rim_needs_standing() -> void:
    var b := _bounds(_def("arena01.json"))
    var evs: Array = []
    b.out_of_bounds.connect(func(e): evs.append(e))
    var fly := _hero(Vector3(19.8, 4.6, 2))
    fly.velocity = Vector3(0, 3.0, 0)
    var perch := _hero(Vector3(19.8, 4.46, -2))
    for i in 60:
        b.step([fly, perch])
        if i == 13:
            check(evs.is_empty(), "no action before the 0.25 s dwell")
    check(evs.size() == 1 and evs[0].hero == perch and evs[0].volume_id == "rim_e", "perched hero recovered once %s" % [evs.map(func(e): return e.volume_id)])
    check(fly.hits.is_empty() and fly.global_position == Vector3(19.8, 4.6, 2), "hero flying past the rim untouched")
    b.free()

func test_spawn_wall_tops_no_stand() -> void:
    var d := _def("arena02.json")
    var b := _bounds(d)
    var evs: Array = []
    b.out_of_bounds.connect(func(e): evs.append(e))
    var h := _hero(Vector3(8.5, 6.0, 26), 1)
    for i in 20:
        b.step([h])
    check(evs.size() == 1 and evs[0].volume_id == "spawn0_wall_e", "enemy on a spawn-room wall top recovered %s" % [evs])
    check(h.global_position.y < 5.0 and b.in_bounds(h.global_position), "dropped to a safe point %s" % h.global_position)
    b.free()

func _with_pit() -> Dictionary:
    var d := _def("arena01.json")
    d.out_of_bounds.volumes.append({"id": "pit", "pos": [0, -1, 0], "size": [4, 4, 4], "mode": "kill"})
    return d

func test_kill_volume_and_credit() -> void:
    var b := _bounds(_with_pit())
    var evs: Array = []
    b.out_of_bounds.connect(func(e): evs.append(e))
    var enemy := _hero(Vector3(5, 0.2, 5), 1)
    var ally := _hero(Vector3(6, 0.2, 5), 0)
    var v := _hero(Vector3(0, 0.2, 5), 0)
    b.step([v])
    b.note_hit(v, ally)          # allies never get credit
    check(b.credit_for(v) == null, "ally hit ignored")
    b.note_hit(v, enemy)
    v.global_position = Vector3(0, -0.5, 0)
    b.step([v])
    check(v.dead and evs.size() == 1 and evs[0].mode == "kill" and evs[0].killed and evs[0].credit == enemy, "pit kills, credited %s" % [evs])
    check(v.hits[0][1] == enemy and v.hits[0][2] == "fall", "take_damage source = last enemy, kind fall")
    # credit window
    var w := _hero(Vector3(0, 0.2, 5), 0)
    b.step([w])
    b.note_hit(w, enemy)
    for i in 241:
        b.step([w])
    w.global_position = Vector3(0, -0.5, 0)
    b.step([w])
    check(w.dead and evs[-1].credit == null and w.hits[0][1] == null, "after 4 s: environment kill")
    b.free()

func test_kill_refused_recovers() -> void:
    var b := _bounds(_with_pit())
    var evs: Array = []
    b.out_of_bounds.connect(func(e): evs.append(e))
    var h := _hero(Vector3(0, 0.2, 5))
    h.immune = true
    b.step([h])
    h.global_position = Vector3(0, -0.5, 0)
    b.step([h])
    check(not h.dead and evs.size() == 1 and evs[0].mode == "recover" and b.in_bounds(h.global_position), "immune hero recovered, not left in the pit")
    b.free()

func test_lethal_penalty_credited() -> void:
    var b := _bounds(_def("arena01.json"))
    var enemy := _hero(Vector3(5, 0.2, 5), 1)
    var a := _hero(Vector3(0, 0.2, 5), 0, 50.0)
    var c := _hero(Vector3(3, 0.2, 5), 0, 5.0)
    b.step([a, c])
    b.note_hit(a, enemy)
    b.note_hit(c, enemy)
    a.global_position = Vector3(0, -4, 5)
    c.global_position = Vector3(3, -4, 5)
    b.step([a, c])
    check(not a.dead and a.hits[0][1] == null, "non-lethal penalty: no credit, no ult charge")
    check(c.dead and c.hits[0][1] == enemy, "lethal penalty credited to the pusher")
    b.free()

func test_occupied_point_skipped() -> void:
    var b := _bounds(_def("arena01.json"))
    var a := _hero(Vector3(0, 0.2, 2))
    var c := _hero(Vector3(0, 0.2, 2))
    b.step([a, c])
    a.global_position = Vector3(0, -4, 2)
    c.global_position = Vector3(0, -4, 2)
    b.step([a, c])
    check(a.global_position.distance_to(c.global_position) >= 1.0, "two recovered heroes not stacked %s %s" % [a.global_position, c.global_position])
    b.free()

func test_client_never_acts() -> void:
    var b := _bounds(_def("arena01.json"), 0)
    var h := _hero(Vector3(0, -10, 0))
    b.step([h])
    check(h.global_position == Vector3(0, -10, 0) and h.hits.is_empty(), "client step is a no-op")
    b.free()

func test_heroes_on_gameplay_spots_untouched() -> void:
    for f in MAPS:
        var d := _def(f)
        var b := _bounds(d)
        var hs: Array = []
        for team in d.spawns:
            for s in d.spawns[team]:
                hs.append(_hero(_v(s), int(team)))
        for o in d.get("pickups", []) + d.get("jump_pads", []) + d.get("zones", []):
            hs.append(_hero(_v(o.pos)))
        var n := [0]
        b.out_of_bounds.connect(func(_e): n[0] += 1)
        for i in 60:
            b.step(hs)
        check(n[0] == 0, "%s spawns / zones / objects never trigger (%d)" % [f, n[0]])
        b.free()

func test_dead_heroes_ignored() -> void:
    var b := _bounds(_def("arena01.json"))
    var h := _hero(Vector3(0, -10, 0))
    h.dead = true
    b.step([h])
    check(h.global_position == Vector3(0, -10, 0), "dead hero not moved")
    b.free()
