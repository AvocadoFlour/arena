extends Ability
## Deploys a temporary solid barrier in front of the hero. Blocks movement, hitscan and
## projectiles from both sides (it is world geometry on layer 1). Params: width, height,
## thickness, distance, duration, color.
var wall: StaticBody3D = null
var left := 0.0

func _do() -> bool:
    var parent: Node = hero.get_parent()
    if parent == null:
        return false
    remove_wall()
    wall = StaticBody3D.new()
    wall.collision_layer = 1
    var size := Vector3(float(def.get("width", 4.0)), float(def.get("height", 2.4)), float(def.get("thickness", 0.25)))
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    cs.shape = bs
    wall.add_child(cs)
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mi.mesh = bm
    var m := StandardMaterial3D.new()
    var c := Color(String(def.get("color", "#60c0ff")))
    m.albedo_color = Color(c.r, c.g, c.b, 0.45)
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mi.material_override = m
    wall.add_child(mi)
    wall.add_to_group("net_props")
    wall.set_meta("net_kind", "wall")
    wall.set_meta("net_size", size)
    wall.set_meta("net_color", c)
    parent.add_child(wall)
    var f: Vector3 = hero.look_dir()
    f = Vector3(f.x, 0, f.z).normalized()
    if f.length() < 0.1:
        f = Vector3(0, 0, -1)
    var pos: Vector3 = hero.global_position + f * float(def.get("distance", 1.6)) + Vector3(0, size.y * 0.5, 0)
    wall.global_position = pos
    wall.rotation.y = hero.yaw
    left = float(def.get("duration", 5.0))
    return true

func tick(dt: float) -> void:
    super.tick(dt)
    if left > 0.0:
        left -= dt
        if left <= 0.0:
            remove_wall()

func active() -> bool:
    return wall != null and is_instance_valid(wall)

func remove_wall() -> void:
    if wall != null and is_instance_valid(wall):
        wall.queue_free()
    wall = null
    left = 0.0
