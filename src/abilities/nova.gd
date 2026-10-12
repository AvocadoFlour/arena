extends Ability
## Ultimate: large AoE burst. Requires a full ult meter (charged by damage dealt).
func can_activate() -> bool:
    return cooldown.is_ready() and hero.ult.is_full()

func _do() -> bool:
    if not hero.ult.consume():
        return false
    var r := float(def.get("radius", 10.0))
    hero.aoe(hero.global_position + Vector3(0, 1, 0), r, float(def.get("damage", 220.0)), "ultimate")
    Fx.ring(hero.get_parent(), hero.global_position + Vector3(0, 1, 0), r, Color(0.3, 0.9, 1.0), 0.7)
    return true
