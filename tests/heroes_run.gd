extends SceneTree
## Heroes/abilities test runner (until these suites are registered in tests/run_tests.gd):
## godot --headless --path . -s tests/heroes_run.gd
const SUITES := ["res://tests/heroes_test_defs.gd", "res://tests/abilities_test_projectile.gd"]
var passed := 0
var failed := 0
var sim

func _initialize() -> void:
    print("== heroes/abilities unit tests ==")
    for path in SUITES:
        var s = load(path).new()
        for m in s.get_method_list():
            var n: String = m.name
            if not n.begins_with("test_"):
                continue
            s.errors = []
            s.call(n)
            if s.errors.is_empty():
                passed += 1
                print("  ok    %s::%s" % [path.get_file(), n])
            else:
                failed += 1
                print("  FAIL  %s::%s  %s" % [path.get_file(), n, s.errors])
    print("== abilities integration (Jolt, 60 Hz) ==")
    sim = load("res://tests/abilities_sim.gd").new()
    root.add_child(sim)

func _process(_dt: float) -> bool:
    if sim == null or not sim.done:
        return false
    for r in sim.results:
        if r[1]:
            passed += 1
        else:
            failed += 1
        print("  %s  sim::%s  %s" % ["ok  " if r[1] else "FAIL", r[0], r[2]])
    print("HEROES RESULT: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)
    sim = null
    return false
