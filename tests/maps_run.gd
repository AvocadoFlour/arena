extends SceneTree
## Standalone runner for map suites: godot --headless --path . -s tests/maps_run.gd
## Discovers tests/maps_*test*.gd (same suites run_tests.gd picks up). Fails (exit 1) when:
##   - a suite fails to load/parse/compile (as run_tests.gd),
##   - a test records errors via check()/near(),
##   - a test raises a script/engine error while running (captured with a Logger, since
##     GDScript has no try/catch and an erroring call just returns early).
## Runs on the first frame so autoloads (Settings, GameConfig, ...) are ready, like run_tests.gd.

class ErrorTap extends Logger:
    var count := 0
    var last := ""
    var _m := Mutex.new()
    func _log_error(function: String, file: String, line: int, code: String, rationale: String,
            _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
        if error_type == Logger.ERROR_TYPE_WARNING:
            return
        _m.lock()
        count += 1
        last = "%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function]
        _m.unlock()
    func _log_message(_message: String, _error: bool) -> void:
        pass

var passed := 0
var failed := 0
var _started := false
var tap := ErrorTap.new()

func _suites() -> Array:
    var out: Array = []
    for f in DirAccess.get_files_at("res://tests"):
        if f.begins_with("maps_") and f.ends_with(".gd") and f.contains("test") and not f.contains("run"):
            out.append("res://tests/" + f)
    out.sort()
    return out

func _initialize() -> void:
    OS.add_logger(tap)

func _process(_dt: float) -> bool:
    if _started:
        return false
    _started = true
    for path in _suites():
        var before := tap.count
        var scr = load(path)
        if scr == null or not scr.can_instantiate():
            failed += 1
            print("  FAIL  %s  (script failed to load/parse)" % path.get_file())
            continue
        var s = scr.new()
        if tap.count != before:
            failed += 1
            print("  FAIL  %s  (errors while loading: %s)" % [path.get_file(), tap.last])
            continue
        for m in s.get_method_list():
            var n: String = m.name
            if not n.begins_with("test_"):
                continue
            s.errors = []
            var e0 := tap.count
            s.call(n)
            var raised := tap.count - e0
            if s.errors.is_empty() and raised == 0:
                passed += 1
                print("  ok    %s::%s" % [path.get_file(), n])
            else:
                failed += 1
                var why: Array = s.errors.duplicate()
                if raised > 0:
                    why.append("%d script/engine error(s), last: %s" % [raised, tap.last])
                print("  FAIL  %s::%s  %s" % [path.get_file(), n, why])
    print("RESULT: %d passed, %d failed" % [passed, failed])
    OS.remove_logger(tap)
    quit(0 if failed == 0 else 1)
    return false
