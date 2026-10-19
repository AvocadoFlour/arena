extends "res://tests/test_base.gd"
## Perf pass (maps queue 4): merged static block meshes, unshaded low-quality toon path, draw-call budget,
## host per-tick script cost. Collision is checked against the golden file (unchanged).

const MAPS := ["arena01.json", "arena02.json"]

class FH:
    var team := 0
    var dead := false
    var global_position := Vector3.ZERO
    var velocity := Vector3.ZERO
    var def := {"collider": {"radius": 0.4}}
    func heal(_a: float) -> float:
        return 0.0
    func take_damage(_a: float, _s, _p: Vector3, _k: String, _i := "") -> float:
        return 0.0

func _def(f: String) -> Dictionary:
    return MapLoader.load_def("res://src/maps/" + f)

func test_golden_unchanged() -> void:
    var g = JSON.parse_string(FileAccess.get_file_as_string("res://tests/maps_collision_golden.json"))
    for f in MAPS:
        for lq in [false, true]:
            var m := MapLoader.build("res://src/maps/" + f, {"low_quality": lq})
            check(load("res://tests/maps_visual_test.gd").signature(m) == g[f], "%s lq=%s collision identical" % [f, lq])
            m.free()

func test_blocks_merged_per_material() -> void:
    for f in MAPS:
        var d := _def(f)
        for lq in [false, true]:
            var m := MapLoader.build("res://src/maps/" + f, {"low_quality": lq})
            var bl := m.get_node_or_null("Blocks")
            check(bl != null, "%s Blocks node" % f)
            if bl == null:
                m.free()
                continue
            var keys := {}
            var n_merge := 0
            var tris := 0
            for i in d.blocks.size():
                var b: Dictionary = d.blocks[i]
                var body: Node = m.get_node("%s_%02d" % [b.kind, i])
                var own := body.find_children("*", "MeshInstance3D", false, false)
                if MapLoader.is_destructible(b):
                    check(own.size() >= 1 and not body.has_meta("mesh_group"), "%s %d destructible keeps its own mesh" % [f, i])
                    continue
                n_merge += 1
                var key := "blocks_%s_%s" % [b.mat, "n" if b.kind == "floor" else "s"]
                keys[key] = true
                check(own.is_empty() and String(body.get_meta("mesh_group", "")) == key, "%s %d merged into %s" % [f, i, key])
                check(body.find_children("*", "CollisionShape3D", false, false).size() == 1, "%s %d keeps its collision" % [f, i])
            var counted := 0
            for mi in bl.get_children():
                counted += int(mi.get_meta("block_count"))
                var arr: Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)
                tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
                check((mi as MeshInstance3D).mesh.get_surface_count() == 1, "%s %s one surface (one draw call)" % [f, mi.name])
                var floor_grp: bool = String(mi.name).ends_with("_n")
                check((mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) == floor_grp, "%s %s shadow flag" % [f, mi.name])
            check(bl.get_child_count() == keys.size() and counted == n_merge, "%s lq=%s %d blocks in %d meshes" % [f, lq, n_merge, bl.get_child_count()])
            check(tris == 12 * n_merge, "%s merged geometry = 12 triangles per block (%d)" % [f, tris])
            m.free()

func test_merged_geometry_matches_blocks() -> void:
    # union of the merged meshes' bounds == union of the transformed block boxes (same placement as the bodies)
    for f in MAPS:
        var d := _def(f)
        var m := MapLoader.build("res://src/maps/" + f, {"low_quality": true})
        var want := {}
        for i in d.blocks.size():
            var b: Dictionary = d.blocks[i]
            if MapLoader.is_destructible(b):
                continue
            var body: Node3D = m.get_node("%s_%02d" % [b.kind, i])
            var sz := Vector3(b.size[0], b.size[1], b.size[2])
            var box: AABB = body.transform * AABB(-sz * 0.5, sz)
            var key := String(body.get_meta("mesh_group"))
            want[key] = box if not want.has(key) else (want[key] as AABB).merge(box)
        for mi in m.get_node("Blocks").get_children():
            var got: AABB = (mi as MeshInstance3D).mesh.get_aabb()
            var w: AABB = want[String(mi.name)]
            check(got.position.distance_to(w.position) < 1e-3 and got.size.distance_to(w.size) < 1e-3, "%s %s bounds %s vs %s" % [f, mi.name, got, w])
        m.free()

