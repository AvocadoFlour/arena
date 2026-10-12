extends Ability
## Forward rush (uses the hero dash hooks). Enemies touched take damage once and are knocked
## back. Params: distance, duration, damage, hit_radius, knockback.
var left := 0.0
var hit: Array = []

func _do() -> bool:
    var f: Vector3 = hero.look_dir()
    var dir := Vector3(f.x, 0, f.z)
    if dir.length() < 0.1:
        dir = Vector3(0, 0, -1)
    dir = dir.normalized()
    var dur := float(def.get("duration", 0.5))
    hero.dash_time = dur
    hero.dash_vel = dir * float(def.get("distance", 9.0)) / dur
    left = dur
    hit = []
    return true

func charging() -> bool:
    return left > 0.0

func tick(dt: float) -> void:
    super.tick(dt)
    if left <= 0.0:
        return
    left -= dt
    if not hero.is_inside_tree():
        return
    var r := float(def.get("hit_radius", 1.3))
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h == hero or h.dead or h.team == hero.team or hit.has(h):
            continue
        if h.global_position.distance_to(hero.global_position) <= r:
            hit.append(h)
            h.take_damage(float(def.get("damage", 40.0)) * hero.damage_scale, hero, h.global_position + Vector3(0, 1.2, 0), "charge")
            var kb: Vector3 = hero.dash_vel.normalized() * float(def.get("knockback", 8.0))
            h.velocity += Vector3(kb.x, 4.0, kb.z)
