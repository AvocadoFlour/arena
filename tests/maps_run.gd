extends SceneTree
## Standalone runner for map tests until tests/maps_test.gd is in run_tests.gd SUITES:
## godot --headless --path . -s tests/maps_run.gd
func _initialize() -> void:
    var s = load("res://tests/maps_test.gd").new()
    var p := 0
    var f := 0
    for m in s.get_method_list():
        var n: String = m.name
        if not n.begins_with("test_"):
            continue
        s.errors = []
        s.call(n)
        if s.errors.is_empty():
            p += 1
            print("  ok    maps_test.gd::%s" % n)
        else:
            f += 1
            print("  FAIL  maps_test.gd::%s  %s" % [n, s.errors])
    print("RESULT: %d passed, %d failed" % [p, f])
    quit(0 if f == 0 else 1)
