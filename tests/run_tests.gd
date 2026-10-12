extends SceneTree
## Headless test runner: godot --headless --path . -s tests/run_tests.gd
const SUITES := ["res://tests/test_combat.gd", "res://tests/test_hitmath.gd", "res://tests/test_motion.gd"]
var passed := 0
var failed := 0
var driver

func _initialize() -> void:
    print("== unit tests ==")
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
    print("== physics integration (Jolt, 60 Hz) ==")
    driver = load("res://tests/physics_driver.gd").new()
    root.add_child(driver)

func _process(_dt: float) -> bool:
    if driver == null or not driver.done:
        return false
    for r in driver.results:
        if r[1]:
            passed += 1
        else:
            failed += 1
        print("  %s  physics::%s  %s" % ["ok  " if r[1] else "FAIL", r[0], r[2]])
    print("RESULT: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)
    driver = null
    return false
