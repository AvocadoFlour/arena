extends Node3D
## Übel's primary: a held stream of magma. Corkscrew of hot blobs, not the Encore Beam ribbon.
## Drawn from replicated `primary_beam` (or the local player's own fire). No gameplay here.
const BLOBS := 16
var hero
var _t := 0.0
var _blobs: Array = []

func setup(h) -> void:
    hero = h
    for i in BLOBS:
        var m := MeshInstance3D.new()
        var s := SphereMesh.new()
        var hot: bool = i % 3 == 0
        s.radius = 0.22 if hot else 0.14
        s.height = s.radius * 2.0
        s.radial_segments = 8
        s.rings = 4
        m.mesh = s
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        var c := Color("#ffb000") if hot else (Color("#ff4d1a") if i % 3 == 1 else Color("#7a180c"))
        mat.albedo_color = Color(c.r, c.g, c.b, 0.92)
        mat.emission_enabled = true
        mat.emission = c * (2.2 if hot else 1.1)
        m.material_override = mat
        m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        m.top_level = true
        m.visible = false
        add_child(m)
        _blobs.append(m)

func visual_process(dt: float) -> void:
    _t += dt
    var on: bool = hero != null and is_instance_valid(hero) and hero.primary_beam and not hero.dead
    if not on:
        for m in _blobs:
            m.visible = false
        return
    var p: Dictionary = hero.def.get("primary", {})
    var rng := float(p.get("range", 16.0))
    var a: Vector3 = hero.eye_position() + hero.look_dir() * 0.35
    var b: Vector3 = _end(a, hero.look_dir(), rng)
    var axis: Vector3 = b - a
    var length := axis.length()
    if length < 0.05:
        for m in _blobs:
            m.visible = false
        return
    var dir := axis / length
    var side := dir.cross(Vector3.UP)
    if side.length() < 0.15:
        side = dir.cross(Vector3.RIGHT)
    side = side.normalized()
    var lift := dir.cross(side).normalized()
    for i in _blobs.size():
        var m: MeshInstance3D = _blobs[i]
        var f := fposmod(_t * 0.85 + float(i) / BLOBS, 1.0)
        var env := sin(f * PI)
        var wob := sin(f * TAU * 3.0 - _t * 7.0) * 0.42 * env
        var wob2 := cos(f * TAU * 2.0 - _t * 5.0) * 0.33 * env
        m.global_position = a.lerp(b, f) + side * wob + lift * wob2
        var pulse := 0.75 + 0.35 * sin(_t * 9.0 + float(i))
        m.scale = Vector3.ONE * pulse * (1.15 if i % 3 == 0 else 0.85)
        m.visible = true

func _end(a: Vector3, dir: Vector3, rng: float) -> Vector3:
    var end := a + dir * rng
    if hero == null or not hero.is_inside_tree():
        return end
    var exclude: Array = [hero.get_rid()]
    for _i in 6:
        var q := PhysicsRayQueryParameters3D.create(a, end)
        q.exclude = exclude
        var hit: Dictionary = hero.get_world_3d().direct_space_state.intersect_ray(q)
        if hit.is_empty():
            return end
        var c = hit.collider
        if c is Node and c.is_in_group("heroes"):
            exclude.append(c.get_rid())
            continue
        return hit.position
    return end
