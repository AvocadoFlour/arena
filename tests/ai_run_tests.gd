extends SceneTree
## AI test runner: godot --headless --path . -s tests/ai_run_tests.gd
## (Requested to be folded into tests/run_tests.gd SUITES, see docs/requests/ai.md.)
const SUITES := ["res://tests/ai_unit_tests.gd"]
const DRIVERS := ["res://tests/ai_nav_driver.gd", "res://tests/ai_team_driver.gd", "res://tests/ai_melee_driver.gd", "res://tests/ai_support_driver.gd"]
var passed := 0
var failed := 0
var driver

func _initialize() -> void:
    print("== ai unit tests ==")
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
    print("== ai integration (navmesh, real map) ==")
    _next()

var _di := 0
func _next() -> void:
    driver = load(DRIVERS[_di]).new()
    _di += 1
    root.add_child(driver)

func _process(_dt: float) -> bool:
    if driver == null or not driver.done:
        return false
    for r in driver.results:
        if r[1]:
            passed += 1
        else:
            failed += 1
        print("  %s  ai::%s  %s" % ["ok  " if r[1] else "FAIL", r[0], r[2]])
    driver.queue_free()
    if _di < DRIVERS.size():
        _next()
        return false
    print("AI RESULT: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)
    driver = null
    return false
