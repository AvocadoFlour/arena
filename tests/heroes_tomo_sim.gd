extends Node3D
## Integration (Jolt, 60 Hz): Tomo's kit on a flat floor. Packet Burst completes a 3-round burst after a single
## trigger tap; Hotfix blinks forward, leaves an afterimage and buffs the next burst; Breakpoint roots the first
## enemy hit; Force Push damages + knocks back enemies in the frontal cone only and consumes the ult meter.
var results: Array = []
var done := false
var frame := 0
var tomo: Hero
var foe: Hero
var foe2: Hero
var ally: Hero
var hp0 := 0.0
var t0 := Vector3.ZERO
var p0 := Vector3.ZERO
var mover := Mover.new()

class Idle:
    var f := InputFrame.new()
    func poll(_h) -> InputFrame:
        return f

class Mover:   ## walks forward (-Z local) every tick
    func poll(_h) -> InputFrame:
        var f := InputFrame.new()
        f.move = Vector2(0, 1)
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
    bs.size = Vector3(160, 1, 160)
    cs.shape = bs
    sb.add_child(cs)
    sb.position = Vector3(0, -0.5, 0)
    add_child(sb)
    tomo = _hero("res://src/heroes/tomo.json", 0, Vector3(0, 0, 0))
    foe = _hero("res://src/heroes/cob.json", 1, Vector3(0, 0, -10))
    foe2 = _hero("res://src/heroes/twin_tails.json", 1, Vector3(30, 0, 30))
    ally = _hero("res://src/heroes/the_best.json", 0, Vector3(-30, 0, 30))

func _place(h: Hero, pos: Vector3) -> void:
    h.global_position = pos
    h.velocity = Vector3.ZERO
    h.health.reset()

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    match frame:
        20:
            tomo.yaw = 0.0
            tomo.pitch = -0.08
            hp0 = foe.health.hp
            tomo._try_fire()   # one tap: only the first round comes from the trigger
            _rec("burst_starts", tomo.weapon.bursting() and tomo.weapon.ammo == 23, "ammo=%d" % tomo.weapon.ammo)
        45:
            var d := hp0 - foe.health.hp
            _rec("burst_completes_after_tap", tomo.weapon.ammo == 21 and absf(d - 45.0) < 0.01, "ammo=%d dmg=%.1f" % [tomo.weapon.ammo, d])
            _rec("burst_pauses", not tomo.weapon.bursting(), "")
        70:
            _place(foe, Vector3(0, 0, -16))
            t0 = tomo.global_position
            _rec("hotfix_activates", tomo.abilities["ability1"].activate(), "")
            var ghost := find_children("HotfixAfterimage", "", false, false)
            _rec("hotfix_afterimage", ghost.size() == 1 and ghost[0].global_position.distance_to(t0 + Vector3(0, 0.925, 0)) < 0.05, "%d" % ghost.size())
            _rec("hotfix_bonus_armed", tomo.abilities["ability1"].bonus_pending() == 3, "")
        90:
            var moved := t0.z - tomo.global_position.z
            _rec("hotfix_blinks_forward", moved > 5.5 and moved < 8.0, "dz=%.2f" % moved)
            hp0 = foe.health.hp
            tomo.pitch = -0.04
            tomo._try_fire()
        115:
            var d := hp0 - foe.health.hp
            _rec("hotfix_bonus_burst", absf(d - 67.5) < 0.01, "dmg=%.1f" % d)
            _rec("hotfix_bonus_consumed", tomo.abilities["ability1"].bonus_pending() == 0, "")
        135:
            _rec("afterimage_fades", find_children("HotfixAfterimage", "", false, false).is_empty(), "")
            hp0 = foe.health.hp
            tomo._try_fire()
        160:
            var d := hp0 - foe.health.hp
            _rec("normal_burst_after_bonus", absf(d - 45.0) < 0.01, "dmg=%.1f" % d)
            # Breakpoint: foe walks toward Tomo; the marker roots it
            _place(tomo, Vector3(0, 0, 0))
            tomo.yaw = 0.0
            tomo.pitch = -0.1
            _place(foe, Vector3(0, 0, -9))
            foe.yaw = PI   # faces +Z (toward Tomo)
            foe.rotation.y = PI
            foe.input_source = mover
            hp0 = foe.health.hp
            _rec("breakpoint_activates", tomo.abilities["ability2"].activate(), "")
        180:
            _rec("breakpoint_hits", absf(hp0 - foe.health.hp - 25.0) < 0.01, "dmg=%.1f" % (hp0 - foe.health.hp))
            _rec("breakpoint_roots", foe.rooted() and foe.root_left > 0.5 and foe.slow_mult == 1.0, "root=%.2f slow=%.2f" % [foe.root_left, foe.slow_mult])
            p0 = foe.global_position
        215:
            var drift := Vector2(foe.global_position.x - p0.x, foe.global_position.z - p0.z).length()
            _rec("rooted_cannot_walk", drift < 0.3, "drift=%.2f" % drift)
            p0 = foe.global_position
        270:
            var walked := Vector2(foe.global_position.x - p0.x, foe.global_position.z - p0.z).length()
            _rec("root_wears_off", not foe.rooted() and walked > 1.0, "walked=%.2f" % walked)
            foe.input_source = Idle.new()
            # Force Push: foe in front, foe2 behind
            _place(tomo, Vector3(0, 0, 0))
            tomo.yaw = 0.0
            tomo.pitch = 0.0
            _place(foe, Vector3(0, 0, -5))
            _place(foe2, Vector3(0, 0, 4))
            _place(ally, Vector3(1.5, 0, -2))
            _rec("ult_locked", not tomo.abilities["ultimate"].activate(), "")
            tomo.ult.add(10000.0)
            hp0 = foe.health.hp
            _rec("ult_fires", tomo.abilities["ultimate"].activate(), "")
            var d := hp0 - foe.health.hp
            _rec("ult_damages_cone", d > 80.0 and d <= 130.0, "dmg=%.1f" % d)
            _rec("ult_knocks_back", foe.velocity.z < -10.0 and foe.velocity.y > 4.0, "v=%s" % foe.velocity)
            _rec("ult_spares_behind", foe2.health.hp == foe2.health.max_hp and foe2.velocity.length() < 0.01, "")
            _rec("ult_spares_ally", ally.health.hp == ally.health.max_hp and ally.velocity.length() < 0.01, "")
            _rec("ult_consumes_meter", not tomo.ult.is_full(), "")
        300:
            _rec("ult_pushes_away", foe.global_position.z < -6.0, "z=%.2f" % foe.global_position.z)
            done = true
