extends SceneTree
## Standalone runner for map suites: godot --headless --path . -s tests/maps_run.gd
## (run_tests.gd also auto-discovers tests/maps_*test*.gd.)
const SUITES := ["res://tests/maps_test.gd", "res://tests/maps_zone_test.gd"]
func _initialize() -> void:
    var p := 0
    var f := 0
    for path in SUITES:
        var s = load(path).new()
        for m in s.get_method_list():
            var n: String = m.name
            if not n.begins_with("test_"):
                continue
            s.errors = []
            s.call(n)
            if s.errors.is_empty():
                p += 1
                print("  ok    %s::%s" % [path.get_file(), n])
            else:
                f += 1
                print("  FAIL  %s::%s  %s" % [path.get_file(), n, s.errors])
    print("RESULT: %d passed, %d failed" % [p, f])
    quit(0 if f == 0 else 1)
