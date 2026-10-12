class_name MapLoader
extends RefCounted
## Builds a map Node3D from the JSON map format (INTERFACES.md section 6).

static func load_def(path: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(path))

static func build(path: String) -> Node3D:
    var d := load_def(path)
    var root := Node3D.new()
    root.name = "Map"
    var grid := _grid_tex()
    var i := 0
    for b in d.get("blocks", []):
        var body := _box(b, grid)
        body.name = "%s_%02d" % [String(b.get("kind", "block")), i]   # unique, keeps kind prefix (AI finds "cover")
        body.set_meta("kind", String(b.get("kind", "block")))
        root.add_child(body)
        i += 1
    var env := WorldEnvironment.new()
    var e := Environment.new()
    var sky := Sky.new()
    var sm := ProceduralSkyMaterial.new()
    sm.sky_top_color = Color("#3a5a8a")
    sm.sky_horizon_color = Color("#a8b8c8")
    sky.sky_material = sm
    e.background_mode = Environment.BG_SKY
    e.sky = sky
    e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    e.ambient_light_energy = 0.8
    e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.environment = e
    root.add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -35, 0)
    sun.shadow_enabled = true
    sun.light_energy = 1.1
    root.add_child(sun)
    var spawns := {}
    var sp: Dictionary = d.get("spawns", {})
    for team in sp:
        var arr: Array = []
        for p in sp[team]:
            arr.append(Vector3(p[0], p[1], p[2]))
        spawns[int(team)] = arr
    root.set_meta("spawns", spawns)
    root.set_meta("bounds", float(d.get("bounds", 17)))
    root.set_meta("map_name", d.get("name", "Map"))
    # Optional extensions (arena02+): capture zones and spawn rooms, data only.
    var zones: Array = []
    for z in d.get("zones", []):
        zones.append({"id": z.get("id", ""), "kind": z.get("kind", "capture"), "pos": _v(z.pos), "size": _v(z.size)})
    root.set_meta("zones", zones)
    var rooms := {}
    var sr: Dictionary = d.get("spawn_rooms", {})
    for team in sr:
        rooms[int(team)] = AABB(_v(sr[team].pos) - _v(sr[team].size) * 0.5, _v(sr[team].size))
    root.set_meta("spawn_rooms", rooms)
    return root

static func _v(a) -> Vector3:
    return Vector3(a[0], a[1], a[2])

static func _box(b: Dictionary, grid: Texture2D) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = String(b.get("kind", "block"))
    var size := _v(b.size)
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    cs.shape = bs
    body.add_child(cs)
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mi.mesh = bm
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(String(b.get("color", "#888888")))
    if b.get("grid", false):
        mat.albedo_texture = grid
        mat.uv1_triplanar = true
        mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
    mi.material_override = mat
    body.add_child(mi)
    body.position = _v(b.pos)
    if b.has("rot_deg"):
        body.rotation_degrees = _v(b.rot_deg)
    return body

static func _grid_tex() -> Texture2D:
    var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
    img.set_pixel(0, 0, Color(1, 1, 1))
    img.set_pixel(1, 1, Color(1, 1, 1))
    img.set_pixel(1, 0, Color(0.82, 0.82, 0.82))
    img.set_pixel(0, 1, Color(0.82, 0.82, 0.82))
    return ImageTexture.create_from_image(img)
