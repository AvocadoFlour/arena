extends "res://tests/test_base.gd"
## Toon restyle (queue item 1): flat toon materials + merged black outline hulls, data-driven.

const MAPS := ["arena01.json", "arena02.json"]

func _golden() -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://tests/maps_collision_golden.json"))

## The visual of block i: its merged "Blocks/blocks_<mat>_<s|n>" mesh, or its own MeshInstance3D (destructible).
static func block_mesh(m: Node, i: int, b: Dictionary) -> MeshInstance3D:
    var body: Node = m.get_node("%s_%02d" % [b.kind, i])
    if body.has_meta("mesh_group"):
        return m.get_node("Blocks/" + String(body.get_meta("mesh_group")))
    return body.find_children("*", "MeshInstance3D", false, false)[0]

func test_toon_materials_from_palette() -> void:
    for f in MAPS:
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        check(d.theme.get("toon", false) and float(d.theme.get("outline_width", 0)) > 0.0, "%s toon theme" % f)
        var m := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
        for i in d.blocks.size():
            var b: Dictionary = d.blocks[i]
            var mi: MeshInstance3D = block_mesh(m, i, b)
            var mat: Material = mi.material_override
            check(mat is ShaderMaterial and mat.shader == MapLoader.MAP_TOON, "%s block %d uses map toon shader" % [f, i])
            check(MapLoader.mat_color(mat) == Color(String(d.materials[b.mat].color)), "%s block %d colour from palette" % [f, i])
        var we: WorldEnvironment = m.find_children("*", "WorldEnvironment", false, false)[0]
        check(we.environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "%s linear tonemap (exact palette)" % f)
        m.free()

func test_outlines_merged_no_collision() -> void:
    for f in MAPS:
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        var m := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
        var ol := m.get_node_or_null("Outlines") as MeshInstance3D
        check(ol != null, "%s has Outlines" % f)
        if ol == null:
            m.free()
            continue
        check(ol.get_child_count() == 0 and ol.mesh.get_surface_count() == 1, "%s outlines = 1 mesh, 1 surface (1 draw call)" % f)
        var mat: StandardMaterial3D = ol.material_override
        check(mat.cull_mode == BaseMaterial3D.CULL_FRONT and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "%s inverted-hull material" % f)
        check(mat.albedo_color == Color(String(d.theme.outline_color)), "%s outline colour from data" % f)
        check(ol.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s outlines cast no shadow" % f)
        var blocks_outlined := 0
        for b in d.blocks:
            if d.materials[b.mat].get("outline", true):
                blocks_outlined += 1
        check(int(ol.get_meta("hull_count")) > blocks_outlined, "%s hulls for blocks (%d) + props: %d" % [f, blocks_outlined, ol.get_meta("hull_count")])
        check(_golden()[f] == load("res://tests/maps_visual_test.gd").signature(m), "%s collision identical with outlines" % f)
        m.free()

func test_outline_hull_encloses_block() -> void:
    var d := {"theme": {"outline_width": 0.1}, "blocks": [{"kind": "cover", "pos": [1, 2, 3], "size": [2, 2, 2]}]}
    var mi := MapLoader._outlines(d, d.theme, false)
    var bb: AABB = mi.mesh.get_aabb()
    check(bb.position.is_equal_approx(Vector3(-0.1, 0.9, 1.9)) and bb.size.is_equal_approx(Vector3(2.2, 2.2, 2.2)), "hull = block + width: %s" % bb)
    mi.free()
    var none := MapLoader._outlines({"blocks": [{"kind": "floor", "pos": [0, 0, 0], "size": [4, 0.02, 4]}]}, {"outline_width": 0.1}, false)
    check(none == null, "decal-thin blocks get no hull")

func test_low_quality_keeps_block_outlines_only() -> void:
    for f in MAPS:
        var hq := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
        var lq := MapLoader.build("res://src/maps/" + f, {"low_quality": true})
        var a: int = hq.get_node("Outlines").get_meta("hull_count")
        var b: int = lq.get_node("Outlines").get_meta("hull_count")
        check(b < a and b > 0, "%s low_quality: block hulls only (%d < %d)" % [f, b, a])
        check(lq.get_node_or_null("Props") == null, "%s low_quality: no props" % f)
        var sun: DirectionalLight3D = lq.find_children("*", "DirectionalLight3D", false, false)[0]
        check(not sun.shadow_enabled, "%s low_quality: no shadows" % f)
        check(_golden()[f] == load("res://tests/maps_visual_test.gd").signature(lq), "%s low_quality collision identical" % f)
        hq.free()
        lq.free()

func test_outlines_deterministic() -> void:
    for f in MAPS:
        var a := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
        var b := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
        var va = a.get_node("Outlines").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
        var vb = b.get_node("Outlines").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
        check(va == vb and va.size() > 0, "%s outline vertices identical across builds" % f)
        a.free()
        b.free()
