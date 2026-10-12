extends "res://tests/test_base.gd"

func _rules(with_zone: bool) -> MatchRules:
    var r := MatchRules.new()
    r.setup([Node.new()] if with_zone else [])
    return r

func test_ffa_without_zones() -> void:
    var r := _rules(false)
    check(r.mode == "ffa", "ffa when no zones")
    r.step(500.0, [])
    check(not r.ended, "ffa never ends")
    r.free()

func test_control_one_percent_per_second() -> void:
    var r := _rules(true)
    check(r.mode == "control", "control with zones")
    for i in 600:
        r.step(1.0 / 60.0, [0])
    near(r.scores[0], 10.0, 0.01, "10 s owned = 10 %")
    near(r.scores[1], 0.0, 0.001, "other team 0")
    r.step(5.0, [-1])
    near(r.scores[0], 10.0, 0.01, "neutral zone gives nothing")
    r.free()

func test_first_to_100_wins_once() -> void:
    var r := _rules(true)
    r.step(60.0, [1])
    r.step(30.0, [0])
    check(not r.ended, "not yet")
    r.step(41.0, [1])
    check(r.ended and r.winner == 1, "team 1 wins at 100 %")
    near(r.scores[1], 100.0, 0.001, "clamped")
    r.step(100.0, [0])
    near(r.scores[0], 30.0, 0.001, "no scoring after end")
    r.free()
