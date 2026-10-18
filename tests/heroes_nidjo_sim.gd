extends Node3D
## Integration (60 Hz, real physics): Niđo's Ping Hammer combo, Firewall blocking a hitscan shot, Stand-up Meeting
## pulling an enemy closer over time + slow, Rollback restoring an ally. Structure adapted from the heroes bot's
## backed-up heroes_newkits_sim.gd (Niđo part only).
var results: Array = []
var done := false
var nidjo: Hero
var foe: Hero
var ally: Hero

class Idle:
    var f := InputFrame.new()
    func poll(_h) -> InputFrame:
        return f

func _rec(n: String, ok: bool, info: String = "") -> void:
    results.append([n, ok, info])

func _hero(id: String, team: int, pos: Vector3) -> Hero:
    var h := Hero.from_def("res://src/heroes/%s.json" % id)
    h.team = team
    h.input_source = Idle.new()
    add_child(h)
    h.set_team(team)
    h.global_position = pos
    h.spawn_point = pos
    return h

func _wait(s: float) -> void:
    await get_tree().create_timer(s, true, true).timeout

func _flat(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()

func _ready() -> void:
    var sb := StaticBody3D.new()
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = Vector3(120, 1, 120)
    cs.shape = bs
    sb.add_child(cs)
    sb.position = Vector3(0, -0.5, 0)
    add_child(sb)
    nidjo = _hero("nidjo", 0, Vector3(0, 0, 0))
    ally = _hero("the_best", 0, Vector3(-3, 0, 0))
    foe = _hero("cob", 1, Vector3(0, 0, -7))
    _run()

func _run() -> void:
    await _wait(0.3)
    _rec("loaded", nidjo.display_name == "Niđo" and nidjo.model != null and absf(nidjo.health.max_hp - 300.0) < 0.1)
    # Stand-up Meeting: the enemy ends up clearly closer (pull survives ground friction) and is slowed
    var d0 := _flat(nidjo.global_position, foe.global_position)
    nidjo.abilities.ability2.activate()
    _rec("pull_slow", foe.slow_mult < 1.0, "slow %.2f" % foe.slow_mult)
    await _wait(0.6)
    var d1 := _flat(nidjo.global_position, foe.global_position)
    _rec("pull_closes_distance", d1 < d0 - 2.0 and d1 > 0.8, "%.2f -> %.2f m" % [d0, d1])
    # Ping Hammer: three swings, the third knocks back
    nidjo.yaw = atan2(-(foe.global_position.x - nidjo.global_position.x), -(foe.global_position.z - nidjo.global_position.z))
    nidjo.rotation.y = nidjo.yaw
    foe.global_position = nidjo.global_position + Vector3(-sin(nidjo.yaw), 0, -cos(nidjo.yaw)) * 2.0
    var hp0 := foe.health.hp
    var hits := 0
    for i in 3:
        hits += nidjo.melee_swing()
        if i < 2:
            await _wait(0.05)
    var v := foe.velocity
    _rec("hammer_combo", hits == 3 and foe.health.hp < hp0 and Vector2(v.x, v.z).length() > 1.0, "hits %d hp %.0f->%.0f v %s" % [hits, hp0, foe.health.hp, v])
    await _wait(0.8)
    # Firewall: a wall between Niđo and the enemy stops a hitscan ray
    foe.global_position = nidjo.global_position + Vector3(-sin(nidjo.yaw), 0, -cos(nidjo.yaw)) * 5.0
    foe.velocity = Vector3.ZERO
    nidjo.abilities.ability1.activate()
    await _wait(0.1)
    var q := PhysicsRayQueryParameters3D.create(nidjo.global_position + Vector3(0, 1.2, 0), foe.global_position + Vector3(0, 1.2, 0))
    q.exclude = [nidjo.get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(q)
    _rec("firewall_blocks", nidjo.abilities.ability1.active() and not hit.is_empty() and hit.collider is StaticBody3D and hit.collider != foe, str(hit.get("collider")))
    # Rollback: the ally gets back the HP it lost a moment ago
    ally.global_position = nidjo.global_position + Vector3(2, 0, 0)
    await _wait(1.0)
    ally.take_damage(140.0, foe, Vector3.ZERO, "primary")
    var before := ally.health.hp
    await _wait(0.6)
    nidjo.ult.charge = nidjo.ult.cost
    var ok: bool = nidjo.abilities.ultimate.activate()
    _rec("rollback_restores", ok and ally.health.hp >= before + 130.0, "%.0f -> %.0f" % [before, ally.health.hp])
    for h in [nidjo, ally, foe]:
        h.queue_free()
    await _wait(0.1)
    done = true
