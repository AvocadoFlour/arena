extends Ability
## Ultimate (use with "needs_ult": true): restores the hero and allies within `radius` to the health they had
## `window` seconds ago (only ever heals: the gap between that HP and the current HP), then the hero takes
## `damage_reduction` (fraction) less damage for `dr_duration` s via hero.apply_damage_reduction (pre-damage, so it
## also softens a single lethal hit). Niđo's Rollback.
## HP history: every `sample` s the ability records the HP of every living hero on its team (all peers; only the
## host/offline heal() applies).
var _hist := {}        ## hero instance id -> Array of [time, hp] (oldest first)
var _t := 0.0
var _acc := 0.0
var last_restored := {}   ## hero -> HP restored by the latest cast (tests)

func tick(dt: float) -> void:
    super.tick(dt)
    _t += dt
    _acc += dt
    if _acc >= float(def.get("sample", 0.25)):
        _acc = 0.0
        _record()

func _record() -> void:
    if hero == null or not hero.is_inside_tree():
        return
    var keep := float(def.get("window", 4.0)) + 1.0
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h.team != hero.team:
            continue
        var k: int = h.get_instance_id()
        if h.dead:
            _hist.erase(k)   # a death clears the history: Rollback never undoes a death
            continue
        var a: Array = _hist.get(k, [])
        a.append([_t, float(h.health.hp)])
        while a.size() > 1 and a[0][0] < _t - keep:
            a.pop_front()
        _hist[k] = a

## HP the hero had about `window` s ago (oldest sample if the history is shorter), or -1 when unknown.
func past_hp(h) -> float:
    var a: Array = _hist.get(h.get_instance_id(), [])
    if a.is_empty():
        return -1.0
    var target := _t - float(def.get("window", 4.0))
    var best: float = a[0][1]
    for e in a:
        if e[0] <= target:
            best = e[1]
    return best

func _do() -> bool:
    if not hero.is_inside_tree():
        return false
    _record()
    last_restored.clear()
    var r := float(def.get("radius", 10.0))
    for h in hero.get_tree().get_nodes_in_group("heroes"):
        if h.dead or h.team != hero.team or h.global_position.distance_to(hero.global_position) > r:
            continue
        var p := past_hp(h)
        if p > h.health.hp:
            last_restored[h] = h.heal(p - h.health.hp, hero, id)
    hero.apply_damage_reduction(float(def.get("damage_reduction", 0.35)), float(def.get("dr_duration", 4.0)), "rollback")
    Fx.ring(hero.get_parent(), hero.global_position + Vector3(0, 1, 0), r, Color(String(def.get("color", "#40e070"))), 0.7)
    return true

## Seconds of damage reduction left on the caster (HUD/tests).
func dr_left() -> float:
    return hero.damage_reduction_left("rollback")
