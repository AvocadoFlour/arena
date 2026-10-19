extends Ability
## Pulls every enemy within `radius` toward the hero and slows them (Niđo's Stand-up Meeting).
## Params: radius, pull_speed (max horizontal pull velocity), up_speed (small hop so the pull clears the floor),
## stop_distance (targets aim to end about this far from the hero), slow (speed multiplier), slow_duration, color.
## Walls and shield walls between Niđo's chest and a target's centre block it (Hero.los_clear; heroes do not).
## Uses only the hero API: knockback() (ignored while knockback_immune) and apply_slow(). No damage.
var last_pulled := 0   ## heroes pulled by the latest cast (tests / bots)

func _do() -> bool:
    if not hero.is_inside_tree():
        return false
    var r := float(def.get("radius", 8.0))
    var stop := float(def.get("stop_distance", 1.8))
    var spd := float(def.get("pull_speed", 16.0))
    last_pulled = 0
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h == hero or h.dead or h.team == hero.team:
            continue
        var d: Vector3 = hero.global_position - h.global_position
        d.y = 0.0
        var dist := d.length()
        if dist > r:
            continue
        if not Hero.los_clear(hero, hero.chest(), h.global_position + Vector3(0, 0.9, 0), h):
            continue   # physical path, chest to centre: walls / shield walls block the pull (not a vision check)
        if dist > stop and dist > 0.01:
            # speed scales with the gap so near targets are not flung past the hero
            h.knockback(d / dist * minf(spd, (dist - stop) * 4.0) + Vector3(0, float(def.get("up_speed", 3.0)), 0))
        h.apply_slow(float(def.get("slow", 0.6)), float(def.get("slow_duration", 2.0)))
        last_pulled += 1
    Fx.ring(hero.get_parent(), hero.global_position + Vector3(0, 0.4, 0), r, Color(String(def.get("color", "#40e070"))), 0.45)
    return true
