extends Node3D
## Integration (Jolt, 60 Hz), a small bot-match setup: Twin Tails' left click heals allies (primary.ally_heal = 7 per
## hit, capped at max HP, dead allies ignored) while enemies still take 11; the heal is credited to Twin Tails in
## MatchStats (Top healing, via Events.healed). Encore Beam: 60 HP/s on an ally for 4 s (240), 30 damage/s to an
## enemy it is aimed at or passes through, heal/damage mode for the colour, cancel with Shift through the normal
## input path (cooldown starts at the cancel / at the natural end), and the lockout (no fire / E / Q) while it runs.
## Staccato Note (E): flies through allies healing 19 once each (pass-through and splash, never twice, no slow), then
## hits the enemy for 30 + slow; Twin Tails never heals herself with it.
var results: Array = []
var done := false
var frame := 0
var tt: Hero
var ally: Hero
var foe: Hero
var ally2: Hero
var ally3: Hero
var stats: MatchStats
var inp := Trigger.new()
var hp0 := 0.0
var ammo0 := 0
var heal0 := 0.0

class Trigger:
    var fire := false
    var press := ""      ## one-tick edge: "ability1" / "ability2" / "ultimate"
    func poll(_h) -> InputFrame:
        var f := InputFrame.new()
        f.fire = fire
        if press != "":
            f.set(press, true)
            press = ""
        return f

class Idle:
    func poll(_h) -> InputFrame:
        return InputFrame.new()

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
    bs.size = Vector3(200, 1, 200)
    cs.shape = bs
    sb.add_child(cs)
    sb.position = Vector3(0, -0.5, 0)
    add_child(sb)
    tt = _hero("res://src/heroes/twin_tails.json", 0, Vector3(0, 0, 0))
    tt.input_source = inp
    ally = _hero("res://src/heroes/the_best.json", 0, Vector3(0, 0, -8))
    foe = _hero("res://src/heroes/cob.json", 1, Vector3(8, 0, 0))
    ally2 = _hero("res://src/heroes/nidjo.json", 0, Vector3(-50, 0, 50))
    ally3 = _hero("res://src/heroes/tomo.json", 0, Vector3(-55, 0, 50))
    stats = MatchStats.new()
    add_child(stats)
    stats.bind(Events)

func _aim(h: Hero) -> void:
    var d: Vector3 = h.global_position + Vector3(0, 1.0, 0) - tt.eye_position()
    tt.yaw = atan2(-d.x, -d.z)
    tt.rotation.y = tt.yaw
    tt.pitch = atan2(d.y, Vector2(d.x, d.z).length())
    tt.extra_spread_deg = -tt.weapon.spread_deg   # deterministic hits for exact numbers

