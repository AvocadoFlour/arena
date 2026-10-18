extends SceneTree
## Tooling (not a suite): verbose snag scan. godot --headless --path . -s tests/maps_snag_scan.gd -- --spacing=1.0
var sim
func _initialize() -> void:
    sim = load("res://tests/maps_snag_sim.gd").new()
    sim.verbose = true
    root.add_child(sim)
func _process(_d: float) -> bool:
    if sim == null:
        quit(1)
        return false
    if sim.done:
        var groups := {}
        for f in sim.findings:
            var k := "%s %s %s (%d,%d,%d)" % [f.map.get_basename(), f.cls, f.kind, round(f.pos.x), round(f.pos.y * 2.0) / 2.0, round(f.pos.z)]
            groups[k] = groups.get(k, "") + ("d%d:%.2f/%.2f " % [f.dir, f.dh, f.moved])
        var ks := groups.keys()
        ks.sort()
        for k in ks:
            print("  ", k, "  ", groups[k])
        for r in sim.results:
            print("  %s %s %s" % ["ok  " if r[1] else "FAIL", r[0], r[2]])
        quit()
    return false
