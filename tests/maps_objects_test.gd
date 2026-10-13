extends "res://tests/test_base.gd"
## Health packs + jump pads (queue item 3).

const MAPS := ["arena01.json", "arena02.json"]

class FakeHero:
    var team := 0
    var dead := false
    var global_position := Vector3.ZERO
    var velocity := Vector3.ZERO
    var hp := 100.0
    var max_hp := 200.0
    func heal(a: float) -> float:
        if dead:
            return 0.0
        var got := minf(a, max_hp - hp)
        hp += got
        return got

func _objs(f: String, auth := 1) -> MapObjects:
    var o := MapObjects.from_def(MapLoader.load_def("res://src/maps/" + f))
    o.authority_override = auth
    return o

func _hero(pos: Vector3, hp := 100.0) -> FakeHero:
    var h := FakeHero.new()
    h.global_position = pos
    h.hp = hp
    return h

func test_objects_from_data() -> void:
    for f in MAPS:
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        var m := MapLoader.build("res://src/maps/" + f, {"low_quality": true})
        var o: MapObjects = m.get_node("Objects")
        check(o.pickups.size() == d.pickups.size() and o.pickups.size() >= 2, "%s pickups built" % f)
        check(o.pads.size() == d.jump_pads.size() and o.pads.size() >= 1, "%s pads built (also in low quality)" % f)
        for i in o.pickups.size():
            check(o.pickups[i].id == i and o.pickups[i].active, "%s pickup %d id/active" % [f, i])
        check(o.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s objects add no physics bodies" % f)
        m.free()

func test_golden_unchanged_by_objects() -> void:
    var g = JSON.parse_string(FileAccess.get_file_as_string("res://tests/maps_collision_golden.json"))
    for f in MAPS:
        var m := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
        check(load("res://tests/maps_visual_test.gd").signature(m) == g[f], "%s collision identical" % f)
        m.free()

func test_pickup_heal_consume_respawn() -> void:
    var o := _objs("arena02.json")
    var p: Dictionary = o.pickups[0]
    var h := _hero(p.pos + Vector3(0.3, 0, 0), 100.0)
    var taken: Array = []
    var back: Array = []
    o.pickup_taken.connect(func(ev): taken.append(ev))
    o.pickup_respawned.connect(func(ev): back.append(ev))
    o.step([h])
    near(h.hp, 150.0, 0.001, "healed 50")
    check(not p.active and taken.size() == 1 and taken[0].id == 0, "consumed")
    o.step([h])
    near(h.hp, 150.0, 0.001, "inactive pack doesn't heal")
    for i in int(15.0 * 60.0) - 2:
        o.step([])
    check(not p.active, "still down just before 15 s")
    o.step([])
    o.step([])
    check(p.active and back.size() == 1, "respawned at 15 s (900 ticks)")
    o.free()

func test_pickup_rules() -> void:
    var o := _objs("arena01.json")
    var p: Dictionary = o.pickups[0]
    var full := _hero(p.pos, 200.0)
    o.step([full])
    check(p.active, "full-HP hero does not consume")
    var dead := _hero(p.pos, 10.0)
    dead.dead = true
    o.step([dead])
    check(p.active, "dead hero ignored")
    var far := _hero(p.pos + Vector3(2, 0, 0), 10.0)
    o.step([far])
    check(p.active, "outside radius ignored")
    var a := _hero(p.pos, 10.0)
    var b := _hero(p.pos, 10.0)
    o.step([a, b])
    check(not p.active and a.hp == 60.0 and b.hp == 10.0, "one pack heals one hero (first in order)")
    o.free()

func test_client_never_decides() -> void:
    var o := _objs("arena02.json", 0)
    var h := _hero(o.pickups[0].pos, 10.0)
    var pad_h := _hero(o.pads[0].pos)
    o.step([h, pad_h])
    check(o.pickups[0].active and h.hp == 10.0, "client: no pickup")
    check(pad_h.velocity == Vector3.ZERO, "client: no launch")
    o.free()

func test_client_apply_and_late_join() -> void:
    var host := _objs("arena02.json", 1)
    var client := _objs("arena02.json", 0)
    host.pickup_taken.connect(func(ev): client.apply_pickup(ev.id, false, host.pickups[ev.id].left))
    host.step([_hero(host.pickups[1].pos, 10.0)])
    check(not client.pickups[1].active and not client.pickups[1].node.visible, "client hid taken pack")
    for i in 120:
        host.step([])
    var late := _objs("arena02.json", 0)
    late.apply_state(host.state())
    check(late.state() == host.state(), "late join state matches host: %s" % [late.state()])
    check(not late.pickups[1].node.visible and late.pickups[0].node.visible, "late join visuals")
    check(client.apply_pickup(99, true) == false, "unknown id ignored")
    host.free()
    client.free()
    late.free()

func test_pad_launch_rearm_and_prediction() -> void:
    var o := _objs("arena02.json")
    var pad: Dictionary = o.pads[0]
    var h := _hero(pad.pos + Vector3(0, 0.05, 0))
    var evs: Array = []
    o.pad_launched.connect(func(ev): evs.append(ev))
    var predicted := o.predict_pad(h.global_position, h.velocity)
    o.step([h])
    check(h.velocity == pad.launch and evs.size() == 1, "host launches with data velocity")
    check(predicted == h.velocity, "client prediction == host result")
    h.velocity = Vector3.ZERO
    o.step([h])
    check(evs.size() == 1, "re-arm: no double launch within 0.5 s")
    for i in 31:
        o.step([h])
    check(evs.size() == 2, "re-armed after 0.5 s")
    var rising := _hero(pad.pos)
    rising.velocity = Vector3(0, 5, 0)
    o.step([rising])
    check(rising.velocity == Vector3(0, 5, 0), "rising hero not re-launched")
    check(o.predict_pad(pad.pos + Vector3(10, 0, 0), Vector3.ONE) == Vector3.ONE, "prediction off-pad unchanged")
    o.free()

func test_pads_reach_their_level() -> void:
    # apex of the launch (gravity 22, all heroes) must clear the target ledge with margin
    var targets := {"arena01.json": [3.0], "arena02.json": [4.0, 4.0]}
    for f in MAPS:
        var o := _objs(f)
        for i in o.pads.size():
            var v: Vector3 = o.pads[i].launch
            var apex: float = o.pads[i].pos.y + v.y * v.y / (2.0 * 22.0)
            check(apex >= targets[f][i] + 0.5, "%s pad %d apex %.2f >= ledge %.1f + 0.5" % [f, i, apex, targets[f][i]])
        o.free()

func test_objects_reachable_from_spawns() -> void:
    for f in MAPS:
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        var g := MapGrid.from_def(d)
        var s = d.spawns["0"][0]
        var r := g.flood(g.node_at(Vector3(s[0], s[1], s[2])))
        for p in d.pickups:
            var n := g.node_at(Vector3(p.pos[0], p.pos[1] + 0.1, p.pos[2]))
            check(n >= 0 and r.has(n), "%s pickup %s reachable" % [f, p.pos])
        for p in d.jump_pads:
            var n := g.node_at(Vector3(p.pos[0], p.pos[1] + 0.1, p.pos[2]))
            check(n >= 0 and r.has(n), "%s pad %s reachable" % [f, p.pos])

func test_ids_deterministic() -> void:
    for f in MAPS:
        var a := _objs(f)
        var b := _objs(f)
        var pa: Array = []
        var pb: Array = []
        for p in a.pickups: pa.append([p.id, p.pos, p.amount, p.respawn])
        for p in b.pickups: pb.append([p.id, p.pos, p.amount, p.respawn])
        for p in a.pads: pa.append([p.id, p.pos, p.launch])
        for p in b.pads: pb.append([p.id, p.pos, p.launch])
        check(pa == pb, "%s ids identical across builds" % f)
        a.free()
        b.free()
