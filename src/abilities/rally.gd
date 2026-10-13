extends Ability
## Ultimate: heals self and allies within radius by `heal` (full ult meter required).
func can_activate() -> bool:
    return cooldown.is_ready() and hero.ult.is_full()

func _do() -> bool:
    if not hero.ult.consume():
        return false
    var r := float(def.get("radius", 10.0))
    var amt := float(def.get("heal", 150.0))
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h.dead or h.team != hero.team:
            continue
        if h.global_position.distance_to(hero.global_position) <= r:
            h.heal(amt, hero, id)
    Fx.ring(hero.get_parent(), hero.global_position + Vector3(0, 1, 0), r, Color(0.3, 1.0, 0.5), 0.7)
    return true
