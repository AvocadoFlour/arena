extends "res://tests/test_base.gd"
## Visual pass guard: collision must be exactly the map data, props must never collide.

## Every CollisionObject3D/CollisionShape3D under the map, as sorted strings (transform + box size).
static func signature(map: Node) -> Array:
    var out: Array = []
    for n in map.find_children("*", "CollisionShape3D", true, false):
        var cs: CollisionShape3D = n
        var body := cs.get_parent()
        var t: Transform3D = body.transform * cs.transform
        var sz: Vector3 = cs.shape.size if cs.shape is BoxShape3D else Vector3(-1, -1, -1)
        out.append("%s|%s|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|L%d" % [
            body.name, cs.shape.get_class(), t.origin.x, t.origin.y, t.origin.z,
            t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
            t.basis.z.x, t.basis.z.y, t.basis.z.z, sz.x, sz.y, sz.z, body.collision_layer])
    out.sort()
    return out

func _maps() -> Array:
    var out: Array = []
    for f in DirAccess.get_files_at("res://src/maps"):
        if f.ends_with(".json"):
            out.append(f)
    return out

func test_collision_matches_golden() -> void:
    var g = JSON.parse_string(FileAccess.get_file_as_string("res://tests/maps_collision_golden.json"))
    check(g is Dictionary, "golden loads")
    for f in ["arena01.json", "arena02.json"]:
        var m := MapLoader.build("res://src/maps/" + f)
        var sig := signature(m)
        check(g.has(f) and sig == g[f], "%s collision identical to pre-visual-pass golden" % f)
        m.free()

func test_collision_matches_data() -> void:
    for f in _maps():
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        var m := MapLoader.build("res://src/maps/" + f)
        var bodies := m.find_children("*", "CollisionObject3D", true, false)
        check(bodies.size() == d.blocks.size(), "%s: one body per block (%d vs %d)" % [f, bodies.size(), d.blocks.size()])
        for i in d.blocks.size():
            var b: Dictionary = d.blocks[i]
            var body := m.get_node_or_null("%s_%02d" % [b.kind, i]) as StaticBody3D
            check(body != null, "%s block %d exists" % [f, i])
            if body == null:
                continue
            var shapes := body.find_children("*", "CollisionShape3D", false, false)
            check(shapes.size() == 1, "%s block %d has one shape" % [f, i])
            var bs: BoxShape3D = shapes[0].shape
            check(bs.size.is_equal_approx(MapLoader._v(b.size)), "%s block %d size" % [f, i])
            check(body.position.is_equal_approx(MapLoader._v(b.pos)), "%s block %d pos" % [f, i])
            var rot: Vector3 = MapLoader._v(b.get("rot_deg", [0, 0, 0]))
            check(body.rotation_degrees.is_equal_approx(rot), "%s block %d rot" % [f, i])
        m.free()

func test_props_never_collide() -> void:
    for f in _maps():
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        var m := MapLoader.build("res://src/maps/" + f)
        var props := m.get_node_or_null("Props")
        var n: int = d.get("props", []).size()
        if n > 0:
            check(props != null and props.get_child_count() == n, "%s: %d props built" % [f, n])
            check(props.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s: props have no bodies" % f)
            check(props.find_children("*", "CollisionShape3D", true, false).is_empty(), "%s: props have no shapes" % f)
        m.free()

func test_visual_theme_applied() -> void:
    for f in ["arena01.json", "arena02.json"]:
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        check(d.has("theme") and d.has("materials") and d.get("props", []).size() > 20, "%s has theme/materials/props" % f)
        for b in d.blocks:
            check(d.materials.has(b.get("mat", "")), "%s block mat %s defined" % [f, b.get("mat", "")])
        for p in d.props:
            check(not p.has("mat") or d.materials.has(p.mat), "%s prop mat %s defined" % [f, p.get("mat", "")])
        var m := MapLoader.build("res://src/maps/" + f)
        var we: WorldEnvironment = m.find_children("*", "WorldEnvironment", false, false)[0]
        check(we.environment.fog_enabled, "%s fog on" % f)
        var sm: ProceduralSkyMaterial = we.environment.sky.sky_material
        check(sm.sky_top_color == Color(String(d.theme.sky_top)), "%s sky colour from data" % f)
        m.free()

func test_build_is_deterministic() -> void:
    for f in _maps():
        var a := MapLoader.build("res://src/maps/" + f)
        var b := MapLoader.build("res://src/maps/" + f)
        var pa: Array = []
        var pb: Array = []
        for n in a.find_children("*", "MeshInstance3D", true, false):
            pa.append([n.get_parent().name, n.transform, n.material_override.albedo_color, n.mesh.get_aabb()])
        for n in b.find_children("*", "MeshInstance3D", true, false):
            pb.append([n.get_parent().name, n.transform, n.material_override.albedo_color, n.mesh.get_aabb()])
        check(pa == pb, "%s builds identically twice" % f)
        a.free()
        b.free()

func test_unthemed_map_defaults() -> void:
    var tmp := "user://maps_plain_test.json"
    var fa := FileAccess.open(tmp, FileAccess.WRITE)
    fa.store_string(JSON.stringify({"name": "t", "spawns": {"0": [[0, 0, 0]], "1": [[1, 0, 1]]},
        "blocks": [{"kind": "floor", "pos": [0, -0.5, 0], "size": [4, 1, 4], "color": "#123456", "grid": true}]}))
    fa.close()
    var m := MapLoader.build(tmp)
    check(m.get_node_or_null("Props") == null, "no Props node without props")
    var mi: MeshInstance3D = m.get_node("floor_00").find_children("*", "MeshInstance3D", false, false)[0]
    check(mi.material_override.albedo_color == Color("#123456"), "legacy colour path")
    var we: WorldEnvironment = m.find_children("*", "WorldEnvironment", false, false)[0]
    check(not we.environment.fog_enabled, "no fog by default")
    m.free()
