extends Ability
## Line slash: one instant cut along the aim (flat), hitting every enemy inside a thin box in front of the hero:
## `length` m long, `width` m wide, from the hero's feet up to `height` m. The cut goes through cover (enemies
## behind a wall are still hit) and also damages breakable cover in the box. A rider (ride ability) always cuts
## the victim below her. Params: damage, length, width, height, knockback, cooldown.
static func in_box(origin: Vector3, fwd: Vector3, p: Vector3, length: float, width: float, height: float) -> bool:
    var to := p - origin
    if to.y < -0.5 or to.y > height:
        return false
    var f := Vector3(fwd.x, 0, fwd.z).normalized()
    var along := f.dot(Vector3(to.x, 0, to.z))
    var side := absf(f.cross(Vector3.UP).dot(Vector3(to.x, 0, to.z)))
    return along >= -0.3 and along <= length and side <= width * 0.5

func _do() -> bool:
    if not hero.is_inside_tree():
        return false
    var fwd: Vector3 = hero.look_dir()
    fwd.y = 0.0
    if fwd.length() < 0.01:
        fwd = Vector3(0, 0, -1)
    fwd = fwd.normalized()
    var o: Vector3 = hero.global_position
    var ln := float(def.get("length", 6.0))
    var w := float(def.get("width", 1.2))
    var hgt := float(def.get("height", 2.5))
    var dmg: float = float(def.get("damage", 60.0)) * hero.damage_mult()
    var under = hero.mounted_on() if hero.has_method("mounted_on") else null
    if under != null:   # cutting down from a head: the box starts at the victim's feet and covers her seat height
        hgt += o.y - under.global_position.y
        o.y = under.global_position.y
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h == hero or h.dead or h.team == hero.team or h.get_world_3d() != hero.get_world_3d():
            continue
        var pos: Vector3 = h.global_position
        if h == under or in_box(o, fwd, pos, ln, w, hgt) or in_box(o, fwd, pos + Vector3(0, 1.0, 0), ln, w, hgt):
            h.take_damage(dmg, hero, pos + Vector3(0, 1.2, 0), "ability", id)
            var kb := float(def.get("knockback", 0.0))
            if kb > 0.0 and h != under:
                h.knockback(fwd * kb)
    for c in hero.get_tree().get_nodes_in_group("destructible"):
        if c.is_inside_tree() and in_box(o, fwd, c.global_position, ln, w + 0.6, hgt + 0.5):
            c.take_damage(dmg, hero, c.global_position, "ability", id)
    return true
