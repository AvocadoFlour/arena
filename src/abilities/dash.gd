extends Ability
## Short burst in the move direction (or facing direction if not moving).
func _do() -> bool:
    var dir: Vector3 = hero.last_wish
    if dir.length() < 0.1:
        var f: Vector3 = hero.look_dir()
        dir = Vector3(f.x, 0, f.z)
    dir = dir.normalized()
    var dur := float(def.get("duration", 0.18))
    hero.dash_time = dur
    hero.dash_vel = dir * float(def.get("distance", 7.0)) / dur
    return true
