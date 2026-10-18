extends "res://tests/test_base.gd"
## Protected spawn rooms (maps queue item 1): enemy blocked, ally passes, spawn-shield hook, determinism,
## team-aware reachability, visuals, no collision change.

const MAPS := ["arena01.json", "arena02.json"]

class FakeHero:
    var team := 0
    var dead := false
    var global_position := Vector3.ZERO
    var velocity := Vector3.ZERO

func _rooms(f: String) -> SpawnRooms:
    var s := SpawnRooms.from_def(MapLoader.load_def("res://src/maps/" + f))
    s.authority_override = 1
    return s

func _hero(team: int, pos: Vector3) -> FakeHero:
    var h := FakeHero.new()
    h.team = team
    h.global_position = pos
    return h

## Walks hero along vel for n ticks (simple integrator, no world collision), resolving each tick.
func _walk(s: SpawnRooms, h: FakeHero, vel: Vector3, n: int) -> void:
    for i in n:
        h.velocity = vel
        h.global_position += h.velocity * SpawnRooms.TICK
        s.step([h])

func test_built_on_both_maps() -> void:
    for f in MAPS:
        for lq in [false, true]:
            var m := MapLoader.build("res://src/maps/" + f, {"low_quality": lq})
            var s: SpawnRooms = m.get_node_or_null("SpawnRooms")
            check(s != null, "%s lq=%s has SpawnRooms" % [f, lq])
            if s == null:
                m.free()
                continue
            check(s.teams().has(0) and s.teams().has(1), "%s protects both teams" % f)
            check(s.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s barriers add no physics bodies" % f)
            for t in [0, 1]:
                var vis := s.get_node_or_null("barriers_team%d" % t)
                check(vis != null and int(vis.get_meta("panel_count")) >= 3, "%s team %d barrier visual" % [f, t])
            m.free()
    # arena01 stays FFA for core (no team-0 spawn_rooms meta -> GameConfig.allies_for == 0)
    var m1 := MapLoader.build("res://src/maps/arena01.json")
    check((m1.get_meta("spawn_rooms") as Dictionary).is_empty(), "arena01 spawn_rooms meta still empty")
    m1.free()

func test_every_spawn_inside_own_protection() -> void:
    for f in MAPS:
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        var s := _rooms(f)
        var inside := 0
        for t in d.spawns:
            for p in d.spawns[t]:
                var pos := Vector3(p[0], p[1], p[2])
                var o := s.owner_at(pos)
                check(o == -1 or o == int(t), "%s spawn %s not in an enemy volume" % [f, pos])
                if o == int(t):
                    inside += 1
        # arena02: all 10; arena01: all but the central platform spawn
        check(inside >= (10 if f == "arena02.json" else 3), "%s spawns protected: %d" % [f, inside])
        s.free()

func test_enemy_blocked_arena02_door() -> void:
    var s := _rooms("arena02.json")
    var e := _hero(1, Vector3(0, 0.2, 18))   # team 1 walks into team 0's room through the door
    _walk(s, e, Vector3(0, 0, 6), 120)
    check(e.global_position.z < 21.0 - 0.4 + 0.02, "enemy stopped at door: z=%.3f" % e.global_position.z)
    check(e.velocity.z <= 0.0, "inward velocity zeroed")
    check(not s.in_team_volume(0, e.global_position), "enemy not inside the room")
    # dash-speed (30 m/s) attempt also blocked
    var d := _hero(1, Vector3(1, 0.2, 18))
    _walk(s, d, Vector3(0, 0, 30), 30)
    check(d.global_position.z < 21.0, "fast enemy stopped: z=%.3f" % d.global_position.z)
    # back gap flank entrance blocked too
    var g := _hero(1, Vector3(12, 0.2, 31.25))
    _walk(s, g, Vector3(-6, 0, 0), 120)
    check(g.global_position.x > 9.0 + 0.4 - 0.02, "enemy stopped at back gap: x=%.3f" % g.global_position.x)
    s.free()

func test_enemy_blocked_both_teams_both_maps() -> void:
    # Every enemy volume repels every opposing hero placed at its centre, onto a point outside all enemy volumes.
    for f in MAPS:
        var s := _rooms(f)
        for v in s.volumes:
            var enemy := 1 - int(v.team)
            var c: Vector3 = v.aabb.get_center()
            c.y = v.aabb.position.y + 0.2
            var r := s.resolve(enemy, c, Vector3(0, 0, 3), c)
            check(int(r[2]) == v.team, "%s %s team %d pushes enemy" % [f, v.kind, v.team])
            check(s.owner_at(r[0], 0.39) != v.team, "%s pushed out of team %d volume: %s" % [f, v.team, r[0]])
        s.free()

func test_ally_passes() -> void:
    var s := _rooms("arena02.json")
    var a := _hero(0, Vector3(0, 0.2, 18))
    _walk(s, a, Vector3(0, 0, 6), 90)   # 9 m: through the door into the room
    near(a.global_position.z, 27.0, 0.001, "owner walks straight in")
    check(s.in_own_room(a), "owner inside own room")
    _walk(s, a, Vector3(0, 0, -6), 120)   # and out again
    near(a.global_position.z, 15.0, 0.001, "owner walks straight out")
    var s1 := _rooms("arena01.json")
    var p := _hero(0, Vector3(0, 0.2, 10))
    _walk(s1, p, Vector3(0, 0, 5), 60)
    near(p.global_position.z, 15.0, 0.001, "arena01 player walks into own area")
    var b := _hero(1, Vector3(0, 0.2, 10))
    _walk(s1, b, Vector3(0, 0, 5), 60)
    check(b.global_position.z < 13.0 - 0.38, "arena01 bot kept out of player area: z=%.3f" % b.global_position.z)
    s.free()
    s1.free()

func test_client_does_not_push() -> void:
    var s := _rooms("arena02.json")
    s.authority_override = 0
    var e := _hero(1, Vector3(0, 0.2, 25))
    s.step([e])
    near(e.global_position.z, 25.0, 0.0001, "client step is a no-op (host decides)")
    var r := s.resolve(1, Vector3(0, 0.2, 21.5), Vector3(0, 0, 5), Vector3(0, 0.2, 20.0))
    check(int(r[2]) == 0 and r[0].z < 20.7, "client prediction uses the same pure rule")
    s.free()

func test_shield_hook() -> void:
    var s := _rooms("arena02.json")
    var evs: Array = []
    s.spawn_shield_changed.connect(func(e): evs.append([e.active, e.reason]))
    var h := _hero(0, Vector3(0, 0.2, 27))
    s.step([h])
    check(s.is_shielded(h), "fresh spawn in own room is shielded")
    check(evs.size() == 1 and evs[0] == [true, "spawn"], "shield start event: %s" % [evs])
    near(s.shield_left(h), 2.0 - SpawnRooms.TICK, 0.001, "shield_left counts down from spawn_shield")
    for i in 30:
        s.step([h])
    check(s.is_shielded(h), "still shielded inside room after 0.5 s")
    for i in 100:
        s.step([h])
    check(not s.is_shielded(h), "shield times out after 2 s")
    check(evs.back() == [false, "timeout"], "timeout event: %s" % [evs])
    # dies -> respawns: new shield; leaving the room ends it early
    h.dead = true
    s.step([h])
    h.dead = false
    s.step([h])
    check(s.is_shielded(h), "respawn re-grants shield")
    _walk(s, h, Vector3(0, 0, -8), 60)   # out of the door (z 27 -> 19)
    check(not s.is_shielded(h), "leaving own room ends shield")
    check(evs.back() == [false, "left_room"], "left_room event: %s" % [evs])
    # died while shielded
    var k := _hero(1, Vector3(0, 0.2, -27))
    s.step([k])
    k.dead = true
    s.step([k])
    check(evs.back() == [false, "died"] and not s.is_shielded(k), "death ends shield")
    # spawn outside any room (arena01 platform spawn): timer only
    var s1 := _rooms("arena01.json")
    var q := _hero(1, Vector3(0, 3.2, -10))
    s1.step([q])
    _walk(s1, q, Vector3(3, 0, 0), 60)
    check(s1.is_shielded(q), "unprotected spawn keeps the timed shield while moving")
    # own-room signal
    var inside: Array = []
    s1.own_room_changed.connect(func(e): inside.append(e.inside))
    var p := _hero(0, Vector3(0, 0.2, 15))
    s1.step([p])
    _walk(s1, p, Vector3(0, 0, -6), 60)
    check(inside == [true, false], "own_room_changed enter/leave: %s" % [inside])
    s.free()
    s1.free()

func _scripted_run(f: String) -> Array:
    var s := _rooms(f)
    var hs: Array = []
    for i in 6:
        hs.append(_hero(i % 2, Vector3(-6 + i * 2.3, 0.2, 0)))
    var out: Array = []
    for t in 600:
        for i in hs.size():
            var h: FakeHero = hs[i]
            var ang := float(t) * 0.013 * float(i + 1) + float(i)
            h.velocity = Vector3(cos(ang), 0, sin(ang)) * 9.0 + Vector3(0, 0, 4.0 if h.team == 1 else -4.0)
            h.global_position += h.velocity * SpawnRooms.TICK
            if t % 97 == i:
                h.dead = not h.dead
        s.step(hs)
        for h in hs:
            out.append(h.global_position)
            out.append(s.is_shielded(h))
    s.free()
    return out

func test_deterministic() -> void:
    for f in MAPS:
        var a := _scripted_run(f)
        var b := _scripted_run(f)
        check(a == b, "%s identical run twice" % f)
        var s1 := _rooms(f)
        var s2 := _rooms(f)
        check(str(s1.volumes) == str(s2.volumes), "%s same volumes every build" % f)
        s1.free()
        s2.free()

func test_team_reachability() -> void:
    # With enemy keep-out volumes blocked: each team still reaches all its own spawns, every zone and the other
    # team's door; no enemy can reach a protected spawn.
    for f in MAPS:
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        var s := _rooms(f)
        var g := MapGrid.from_def(d)
        for t in d.spawns:
            var team := int(t)
            var blocked := func(p: Vector3) -> bool:
                var o := s.owner_at(p + Vector3(0, 0.1, 0), 0.4)
                return o >= 0 and o != team
            for sp in d.spawns[t]:
                var n := g.node_at(Vector3(sp[0], sp[1], sp[2]))
                check(n >= 0, "%s spawn %s on ground" % [f, sp])
                if n < 0:
                    continue
                var r := g.flood(n, blocked)
                for sp2 in d.spawns[t]:
                    check(r.has(g.node_at(Vector3(sp2[0], sp2[1], sp2[2]))), "%s team %d spawn %s reaches own spawn %s" % [f, team, sp, sp2])
                for z in d.get("zones", []):
                    check(MapGrid.reaches_box(r, g, Vector3(z.pos[0], z.pos[1], z.pos[2]), Vector3(z.size[0], z.size[1], z.size[2])),
                        "%s team %d spawn %s reaches zone" % [f, team, sp])
                for t2 in d.spawns:
                    if int(t2) == team:
                        continue
                    for sp2 in d.spawns[t2]:
                        var e := Vector3(sp2[0], sp2[1], sp2[2])
                        if s.owner_at(e) == int(t2):
                            check(not r.has(g.node_at(e)), "%s team %d cannot reach protected enemy spawn %s" % [f, team, e])
                        else:
                            check(r.has(g.node_at(e)), "%s team %d reaches unprotected enemy spawn %s" % [f, team, e])
        s.free()