func test_low_quality_toon_path() -> void:
    for f in MAPS:
        var d := _def(f)
        var hi := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
        var lo := MapLoader.build("res://src/maps/" + f, {"low_quality": true})
        var sun: DirectionalLight3D = lo.find_children("*", "DirectionalLight3D", false, false)[0]
        for mi in hi.get_node("Blocks").get_children():
            var mh: ShaderMaterial = mi.material_override
            var ml: ShaderMaterial = lo.get_node("Blocks/" + String(mi.name)).material_override
            check(mh.shader == MapLoader.MAP_TOON, "%s %s normal quality keeps the lit toon shader" % [f, mi.name])
            check(ml.shader == MapLoader.MAP_TOON_LQ, "%s %s low quality uses the unshaded toon path" % [f, mi.name])
            for pn in ["albedo", "shade", "use_pattern", "pattern_scale", "emission", "emission_energy"]:
                check(mh.get_shader_parameter(pn) == ml.get_shader_parameter(pn), "%s %s %s copied" % [f, mi.name, pn])
            var th = mh.get_shader_parameter("pattern")
            var tl = ml.get_shader_parameter("pattern")
            check((th == null) == (tl == null) and (th == null or (th as Texture2D).get_image().get_data() == (tl as Texture2D).get_image().get_data()), "%s %s same pattern" % [f, mi.name])
            var st: Vector3 = ml.get_shader_parameter("sun_to")
            check(st.distance_to(sun.transform.basis.z) < 1e-4, "%s sun_to = direction towards the sun" % f)
        for c in lo.get_children():
            if c is DestructibleCover:
                var cm: ShaderMaterial = c.find_children("*", "MeshInstance3D", false, false)[0].material_override
                check(cm.shader == MapLoader.MAP_TOON_LQ, "%s %s destructible cover lq material" % [f, c.name])
        hi.free()
        lo.free()

static func draw_items(m: Node) -> int:
    var n := 0
    for g in m.find_children("*", "GeometryInstance3D", true, false):
        if (g as GeometryInstance3D).visible:
            n += 1
    return n

func test_draw_item_budget() -> void:
    # visible map geometry instances (each >= 1 draw call, plus one per shadow split in normal quality).
    # Before the pass (one mesh per block): arena01 45 normal / 36 lq, arena02 98 / 85. After: 33 / 24, 53 / 40
    # (blocks 18 -> 6 and 60 -> 15 meshes; the rest is pickups/pads, barrier panels, props, destructible cover).
    var budget := {"arena01.json": [33, 24], "arena02.json": [53, 40]}   # [normal, low quality]
    for f in MAPS:
        for k in 2:
            var m := MapLoader.build("res://src/maps/" + f, {"low_quality": k == 1})
            var n := draw_items(m)
            check(n <= budget[f][k], "%s lq=%d %d map geometry instances (budget %d)" % [f, k, n, budget[f][k]])
            m.free()

func test_host_tick_cost() -> void:
    # SpawnRooms + Objects + Bounds + CaptureZone steps with 10 heroes: well under 1 ms per 60 Hz tick
    var m := MapLoader.build("res://src/maps/arena02.json", {"low_quality": true})
    var hs: Array = []
    for i in 10:
        var h := FH.new()
        h.team = i % 2
        h.global_position = Vector3(-30 + i * 6, 0.2, -10 + i * 2)
        hs.append(h)
    var sr: SpawnRooms = m.get_node("SpawnRooms")
    var ob: MapObjects = m.get_node("Objects")
    var bd: MapBounds = m.get_node("Bounds")
    for n in [sr, ob, bd]:
        n.authority_override = 1
    bd.safe_points()
    var zs := CaptureZone.from_map(m)
    var t := Time.get_ticks_usec()
    for k in 300:
        sr.step(hs)
        ob.step(hs)
        bd.step(hs)
        for z in zs:
            z.step(1.0 / 60.0, z.count(hs))
    var per := float(Time.get_ticks_usec() - t) / 300.0
    check(per < 1000.0, "host map scripts %.0f us per tick (10 heroes)" % per)
    for z in zs:
        z.free()
    m.free()
