extends "res://src/abilities/nova.gd"
## Force Push (Tomo): ultimate shockwave in a wide frontal cone. Every enemy inside `radius` and the `arc_deg`
## cone takes damage (HitMath falloff: 100 % at Tomo, 50 % at the edge) and is knocked straight away from him
## (`knockback` horizontal + `lift` up; ignored while knockback_immune). Breakable cover in the cone is damaged
## too. Needs a full ult meter (nova.gd). Params: radius, arc_deg, damage, knockback, lift, color.
func _do() -> bool:
    if not hero.is_inside_tree() or not hero.ult.consume():
        return false
    var r := float(def.get("radius", 9.0))
    var arc := deg_to_rad(float(def.get("arc_deg", 120.0))) * 0.5
    var dmg := float(def.get("damage", 130.0))
    var f: Vector3 = hero.look_dir()
    var fwd := Vector3(f.x, 0, f.z)
    fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
    var o: Vector3 = hero.global_position
    for h in targets(hero, r, arc, fwd):
        var amt := HitMath.aoe_damage(o + Vector3(0, 0.9, 0), r, dmg, h.global_position + Vector3(0, 0.9, 0))
        if amt <= 0.0:
            continue
        h.take_damage(amt * hero.damage_mult(), hero, h.global_position + Vector3(0, 1.2, 0), "ultimate", id)
        var away: Vector3 = h.global_position - o
        away.y = 0.0
        away = away.normalized() if away.length() > 0.01 else fwd
        h.knockback(away * float(def.get("knockback", 15.0)) + Vector3(0, float(def.get("lift", 5.5)), 0))
    for c in hero.get_tree().get_nodes_in_group("destructible"):
        if c.is_inside_tree() and MeleeMath.in_arc(o, fwd, c.global_position, r, arc) and hero.can_hit(c):
            var ca := HitMath.aoe_damage(o, r, dmg, c.global_position)
            if ca > 0.0:
                c.take_damage(ca * hero.damage_mult(), hero, c.global_position, "ultimate", id)
    var col := Color(String(def.get("color", "#ff4a4a")))
    for i in 3:   # expanding wave of rings in front (replayed on clients)
        var d := r * (0.25 + 0.3 * i)
        Fx.ring(hero.get_parent(), o + Vector3(0, 1.0, 0) + fwd * d, 0.8 + d * tan(arc) * 0.5, col, 0.35 + 0.1 * i)
    return true

## Enemies (alive, other team) within `r` of the hero and inside the frontal cone (half-angle `half_arc`).
static func targets(h, r: float, half_arc: float, fwd: Vector3) -> Array:
    var out: Array = []
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o == h or o.dead or o.team == h.team:
            continue
        if o.get_world_3d() != h.get_world_3d():
            continue
        if MeleeMath.in_arc(h.global_position, fwd, o.global_position, r, half_arc) and h.can_hit(o):   # walls block it
            out.append(o)
    return out
