extends Ability
## Leap charge: jump forward in the aim direction; on landing, AoE impact (damage + knockback).
## Params: forward_speed, up_speed, air_time, radius, damage, knockback.
var airborne := false

func _do() -> bool:
    var f: Vector3 = hero.look_dir()
    var dir := Vector3(f.x, 0, f.z)
    if dir.length() < 0.1:
        dir = Vector3(0, 0, -1)
    dir = dir.normalized()
    var fs := float(def.get("forward_speed", 14.0))
    hero.dash_time = float(def.get("air_time", 0.7))
    hero.dash_vel = dir * fs
    hero.velocity = dir * fs + Vector3(0, float(def.get("up_speed", 9.0)), 0)
    hero.slam_pending = true
    airborne = true
    return true

func leaping() -> bool:
    return airborne

func on_landed() -> void:
    if not airborne:
        return
    airborne = false
    hero.dash_time = 0.0
    var r := float(def.get("radius", 3.5))
    var dmg := float(def.get("damage", 50.0))
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h == hero or h.dead or h.team == hero.team:
            continue
        var amt := HitMath.aoe_damage(hero.global_position, r, dmg, h.global_position + Vector3(0, 0.9, 0))
        if amt > 0.0 and hero.can_hit(h):   # walls / shield walls block the landing impact
            h.take_damage(amt * hero.damage_mult(), hero, h.global_position + Vector3(0, 1.2, 0), "charge", id)
            var away: Vector3 = h.global_position - hero.global_position
            away.y = 0
            h.knockback(away.normalized() * float(def.get("knockback", 6.0)) + Vector3(0, 4, 0))
    Fx.ring(hero.get_parent(), hero.global_position + Vector3(0, 0.3, 0), r, Color(1, 0.7, 0.2))
