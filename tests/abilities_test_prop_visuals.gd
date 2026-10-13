extends "res://tests/test_base.gd"
## Remote (net-prop) path: core Net.make_prop with the heroes' "visual" hook builds the toon note glyph /
## crystal wall instead of plain sphere/box; walls keep core's collision box of the exact size.
const VIS := "res://src/abilities/prop_visuals.gd"

func _def(hero: String, slot: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % hero)).abilities[slot]

func test_defs_use_hook() -> void:
    check(_def("twin_tails", "ability2").get("visual") == VIS, "staccato visual")
    check(_def("cob", "ability2").get("visual") == VIS, "geode visual")

func test_remote_shot_is_note() -> void:
    var n: Node3D = Net.make_prop("shot", Vector3.ONE * 0.18, Color("#d8ecff"), VIS)
    check(n.name == "NoteGlyph", "note glyph, got %s" % n.name)
    check(not (n is MeshInstance3D) and n.find_children("*", "MeshInstance3D", true, false).size() >= 3, "glyph parts, not a plain sphere")
    check(n.find_children("*", "CollisionObject3D", true, false).is_empty(), "shot has no collision")
    n.free()

func test_remote_wall_is_crystals_with_same_collision() -> void:
    var size := Vector3(4.5, 2.6, 0.35)
    var n: Node3D = Net.make_prop("wall", size, Color("#b080ff"), VIS)
    check(n is StaticBody3D, "wall stays solid")
    var shapes := n.find_children("*", "CollisionShape3D", true, false)
    check(shapes.size() == 1 and (shapes[0].shape as BoxShape3D).size == size, "collision box unchanged")
    var crystals := n.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.mesh is CylinderMesh)
    check(crystals.size() >= 8, "crystals=%d" % crystals.size())
    var opaque_box := n.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.mesh is BoxMesh and (m.material_override == null or m.material_override.albedo_color.a > 0.3))
    check(opaque_box.is_empty(), "plain box hidden/faint")
    var a := Net.make_prop("wall", size, Color("#b080ff"), VIS)
    var same := true
    var ca := a.find_children("*", "MeshInstance3D", true, false)
    var cb := n.find_children("*", "MeshInstance3D", true, false)
    for i in ca.size():
        same = same and ca[i].transform.is_equal_approx(cb[i].transform)
    check(same and ca.size() == cb.size(), "deterministic layout (all peers match)")
    a.free()
    n.free()

func test_fallback_without_visual() -> void:
    var n: Node3D = Net.make_prop("wall", Vector3(2, 2, 0.3), Color.WHITE, "")
    check(n.find_children("*", "MeshInstance3D", true, false).any(func(m): return m.mesh is BoxMesh), "plain box fallback")
    n.free()
