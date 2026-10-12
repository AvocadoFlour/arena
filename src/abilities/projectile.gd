extends Ability
## Projectile weapon ability: spawns a travelling shot (not hitscan).
## Params: speed, damage, gravity, lifetime, hit_radius, splash_radius (0 = direct only),
## slow {mult, duration} (optional), kind, color, size.
const Shot := preload("res://src/abilities/projectile_shot.gd")

func _do() -> bool:
    var parent: Node = hero.get_parent()
    if parent == null:
        return false
    var s = Shot.new(hero, def)
    var origin: Vector3 = hero.eye_position()
    var dir: Vector3 = hero.look_dir()
    if hero.aim_camera:
        dir = -hero.aim_camera.global_basis.z
    s.add_to_group("net_props")
    s.set_meta("net_kind", "shot")
    s.set_meta("net_size", Vector3.ONE * float(def.get("size", 0.2)))
    s.set_meta("net_color", Color(String(def.get("color", "#ffd060"))))
    parent.add_child(s)
    s.launch(origin + dir * 0.6, dir)
    return true
