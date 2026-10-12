extends "res://tests/test_base.gd"
## Map tests: every map loads, spawns are reachable, spawn picker avoids enemy sight.

func _maps() -> Array:
    var out: Array = []
    for f in DirAccess.get_files_at("res://src/maps"):
        if f.ends_with(".json"):
            out.append("res://src/maps/" + f)
    return out

func test_all_maps_load() -> void:
    var maps := _maps()
    check(maps.size() >= 2, "expected >= 2 maps, got %d" % maps.size())
    for p in maps:
        var d = MapLoader.load_def(p)
        check(d is Dictionary, "%s parses" % p)
        if not d is Dictionary:
            continue
        var m := MapLoader.build(p)
        var sp: Dictionary = m.get_meta("spawns")
        check(sp.has(0) and sp.has(1), "%s has spawns for teams 0 and 1" % p)
        check(m.get_child_count() >= d.blocks.size(), "%s built all blocks" % p)
        m.free()

func test_arena01_unchanged() -> void:
    var m := MapLoader.build("res://src/maps/arena01.json")
    var sp: Dictionary = m.get_meta("spawns")
    check(m.get_meta("map_name") == "Proving Grounds", "arena01 name")
    check(sp[0][0] == Vector3(0, 0.2, 15), "arena01 player spawn")
    check(sp[1].size() == 3, "arena01 bot spawns")
    near(m.get_meta("bounds"), 17.0, 0.001, "arena01 bounds")
    m.free()

func test_arena02_layout() -> void:
    var m := MapLoader.build("res://src/maps/arena02.json")
    var zones: Array = m.get_meta("zones")
    var rooms: Dictionary = m.get_meta("spawn_rooms")
    var sp: Dictionary = m.get_meta("spawns")
    check(zones.size() == 1 and zones[0].kind == "capture", "arena02 has one capture zone")
    for t in [0, 1]:
        check(rooms.has(t), "spawn room for team %d" % t)
        for s in sp[t]:
            check(rooms[t].has_point(s), "team %d spawn %s inside its room" % [t, s])
    m.free()
    var g := MapGrid.from_def(MapLoader.load_def("res://src/maps/arena02.json"))
    var levels := {}
    for col in g.columns:
        for h in col:
            if h < 7.5:
                levels[snappedf(h, 1.0)] = true
    check(levels.has(0.0) and levels.has(4.0) and levels.has(7.0), "arena02 has ground/4m/7m levels: %s" % [levels.keys()])

func test_spawns_reachable() -> void:
    for p in _maps():
        var d: Dictionary = MapLoader.load_def(p)
        var g := MapGrid.from_def(d)
        var zones: Array = d.get("zones", [])
        var sp: Dictionary = d.spawns
        var other_start := g.node_at(Vector3(sp["0"][0][0], sp["0"][0][1], sp["0"][0][2]))
        for team in sp:
            for s in sp[team]:
                var pos := Vector3(s[0], s[1], s[2])
                var n := g.node_at(pos)
                check(n >= 0, "%s spawn %s stands on ground" % [p.get_file(), pos])
                if n < 0:
                    continue
                var r := g.flood(n)
                if zones.is_empty():
                    check(r.has(other_start), "%s spawn %s reaches team-0 spawn" % [p.get_file(), pos])
                for z in zones:
                    var ok := MapGrid.reaches_box(r, g, Vector3(z.pos[0], z.pos[1], z.pos[2]), Vector3(z.size[0], z.size[1], z.size[2]))
                    check(ok, "%s spawn %s reaches zone %s" % [p.get_file(), pos, z.id])
                # Every spawn must also reach every enemy spawn (no sealed rooms).
                for t2 in sp:
                    var e := g.node_at(Vector3(sp[t2][0][0], sp[t2][0][1], sp[t2][0][2]))
                    check(r.has(e), "%s spawn %s reaches team %s spawn" % [p.get_file(), pos, t2])

func test_flank_and_upper_routes_reachable() -> void:
    var g := MapGrid.from_def(MapLoader.load_def("res://src/maps/arena02.json"))
    var r := g.flood(g.node_at(Vector3(0, 0.2, 27)))
    for target in [Vector3(-28, 4.2, 0), Vector3(28, 4.2, 0), Vector3(-30, 7.2, 1), Vector3(30, 7.2, -1), Vector3(-6, 4.2, -10), Vector3(6, 4.2, 10), Vector3(-28, 0.2, 0), Vector3(28, 0.2, 0)]:
        var n := g.node_at(target)
        check(n >= 0 and r.has(n), "arena02 route point %s reachable" % target)

func test_wall_blocks_grid() -> void:
    var g := MapGrid.from_def({"blocks": [
        {"pos": [0, -0.5, 0], "size": [10, 1, 10]},
        {"pos": [0, 2, 0], "size": [0.6, 4, 10]}]}, 0.25)
    var r := g.flood(g.node_at(Vector3(-3, 0, 0)))
    check(not r.has(g.node_at(Vector3(3, 0, 0))), "full wall separates halves")

func test_spawn_picker_avoids_sight() -> void:
    var cands := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)]
    var enemy := [Vector3(1, 1.5, 5)]
    # Only the candidate at x=20 is hidden.
    var los := func(_a: Vector3, b: Vector3) -> bool: return b.x < 15.0
    check(SpawnPicker.pick(cands, enemy, los) == Vector3(20, 0, 0), "picks hidden spawn")
    # All hidden: farthest from nearest enemy.
    var none := func(_a: Vector3, _b: Vector3) -> bool: return false
    check(SpawnPicker.pick(cands, enemy, none) == Vector3(20, 0, 0), "farthest among hidden")
    # All visible fallback: fewest watchers then farthest.
    var all := func(_a: Vector3, _b: Vector3) -> bool: return true
    check(SpawnPicker.pick(cands, [Vector3(0, 1.5, 0)], all) == Vector3(20, 0, 0), "fallback farthest")
    var two := [Vector3(0, 1.5, 0), Vector3(20, 1.5, 3)]
    var some := func(a: Vector3, b: Vector3) -> bool: return not (a.x > 15.0 and b.x < 5.0)
    check(SpawnPicker.pick(cands, two, some) == Vector3(0, 0, 0), "fallback fewest watchers")
    check(SpawnPicker.pick(cands, [], all, 1) == Vector3(10, 0, 0), "no enemies -> default index")
