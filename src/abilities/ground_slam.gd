extends Ability
## Grounded: instant AoE shockwave. Airborne: dive down, AoE on landing.
func _do() -> bool:
    if hero.is_on_floor():
        _impact()
    else:
        hero.slam_pending = true
        hero.velocity.y = -float(def.get("dive_speed", 30.0))
    return true

func on_landed() -> void:
    _impact()

func _impact() -> void:
    var r := float(def.get("radius", 5.0))
    hero.aoe(hero.global_position, r, float(def.get("damage", 70.0)), "slam")
    Fx.ring(hero.get_parent(), hero.global_position + Vector3(0, 0.3, 0), r, Color(1, 0.6, 0.1))
