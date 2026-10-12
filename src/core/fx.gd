class_name Fx
extends RefCounted
## Throwaway visual effects built from primitives.

static func _mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = c
    if c.a < 1.0:
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return m

static func tracer(parent: Node, a: Vector3, b: Vector3, c: Color) -> void:
    Net.send_fx("tracer", [a, b, c])
    var length := a.distance_to(b)
    if length < 0.05:
        return
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(0.035, 0.035, length)
    mi.mesh = bm
    mi.material_override = _mat(c)
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    mi.global_position = (a + b) * 0.5
    var up := Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT
    mi.look_at(b, up)
    parent.get_tree().create_timer(0.06).timeout.connect(mi.queue_free)

static func ring(parent: Node, pos: Vector3, radius: float, c: Color, dur: float = 0.4) -> void:
    Net.send_fx("ring", [pos, radius, c, dur])
    var mi := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 1.0
    sm.height = 2.0
    mi.mesh = sm
    var m := _mat(Color(c.r, c.g, c.b, 0.55))
    mi.material_override = m
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    mi.global_position = pos
    mi.scale = Vector3.ONE * 0.2
    var tw := mi.create_tween().set_parallel(true)
    tw.tween_property(mi, "scale", Vector3(radius, radius * 0.35, radius), dur)
    tw.tween_property(m, "albedo_color:a", 0.0, dur)
    tw.chain().tween_callback(mi.queue_free)
