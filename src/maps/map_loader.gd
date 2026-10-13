class_name MapLoader
extends RefCounted
## Builds a map Node3D from the JSON map format (INTERFACES.md section 6).

static func load_def(path: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(path))

## opts: {"low_quality": bool} overrides the Settings/GameConfig flag (see low_quality_flag()).
static func build(path: String, opts: Dictionary = {}) -> Node3D:
    var d := load_def(path)
    var lq: bool = bool(opts.get("low_quality", low_quality_flag()))
    var root := Node3D.new()
    root.name = "Map"
    var grid := _grid_tex()
    var theme: Dictionary = d.get("theme", {})
    var mats := _materials(d.get("materials", {}), grid)
    var i := 0
    for b in d.get("blocks", []):
        var body := _box(b, grid, mats)
        body.name = "%s_%02d" % [String(b.get("kind", "block")), i]   # unique, keeps kind prefix (AI finds "cover")
        body.set_meta("kind", String(b.get("kind", "block")))
        root.add_child(body)
        i += 1
    if not lq:
        var props := _props(d.get("props", []), mats)
        if props.get_child_count() > 0:
            root.add_child(props)
    root.add_child(_environment(theme, lq))
    root.add_child(_sun(theme, lq))
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
        var zd: Dictionary = z.duplicate()
        zd["id"] = z.get("id", "")
        zd["kind"] = z.get("kind", "capture")
        zd["pos"] = _v(z.pos)
        zd["size"] = _v(z.size)
        zones.append(zd)
    root.set_meta("zones", zones)
    var rooms := {}
    var sr: Dictionary = d.get("spawn_rooms", {})
    for team in sr:
        rooms[int(team)] = AABB(_v(sr[team].pos) - _v(sr[team].size) * 0.5, _v(sr[team].size))
    root.set_meta("spawn_rooms", rooms)
    return root

static func _v(a) -> Vector3:
    return Vector3(a[0], a[1], a[2])

static func _box(b: Dictionary, grid: Texture2D, mats: Dictionary = {}) -> StaticBody3D:
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
    if b.has("mat") and mats.has(b.mat):
        mi.material_override = mats[b.mat]
    else:
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(String(b.get("color", "#888888")))
        if b.get("grid", false):
            mat.albedo_texture = grid
            mat.uv1_triplanar = true
            mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
            mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
        mi.material_override = mat
    if String(b.get("kind", "")) == "floor":
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # receives only; nothing below it
    body.add_child(mi)
    body.position = _v(b.pos)
    if b.has("rot_deg"):
        body.rotation_degrees = _v(b.rot_deg)
    return body

## Visual-only theme (optional "theme" key). Defaults reproduce the v0.1 look.
static func _environment(t: Dictionary, low_quality := false) -> WorldEnvironment:
    var env := WorldEnvironment.new()
    var e := Environment.new()
    var sky := Sky.new()
    var sm := ProceduralSkyMaterial.new()
    sm.sky_top_color = Color(String(t.get("sky_top", "#3a5a8a")))
    sm.sky_horizon_color = Color(String(t.get("sky_horizon", "#a8b8c8")))
    if t.has("ground_horizon"):
        sm.ground_horizon_color = Color(String(t.ground_horizon))
    if t.has("ground_bottom"):
        sm.ground_bottom_color = Color(String(t.ground_bottom))
    sky.sky_material = sm
    e.background_mode = Environment.BG_SKY
    e.sky = sky
    e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    e.ambient_light_energy = float(t.get("ambient_energy", 0.8))
    e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    if t.has("fog_density") and not low_quality:
        e.fog_enabled = true
        e.fog_light_color = Color(String(t.get("fog_color", "#a8b8c8")))
        e.fog_density = float(t.fog_density)
        e.fog_sky_affect = float(t.get("fog_sky_affect", 0.3))
    env.environment = e
    return env

static func _sun(t: Dictionary, low_quality := false) -> DirectionalLight3D:
    var sun := DirectionalLight3D.new()
    var r: Array = t.get("sun_rot", [-55, -35, 0])
    sun.rotation_degrees = _v(r)
    sun.shadow_enabled = not low_quality   # shadows ~40 % of frame time under software GL
    # Cheaper shadows (biggest cost in software/mobile GL): 2 PSSM splits, distance capped to the play area.
    sun.directional_shadow_mode = int(t.get("shadow_mode", DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS))
    sun.directional_shadow_max_distance = float(t.get("shadow_distance", 60.0))
    sun.light_energy = float(t.get("sun_energy", 1.1))
    sun.light_color = Color(String(t.get("sun_color", "#ffffff")))
    return sun

## Palette (optional "materials" key): name -> {color, roughness?, metallic?, pattern?, pattern_scale?,
## tint?, emission?, emission_energy?}. Patterns are tiny deterministic procedural textures.
static func _materials(defs: Dictionary, grid: Texture2D) -> Dictionary:
    var out := {}
    var texs := {"grid": grid}
    for name in defs:
        var m: Dictionary = defs[name]
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(String(m.get("color", "#888888")))
        mat.roughness = float(m.get("roughness", 0.9))
        mat.metallic = float(m.get("metallic", 0.0))
        var pat := String(m.get("pattern", "none"))
        if pat != "none":
            var key := pat + str(m.get("tint", ""))
            if not texs.has(key):
                texs[key] = _pattern_tex(pat, float(m.get("tint", 0.82)))
            mat.albedo_texture = texs[key]
            mat.uv1_triplanar = true
            var sc := float(m.get("pattern_scale", 0.5))
            mat.uv1_scale = Vector3(sc, sc, sc)
            mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        if m.has("emission"):
            mat.emission_enabled = true
            mat.emission = Color(String(m.emission))
            mat.emission_energy_multiplier = float(m.get("emission_energy", 1.0))
        if m.has("alpha"):
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.albedo_color.a = float(m.alpha)
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        out[name] = mat
    return out

