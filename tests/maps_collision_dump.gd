extends SceneTree
## Writes collision signatures of every map to res://tests/maps_collision_golden.json (tooling, not a suite):
## godot --headless --path . -s tests/maps_collision_dump.gd
func _initialize() -> void:
    var out := {}
    for f in DirAccess.get_files_at("res://src/maps"):
        if f.ends_with(".json"):
            var m := MapLoader.build("res://src/maps/" + f)
            out[f] = load("res://tests/maps_visual_test.gd").signature(m)
            m.free()
    var fa := FileAccess.open(OS.get_environment("OUT") if OS.has_environment("OUT") else "res://tests/maps_collision_golden.json", FileAccess.WRITE)
    fa.store_string(JSON.stringify(out, "  ", true))
    fa.close()
    quit()
