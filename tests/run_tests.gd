extends SceneTree
## Headless test runner: godot --headless --path . -s tests/run_tests.gd
## Auto-discovers (see tests/README.md):
##   unit suites:  tests/test_*.gd and tests/<owner>_*test*.gd (not *run*)  -> methods test_*
##   integration:  tests/physics_driver.gd, tests/<owner>_*_sim.gd, tests/<owner>_*_driver.gd -> Node with `done`, `results`
## Integration scenes run one at a time, each in its own SubViewport world.
var passed := 0
var failed := 0
var sims: Array = []
var current = null
var holder: SubViewport

func _discover() -> Dictionary:
    var units: Array = []
    var integ: Array = ["res://tests/physics_driver.gd"]
    for f in DirAccess.get_files_at("res://tests"):
        if not f.ends_with(".gd") or f == "test_base.gd":
            continue
        if f.contains("run"):
            continue   # per-branch runners (heroes_run.gd, ai_run_tests.gd, ...) are not suites
        if f.begins_with("test_") or f.contains("_test"):
            units.append("res://tests/" + f)
        elif f.ends_with("_sim.gd") or (f.ends_with("_driver.gd") and f != "physics_driver.gd"):
            integ.append("res://tests/" + f)
    units.sort()
    return {"units": units, "integ": integ}

func _initialize() -> void:
    var d := _discover()
    print("== unit tests (%d suites) ==" % d.units.size())
    for path in d.units:
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
    sims = d.integ
    _next()

func _next() -> void:
    if holder:
        holder.queue_free()
        holder = null
    current = null
    if sims.is_empty():
        return
    var path: String = sims.pop_front()
    print("== integration: %s (Jolt, 60 Hz) ==" % path.get_file())
    holder = SubViewport.new()
    holder.own_world_3d = true
    holder.size = Vector2i(2, 2)
    root.add_child(holder)
    current = load(path).new()
    current.set_meta("label", path.get_file().get_basename())
    holder.add_child(current)

func _process(_dt: float) -> bool:
    if current != null and current.done:
        for r in current.results:
            if r[1]:
                passed += 1
            else:
                failed += 1
            print("  %s  %s::%s  %s" % ["ok  " if r[1] else "FAIL", current.get_meta("label"), r[0], r[2]])
        _next()
        if current == null:
            print("RESULT: %d passed, %d failed" % [passed, failed])
            quit(0 if failed == 0 else 1)
    return false