## Deterministic 16x16 greyscale patterns (no RNG; a fixed integer hash gives per-tile variation).
static func _pattern_tex(pat: String, tint: float) -> Texture2D:
    var n := 16
    var img := Image.create(n, n, true, Image.FORMAT_RGB8)
    for y in n:
        for x in n:
            var v := 1.0
            match pat:
                "tiles":
                    v = tint if (x % 8 == 0 or y % 8 == 0) else 1.0 - 0.04 * float(((x / 8) * 7 + (y / 8) * 3) % 3)
                "planks":
                    var row := y / 4
                    var off := (row * 5) % 16
                    v = tint if (y % 4 == 0 or (x + off) % 16 == 0) else 1.0 - 0.05 * float((row * 11) % 3)
                "bricks":
                    var r2 := y / 4
                    var o2 := 4 if r2 % 2 == 1 else 0
                    v = tint if (y % 4 == 0 or (x + o2) % 8 == 0) else 1.0 - 0.03 * float(((x + o2) / 8 + r2 * 3) % 3)
                "stripes":
                    v = tint if (x / 4) % 2 == 0 else 1.0
                _:
                    v = tint if ((x / 8) + (y / 8)) % 2 == 1 else 1.0
            img.set_pixel(x, y, Color(v, v, v))
    img.generate_mipmaps()
    return ImageTexture.create_from_image(img)

## Low-quality flag, read defensively: Settings.low_quality (player setting) OR GameConfig.low_quality (-- --low_quality).
static func low_quality_flag() -> bool:
    var ml := Engine.get_main_loop()
    if not (ml is SceneTree):
        return false
    for n in ["Settings", "GameConfig"]:
        var o: Node = (ml as SceneTree).root.get_node_or_null(n)
        if o != null and "low_quality" in o and bool(o.get("low_quality")):
            return true
    return false

## Decorative props (optional "props" key): visual meshes only, no collision bodies.
## {"shape":"box|cylinder|sphere|cone","pos","size"? | "radius"?,"height"?,"rot_deg"?,"mat"|"color","no_shadow"?}
## Batched at build time: one merged ArrayMesh per (material, shadow) group, in data order (deterministic).
static func _prop_mesh(p: Dictionary) -> PrimitiveMesh:
    var shape := String(p.get("shape", "box"))
    match shape:
        "cylinder", "cone":
            var cm := CylinderMesh.new()
            cm.top_radius = 0.0 if shape == "cone" else float(p.get("radius", 0.5))
            cm.bottom_radius = float(p.get("radius", 0.5))
            cm.height = float(p.get("height", 1.0))
            cm.radial_segments = int(p.get("segments", 8))
            cm.rings = 1
            return cm
        "sphere":
            var sm := SphereMesh.new()
            sm.radius = float(p.get("radius", 0.5))
            sm.height = sm.radius * 2.0
            sm.radial_segments = 8
            sm.rings = 4
            return sm
    var bm := BoxMesh.new()
    bm.size = _v(p.get("size", [1, 1, 1]))
    return bm

static func _props(defs: Array, mats: Dictionary) -> Node3D:
    var root := Node3D.new()
    root.name = "Props"
    var groups := {}     # key -> {st, mat, shadow}
    var order: Array = []
    var color_mats := {}
    for p in defs:
        var mat: Material
        var mkey: String
        if p.has("mat") and mats.has(p.mat):
            mat = mats[p.mat]
            mkey = String(p.mat)
        else:
            mkey = "#" + String(p.get("color", "#888888"))
            if not color_mats.has(mkey):
                var m := StandardMaterial3D.new()
                m.albedo_color = Color(String(p.get("color", "#888888")))
                color_mats[mkey] = m
            mat = color_mats[mkey]
        var shadow: bool = not bool(p.get("no_shadow", false))
        var key := "%s_%s" % [mkey.replace("#", "c"), "s" if shadow else "n"]
        if not groups.has(key):
            var st := SurfaceTool.new()
            st.begin(Mesh.PRIMITIVE_TRIANGLES)
            groups[key] = {"st": st, "mat": mat, "shadow": shadow, "n": 0}
            order.append(key)
        var xf := Transform3D(Basis.from_euler(_v(p.get("rot_deg", [0, 0, 0])) * (PI / 180.0), EULER_ORDER_YXZ), _v(p.pos))
        groups[key].st.append_from(_prop_mesh(p), 0, xf)
        groups[key].n += 1
    for key in order:
        var g: Dictionary = groups[key]
        var mi := MeshInstance3D.new()
        mi.name = "props_" + key
        mi.mesh = g.st.commit()
        mi.material_override = g.mat
        mi.set_meta("prop_count", g.n)
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if g.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        root.add_child(mi)
    return root
static func _grid_tex() -> Texture2D:
    var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
    img.set_pixel(0, 0, Color(1, 1, 1))
    img.set_pixel(1, 1, Color(1, 1, 1))
    img.set_pixel(1, 0, Color(0.82, 0.82, 0.82))
    img.set_pixel(0, 1, Color(0.82, 0.82, 0.82))
    return ImageTexture.create_from_image(img)
