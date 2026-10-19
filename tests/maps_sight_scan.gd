extends SceneTree
## Tooling (not a suite): verbose sightline scan. godot --headless --path . -s tests/maps_sight_scan.gd
var sim
func _initialize() -> void:
    sim = load("res://tests/maps_sight_sim.gd").new()
    sim.verbose = true
    root.add_child(sim)
func _process(_d: float) -> bool:
    if sim == null:
        quit(1)
        return false
    if sim.done:
        for r in sim.results:
            print("  %s %s %s" % ["ok  " if r[1] else "FAIL", r[0], r[2]])
        quit()
    return false
