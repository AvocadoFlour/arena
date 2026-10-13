extends Node3D
## Integration: real heroes in a scene at 60 Hz. Projectile hits+slows, shield wall blocks,
## charge damages, heal beam targets an ally.
var results: Array = []
var done := false
var frame := 0
var willow: Hero
var rampart: Hero
var dummy: Hero
var ally: Hero
var hp0 := 0.0

class Idle:
    var f := InputFrame.new()
    func poll(_h) -> InputFrame:
        return f

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _box(pos: Vector3, size: Vector3) -> void:
    var sb := StaticBody3D.new()
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    cs.shape = bs
    sb.add_child(cs)
    sb.position = pos
    add_child(sb)

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
    _box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
    willow = _hero("res://src/heroes/twin_tails.json", 0, Vector3(0, 0, 0))
    dummy = _hero("res://src/heroes/archive/kestrel.json", 1, Vector3(0, 0, -12))
    ally = _hero("res://src/heroes/archive/kestrel.json", 0, Vector3(-20, 0, -5))
    rampart = _hero("res://src/heroes/cob.json", 0, Vector3(20, 0, 0))
    willow.pitch = -0.08   # aim a little down toward dummy torso

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    match frame:
        30:
            hp0 = dummy.health.hp
            _rec("projectile_fires", willow.abilities["ability2"].activate(), "")
            var shots := get_children().filter(func(c): return c.is_in_group("net_props") and c.get_meta("net_kind", "") == "shot")
            _rec("projectile_spawned", shots.size() == 1, "n=%d" % shots.size())
        58:
            var dmg := hp0 - dummy.health.hp
            _rec("projectile_hits_after_travel", dmg >= 20.0, "dmg=%.1f" % dmg)
            _rec("projectile_slows", dummy.slow_mult < 1.0 and dummy.slow_left > 0.0, "mult=%.2f" % dummy.slow_mult)
            _rec("projectile_freed", get_children().filter(func(c): return c.is_in_group("net_props") and c.get_meta("net_kind", "") == "shot" and is_instance_valid(c) and not c.is_queued_for_deletion()).is_empty(), "")
        62:
            # shield wall between willow and dummy
            willow.global_position = Vector3(0, 0, 0)
            rampart.global_position = Vector3(0, 0, -3)
            rampart.yaw = 0.0
            rampart.rotation.y = 0.0
            _rec("shield_wall_up", rampart.abilities["ability2"].activate() and rampart.abilities["ability2"].active(), "")
        66:
            dummy.health.reset()
            hp0 = dummy.health.hp
            willow.abilities["ability2"].cooldown.remaining = 0.0
            _rec("projectile_refire", willow.abilities["ability2"].activate(), "")
        100:
            _rec("shield_blocks_projectile", dummy.health.hp == hp0, "dmg=%.1f" % (hp0 - dummy.health.hp))
        400:
            _rec("shield_expires", not rampart.abilities["ability2"].active(), "")
            rampart.global_position = Vector3(10, 0, -12)
            dummy.global_position = Vector3(10, 0, -16)
            dummy.health.reset()
            hp0 = dummy.health.hp
            _rec("charge_activates", rampart.abilities["ability1"].activate(), "")
        440:
            _rec("charge_moves", rampart.global_position.z < -14.0, "z=%.2f" % rampart.global_position.z)
            _rec("charge_damages", hp0 - dummy.health.hp >= 30.0, "dmg=%.1f" % (hp0 - dummy.health.hp))
        450:
            willow.global_position = Vector3(-20, 0, 5)
            willow.yaw = 0.0
            willow.pitch = 0.0
            ally.health.hp = 50.0
            var hb = willow.abilities["ability1"]
            hb.cooldown.remaining = 0.0
            _rec("heal_beam_activates", hb.activate(), "")
        510:
            _rec("heal_beam_heals_ally", ally.health.hp > 90.0, "hp=%.1f" % ally.health.hp)
            done = true