func _healing() -> float:
    return float(stats.rows.get(tt, {"healing": 0.0}).healing)

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    match frame:
        10:
            _aim(ally)
            ally.health.hp = 100.0
            tt._try_fire()
            _rec("ally_hit_heals_7", is_equal_approx(ally.health.hp, 107.0), "hp=%.1f" % ally.health.hp)
        12:
            _aim(foe)
            hp0 = foe.health.hp
            tt.weapon.tick(1.0)
            tt._try_fire()
            _rec("enemy_hit_deals_11", is_equal_approx(hp0 - foe.health.hp, 11.0), "dmg=%.1f" % (hp0 - foe.health.hp))
        20:
            _aim(ally)
            ally.health.hp = 100.0
            tt.weapon.ammo = tt.weapon.mag_size
            ammo0 = tt.weapon.ammo
            inp.fire = true   # hold left click on the ally for 1 s
        80:
            inp.fire = false
            var shots := ammo0 - tt.weapon.ammo
            var got := ally.health.hp - 100.0
            _rec("held_fire_heals_7_per_shot", shots >= 6 and is_equal_approx(got, 7.0 * shots), "shots=%d healed=%.1f" % [shots, got])
            _rec("about_49_hps", got >= 42.0 and got <= 56.0, "%.1f HP in 1 s" % got)
        84:
            ally.health.hp = ally.health.max_hp - 3.0
            tt.weapon.tick(1.0)
            tt._try_fire()
            _rec("capped_at_max_hp", is_equal_approx(ally.health.hp, ally.health.max_hp), "hp=%.1f/%.1f" % [ally.health.hp, ally.health.max_hp])
        104:   # heal events are batched every 0.25 s: 7 + 7 x shots + 3 (capped)
            _rec("top_healing_credit", is_equal_approx(_healing(), 7.0 + 49.0 + 3.0), "healing=%.1f" % _healing())
        110:
            ally.health.hp = 0.0
            ally.dead = true
            hp0 = ally.health.hp
            tt.weapon.tick(1.0)
            tt._try_fire()
            _rec("dead_ally_not_healed", ally.health.hp == 0.0, "")
            ally.dead = false
            ally.health.hp = 100.0
            _aim(ally)
            heal0 = _healing()
            _rec("beam_starts", tt.abilities["ability1"].activate(), "")
        170:
            var got := ally.health.hp - 100.0
            _rec("beam_60_per_s", absf(got - 60.0) <= 2.0, "%.1f HP after 1 s" % got)
            _rec("beam_mode_heal", beam().mode_for(beam().target) == "heal", "")
            # lockout: fire / E / Q do nothing while the beam runs (ult meter full)
            tt.ult.add(10000.0)
            tt.weapon.tick(1.0)
            ammo0 = tt.weapon.ammo
            inp.fire = true
        176:
            inp.fire = false
            _rec("lockout_blocks_fire", tt.weapon.ammo == ammo0, "ammo %d -> %d" % [ammo0, tt.weapon.ammo])
            inp.press = "ability2"
        178:
            _rec("lockout_blocks_E", tt.abilities["ability2"].cooldown.is_ready(), "")
            inp.press = "ultimate"
        180:
            _rec("lockout_blocks_Q", tt.ult.is_full() and tt.abilities["ultimate"].cooldown.is_ready(), "")
            # an enemy walks through the beam between her and the ally
            foe.global_position = tt.global_position.lerp(ally.global_position, 0.5) + Vector3(0.2, 0, 0)
            hp0 = foe.health.hp
            heal0 = ally.health.hp
        240:
            var dmg := hp0 - foe.health.hp
            _rec("beam_damages_enemy_in_path_30_per_s", absf(dmg - 30.0) <= 1.0, "%.1f dmg in 1 s" % dmg)
            _rec("beam_still_heals_ally_behind", absf(ally.health.hp - heal0 - 60.0) <= 2.0, "%.1f" % (ally.health.hp - heal0))
            _rec("beam_mode_damage_in_path", beam().mode_for(beam().target) == "damage", "")
            # aim straight at the enemy (ally away): damage mode, host's replicated target = the enemy
            ally.global_position = Vector3(-40, 0, 40)
            foe.global_position = Vector3(0, 0, -6)
            _aim(foe)
        250:
            _rec("beam_targets_enemy", beam().target == foe and beam().mode_for(beam().target) == "damage", "target=%s" % beam().target)
            Net.register(tt)
            Net.register(foe)
            _rec("replicated_target_is_enemy", Net._heal_target_id(tt) == foe.net_id, "%d vs %d" % [Net._heal_target_id(tt), foe.net_id])
        362:
            _rec("natural_end_at_4s", not beam().channeling() and absf(beam().cooldown.remaining - (8.0 - 0.0)) <= 0.3, "cd=%.2f" % beam().cooldown.remaining)
            # fresh beam, cancelled after 1 s with Shift (InputFrame.ability1 -> Hero._use -> cancel)
            beam().cooldown.remaining = 0.0
            ally.global_position = Vector3(0, 0, -8)
            foe.global_position = Vector3(40, 0, 40)
            _aim(ally)
            inp.press = "ability1"
        364:
            _rec("restarted", beam().channeling() and beam().cooldown.remaining > 8.0, "cd=%.2f" % beam().cooldown.remaining)
        424:
            inp.press = "ability1"
        426:
            _rec("cancel_ends_early", not beam().channeling(), "")
            _rec("cooldown_starts_at_cancel", absf(beam().cooldown.remaining - 8.0) <= 0.05, "cd=%.2f" % beam().cooldown.remaining)
            ammo0 = tt.weapon.ammo
            tt.weapon.tick(1.0)
            inp.fire = true
        430:
            inp.fire = false
            _rec("fire_allowed_after_cancel", tt.weapon.ammo < ammo0, "")
        440:
            for h in [tt, ally, ally2, ally3, foe]:
                h.velocity = Vector3.ZERO
                h.health.hp = 100.0 if h != foe else h.health.max_hp
                h.slow_mult = 1.0
                h.slow_left = 0.0
            tt.global_position = Vector3(0, 0, 0)
            ally.global_position = Vector3(0, 0, -6)        # in the note's path
            foe.global_position = Vector3(0, 0, -15)
            ally2.global_position = Vector3(0.3, 0, -13)    # in the path AND inside the 2 m splash
            ally3.global_position = Vector3(1.2, 0, -15.2)  # splash only
        442:
            _aim(foe)
            inp.press = "ability2"
        444:
            _rec("note_fired", not tt.abilities["ability2"].cooldown.is_ready(), "")
        448:
            heal0 = _healing()   # earlier heal events flushed (0.25 s batches); the note reaches the first ally later
        500:
            _rec("note_passthrough_heals_19", is_equal_approx(ally.health.hp, 119.0), "hp=%.1f" % ally.health.hp)
            _rec("note_ally_not_slowed", ally.slow_mult == 1.0 and ally2.slow_mult == 1.0 and ally3.slow_mult == 1.0, "")
            _rec("note_path_and_splash_heals_once", is_equal_approx(ally2.health.hp, 119.0), "hp=%.1f" % ally2.health.hp)
            _rec("note_splash_heals_19", is_equal_approx(ally3.health.hp, 119.0), "hp=%.1f" % ally3.health.hp)
            _rec("note_continues_to_enemy_30_and_slow", is_equal_approx(foe.health.max_hp - foe.health.hp, 30.0) and foe.slow_mult == 0.5, "dmg=%.1f slow=%.2f" % [foe.health.max_hp - foe.health.hp, foe.slow_mult])
            _rec("note_no_self_heal", is_equal_approx(tt.health.hp, 100.0), "hp=%.1f" % tt.health.hp)
        530:
            _rec("note_heal_credited", is_equal_approx(_healing() - heal0, 57.0), "credited %.1f" % (_healing() - heal0))
            done = true

func beam():
    return tt.abilities["ability1"]
