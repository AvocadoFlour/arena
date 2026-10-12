extends SceneTree
## UI test runner: godot --headless --path . -s tests/ui_run_tests.gd
## (separate because tests/run_tests.gd SUITES is lead-owned; see docs/requests/ui.md)
var _done := false

func _process(_dt: float) -> bool:
    if _done:
        return false
    _done = true   # first frame: autoloads (Actions/Settings) are ready
    var p := 0
    var f := 0
    var s = load("res://tests/ui_test.gd").new()
    s.tree = self
    for m in s.get_method_list():
        if not m.name.begins_with("test_"):
            continue
        s.errors = []
        s.call(m.name)
        if s.errors.is_empty():
            p += 1
            print("  ok    ui_test.gd::%s" % m.name)
        else:
            f += 1
            print("  FAIL  ui_test.gd::%s  %s" % [m.name, s.errors])
    print("UI RESULT: %d passed, %d failed" % [p, f])
    quit(0 if f == 0 else 1)
    return false
