extends Node3D
## Integration: The Best (melee combo, leap, team buff ult) and Cob (ult ground slam) at 60 Hz.
var results: Array = []
var done := false
var frame := 0
var best: Hero
var cob: Hero
var foe: Hero
var foe2: Hero
var ally: Hero
var hp0 := 0.0

class Idle:
    var f := InputFrame.new()
    func poll(_h) -> InputFrame:
        return f

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _hero(path: String, team: int, pos: Vector3) -> Hero:
    var h := Hero.from_def(path)
    h.team = team
    h.input_source = Idle.new()
    add_child(h)
    h.set_team(team)
    h.global_position = pos
    h.spawn_point = pos
    return h

func _ready() -> void:
    var sb := StaticBody3D.new()
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = Vector3(120, 1, 120)
    cs.shape = bs
    sb.add_child(cs)
    sb.position = Vector3(0, -0.5, 0)
    add_child(sb)
    best = _hero("res://src/heroes/the_best.json", 0, Vector3(0, 0, 0))
    foe = _hero("res://src/heroes/cob.json", 1, Vector3(0, 0, -2.2))
    foe2 = _hero("res://src/heroes/twin_tails.json", 1, Vector3(0, 0, 3))   # behind: must not be hit
    ally = _hero("res://src/heroes/twin_tails.json", 0, Vector3(4, 0, 0))
    cob = _hero("res://src/heroes/cob.json", 0, Vector3(40, 0, 0))

func _swing() -> float:
    var before := foe.health.hp
    best.weapon._shot_cd = 0.0
    best._try_fire()
    return before - foe.health.hp

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    match frame:
        30:
            var b2 := foe2.health.hp
            var d1 := _swing()
            _rec("melee_hits_in_arc", absf(d1 - 32.0) < 0.01, "dmg=%.1f" % d1)
            _rec("melee_misses_behind", foe2.health.hp == b2, "")
        40:
            var d2 := _swing()
            _rec("melee_combo_second", absf(d2 - 32.0) < 0.01, "dmg=%.1f" % d2)
        50:
            var d3 := _swing()
            _rec("melee_combo_finisher", absf(d3 - 51.2) < 0.01, "dmg=%.1f" % d3)
            _rec("finisher_knockback", foe.velocity.length() > 3.0, "v=%.1f" % foe.velocity.length())
        80:
            foe.velocity = Vector3.ZERO
            foe.global_position = Vector3(0, 0, -6.5)
            best.global_position = Vector3(0, 0, 0)
        100:
            var dl := _swing()
            _rec("melee_lunge_reaches", dl > 0.0 and best.dash_time > 0.0, "dmg=%.1f" % dl)
        140:
            var d4 := _swing()
            _rec("combo_resets_after_window", absf(d4 - 32.0) < 0.01 or d4 == 0.0, "dmg=%.1f" % d4)
            best.global_position = Vector3(-20, 0, 10)
            best.yaw = 0.0
            foe.global_position = Vector3(-20, 0, -5.5)
            foe.velocity = Vector3.ZERO
            foe.health.reset()
            hp0 = foe.health.hp
            _rec("leap_activates", best.abilities["ability1"].activate(), "")
        141:
            _rec("leap_airborne", best.global_position.y > 0.05 or best.velocity.y > 0.0, "y=%.2f" % best.global_position.y)
        220:
            var moved := 10.0 - best.global_position.z
            _rec("leap_travels", moved > 6.0, "dz=%.2f" % moved)
            _rec("leap_landed", best.is_on_floor() and not best.abilities["ability1"].leaping(), "")
            _rec("leap_impact_damage", hp0 - foe.health.hp > 10.0, "dmg=%.1f" % (hp0 - foe.health.hp))
        230:
            best.global_position = Vector3(0, 0, 0)
            ally.global_position = Vector3(3, 0, 0)
            _rec("ult_locked", not best.abilities["ultimate"].activate(), "")
            best.ult.add(10000.0)
            _rec("ult_fires", best.abilities["ultimate"].activate(), "")
            _rec("ult_consumes_meter", not best.ult.is_full(), "")
            _rec("ult_buffs_self", best.damage_mult() > 1.3 and best.knockback_immune and best.overheal > 100.0, "mult=%.2f oh=%.0f" % [best.damage_mult(), best.overheal])
            _rec("ult_buffs_ally", ally.damage_mult() > 1.3 and ally.overheal > 100.0, "")
            _rec("ult_skips_enemy", foe2.damage_mult() == 1.0, "")
            var v0 := best.velocity
            best.knockback(Vector3(20, 0, 0))
            _rec("ult_knockback_immune", best.velocity == v0, "")
        700:
            _rec("ult_expires", best.damage_mult() == 1.0 and not best.knockback_immune and best.overheal == 0.0, "")
            foe.global_position = Vector3(44, 0, 0)
            foe.velocity = Vector3.ZERO
            foe.health.reset()
            hp0 = foe.health.hp
            cob.ult.add(10000.0)
            _rec("cob_slam_ult", cob.abilities["ultimate"].activate(), "")
            _rec("cob_slam_damage", hp0 - foe.health.hp > 100.0, "dmg=%.1f" % (hp0 - foe.health.hp))
            _rec("cob_slam_consumes", not cob.ult.is_full(), "")
            done = true
