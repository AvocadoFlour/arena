extends Ability
## Self/team buff (usually an ultimate with "needs_ult": true): for `duration` s every ally within
## `radius` (incl. self) deals damage x `damage_mult`, is immune to knockback (`knockback_immune`)
## and gets `overheal` temporary HP that decays over the duration.
func _do() -> bool:
    var r := float(def.get("radius", 8.0))
    var dur := float(def.get("duration", 6.0))
    var targets: Array = [hero]
    if hero.is_inside_tree():
        for h in hero.get_tree().get_nodes_in_group("heroes"):
            if h != hero and not h.dead and h.team == hero.team and h.global_position.distance_to(hero.global_position) <= r:
                targets.append(h)
    for h in targets:
        h.apply_buff(float(def.get("damage_mult", 1.3)), dur, bool(def.get("knockback_immune", true)))
        h.add_overheal(float(def.get("overheal", 100.0)), dur)
    if hero.is_inside_tree():
        Fx.ring(hero.get_parent(), hero.global_position + Vector3(0, 1, 0), r, Color(1, 0.75, 0.2), 0.6)
    return true
