extends "res://tests/test_base.gd"
## Capture zone logic (src/maps/capture_zone.gd).

func _zone(extra := {}) -> CaptureZone:
    var d := {"id": "A", "pos": [0, 1, 0], "size": [10, 2, 10], "capture_time": 4.0,
        "player_scale": [1.0, 1.5, 2.0], "decay_rate": 0.25}
    d.merge(extra, true)
    return CaptureZone.from_def(d)

func _run(z: CaptureZone, secs: float, counts: Dictionary) -> void:
    for i in int(round(secs * 60.0)):
        z.step(1.0 / 60.0, counts)

func test_from_arena02_data() -> void:
    var m := MapLoader.build("res://src/maps/arena02.json")
    var zs := CaptureZone.from_map(m)
    check(zs.size() == 1, "arena02 has 1 capture zone")
    var z: CaptureZone = zs[0]
    check(z.zone_id == "A" and z.owner_team == CaptureZone.NEUTRAL, "starts neutral")
    near(z.capture_time, 8.0, 0.001, "capture_time from JSON")
    check(z.aabb.has_point(Vector3(0, 1.2, 0)), "aabb covers dais")
    z.free()
    m.free()
    var m1 := MapLoader.build("res://src/maps/arena01.json")
    check(CaptureZone.from_map(m1).is_empty(), "arena01 has no zones")
    m1.free()

func test_single_capture() -> void:
    var z := _zone()
    var evs: Array = []
    z.captured.connect(func(ev): evs.append(ev))
    _run(z, 2.0, {0: 1})
    near(z.progress, 0.5, 0.02, "half after 2 s solo")
    check(z.capturing_team == 0 and z.owner_team == -1, "capturing, not owned")
    _run(z, 2.1, {0: 1})
    check(z.owner_team == 0, "owned after 4 s")
    check(evs.size() == 1 and evs[0].team == 0 and evs[0].previous == -1, "captured event")
    z.free()

func test_scaling_and_cap() -> void:
    var z := _zone()
    near(z.rate_for(1), 0.25, 1e-6, "1 player")
    near(z.rate_for(2), 0.375, 1e-6, "2 players")
    near(z.rate_for(3), 0.5, 1e-6, "3 players")
    near(z.rate_for(6), 0.5, 1e-6, "capped at 3+")
    near(z.rate_for(0), 0.0, 1e-6, "nobody")
    z.free()

func test_contested_pauses() -> void:
    var z := _zone()
    var flips: Array = []
    z.contested_changed.connect(func(ev): flips.append(ev.contested))
    _run(z, 1.0, {0: 2})
    var p := z.progress
    _run(z, 3.0, {0: 2, 1: 1})
    check(z.contested, "contested")
    near(z.progress, p, 1e-6, "progress paused")
    _run(z, 0.1, {0: 2, 1: 0})
    check(not z.contested and flips == [true, false], "contest ends: %s" % [flips])
    z.free()

func test_decay_when_empty() -> void:
    var z := _zone()
    _run(z, 2.0, {0: 1})
    _run(z, 1.0, {})
    near(z.progress, 0.25, 0.02, "decays 0.25/s")
    _run(z, 5.0, {})
    check(z.progress == 0.0 and z.capturing_team == -1, "fully decayed back to neutral progress")
    z.free()

func test_enemy_must_revert_first() -> void:
    var z := _zone()
    _run(z, 2.0, {0: 1})
    _run(z, 1.0, {1: 1})
    near(z.progress, 0.25, 0.02, "team 1 undoes team 0 progress first")
    check(z.capturing_team == 0, "still team 0's progress")
    _run(z, 1.5, {1: 1})
    check(z.capturing_team == 1, "now team 1 capturing")
    z.free()

func test_flip_owned_zone_and_owner_defends() -> void:
    var z := _zone()
    _run(z, 4.1, {0: 1})
    _run(z, 2.0, {1: 1})
    check(z.capturing_team == 1 and z.progress > 0.4, "enemy capturing owned zone")
    _run(z, 1.0, {0: 1})
    near(z.progress, 0.25, 0.03, "owner reverts enemy progress")
    _run(z, 1.5, {0: 1})
    check(z.progress == 0.0 and z.owner_team == 0, "owner kept")
    var evs: Array = []
    z.captured.connect(func(ev): evs.append(ev))
    _run(z, 4.1, {1: 1})
    check(z.owner_team == 1 and evs.size() == 1 and evs[0].previous == 0, "flipped to team 1")
    z.free()

func test_state_changed_events() -> void:
    var z := _zone()
    var n := [0]
    z.state_changed.connect(func(_ev): n[0] += 1)
    _run(z, 1.0, {})
    check(n[0] == 0, "no events while idle")
    _run(z, 0.5, {0: 1})
    check(n[0] > 0, "events while capturing")
    var s := z.state()
    check(s.zone == "A" and s.has("progress") and s.has("owner") and s.has("contested"), "state shape")
    z.free()

class FakeHero:
    var team: int
    var dead: bool
    var global_position: Vector3
    func _init(t: int, p: Vector3, d := false) -> void:
        team = t
        global_position = p
        dead = d

func test_count_inside_alive_only() -> void:
    var z := _zone()
    var hs := [FakeHero.new(0, Vector3(1, 0, 1)), FakeHero.new(0, Vector3(2, 0.5, -3)),
        FakeHero.new(1, Vector3(0, 0, 0), true), FakeHero.new(1, Vector3(20, 0, 0)),
        FakeHero.new(1, Vector3(0, 6, 0))]
    var c := z.count(hs)
    check(c == {0: 2}, "two team-0 inside, dead/outside/above ignored: %s" % [c])
    z.free()
