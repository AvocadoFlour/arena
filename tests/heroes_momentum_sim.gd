extends Node3D
## Integration (Jolt, 60 Hz): Niđo's Momentum (primary.on_hit_speed {bonus, decay}). A hammer swing that hits an
## enemy hero gives x(1 + bonus) move speed, fading linearly to x1 over `decay` s; a hit at half time resets it;
## one swing hitting two enemies is one refresh; destructible-only / ally-only swings give nothing; slows multiply
## on top; acceleration is scaled too; real ground speed rises; death clears it; the MomentumLink net prop carries
## the fraction to clients (decoded the same on a puppet).
var results: Array = []
var done := false
var frame := 0
var nid: Hero
var foe: Hero
var foe2: Hero
var ally: Hero
var mover := Mover.new()
var _t := 0
var _step := 0
var bonus := 0.5
var decay := 1.0

class Idle:
    func poll(_h) -> InputFrame:
        return InputFrame.new()

class Mover:
    var on := false
    func poll(_h) -> InputFrame:
        var f := InputFrame.new()
        if on:
            f.move = Vector2(0, 1)
        return f

class Cover extends StaticBody3D:
    var taken := 0.0
    func _init() -> void:
        var cs := CollisionShape3D.new()
        var bs := BoxShape3D.new()
        bs.size = Vector3(1, 1, 1)
        cs.shape = bs
        add_child(cs)
        add_to_group("destructible")
    func take_damage(a: float, _s = null, _p = Vector3.ZERO, _k := "", _id := "") -> void:
        taken += a

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
    bs.size = Vector3(300, 1, 300)
    cs.shape = bs
    sb.add_child(cs)
    sb.position = Vector3(0, -0.5, 0)
    add_child(sb)
    nid = _hero("res://src/heroes/nidjo.json", 0, Vector3.ZERO)
    nid.input_source = mover
    foe = _hero("res://src/heroes/cob.json", 1, Vector3(40, 0, 0))
    foe2 = _hero("res://src/heroes/the_best.json", 1, Vector3(40, 0, 20))
    ally = _hero("res://src/heroes/twin_tails.json", 0, Vector3(40, 0, 40))
    var o: Dictionary = nid.def.primary.on_hit_speed
    bonus = float(o.bonus)
    decay = float(o.decay)

func _place(h: Hero, pos: Vector3) -> void:
    h.global_position = pos
    h.velocity = Vector3.ZERO
    h.yaw = 0.0
    h.rotation.y = 0.0
    h.health.reset()

func _swing() -> void:
    nid.combo_left = 0.0
    nid.melee_swing()

func _near(a: float, b: float, tol := 0.02) -> bool:
    return absf(a - b) <= tol

func _props() -> Array:
    return get_tree().get_nodes_in_group("net_props").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion() and String(n.get_meta("net_kind", "")).begins_with("momentum:"))

func _physics_process(_dt: float) -> void:
    frame += 1
    if done or frame < 5:
        return
    _t += 1
    var half := int(round(decay * 30.0))
    var full := int(round(decay * 60.0))
    match _step:
        0:   # one hit: 1.5x at t=0, 1.25x at decay/2, 1.0x at decay
            if _t == 1:
                nid.net_id = 9001   # stands in for the Net registry id (kind momentum:<id>)
                _place(nid, Vector3.ZERO)
                _place(foe, Vector3(0, 0, -2))
                _swing()
                _rec("hit_gives_full_bonus_t0", _near(nid.momentum_mult(), 1.0 + bonus), "x%.3f" % nid.momentum_mult())
                _rec("data_values", bonus == 0.5 and decay == 1.0, "bonus=%s decay=%s" % [bonus, decay])
                var pr := _props()
                _rec("net_prop_up", pr.size() == 1 and String(pr[0].get_meta("net_kind")) == "momentum:%d" % nid.net_id, "%d" % pr.size())
            if _t == 1 + half:
                _rec("half_decay_is_1_25", _near(nid.momentum_mult(), 1.0 + bonus * 0.5), "x%.3f" % nid.momentum_mult())
                # client side: the prop yaw decodes to the same fraction on a puppet
                var pr := _props()
                var cn: Node3D = Net.make_prop(String(pr[0].get_meta("net_kind")), Vector3.ONE * 0.1, Color.WHITE, String(pr[0].get_meta("net_visual")))
                add_child(cn)
                cn.rotation.y = pr[0].rotation.y
                cn._process(0.0)
                var pup := _hero("res://src/heroes/nidjo.json", 0, Vector3(60, 0, 60))
                pup.net_role = "puppet"
                pup.net_id = cn.hero_id
                _rec("client_reads_replicated_fraction", _near(pup.momentum_mult(), nid.momentum_mult(), 0.01), "client x%.3f host x%.3f" % [pup.momentum_mult(), nid.momentum_mult()])
                cn.queue_free()
                pup.queue_free()
            if _t == 1 + full:
                _rec("full_decay_is_1_0", _near(nid.momentum_mult(), 1.0, 0.001), "x%.3f" % nid.momentum_mult())
            if _t == 1 + full + 2:
                _rec("net_prop_gone_after", _props().is_empty(), "%d" % _props().size())
                _step += 1
                _t = 0
        1:   # second hit at decay/2 resets to full
            if _t == 1:
                _place(foe, Vector3(0, 0, -2))
                _swing()
            if _t == 1 + half:
                _swing()
                _rec("second_hit_resets_to_1_5", _near(nid.momentum_mult(), 1.0 + bonus), "x%.3f" % nid.momentum_mult())
            if _t == 1 + half + half:
                _rec("reset_restarts_timer", _near(nid.momentum_mult(), 1.0 + bonus * 0.5), "x%.3f" % nid.momentum_mult())
                _step += 1
                _t = 0
        2:   # two enemies, one swing = one refresh, no stacking
            if _t == 1:
                nid.momentum_left = 0.0
                _place(foe, Vector3(-0.6, 0, -2))
                _place(foe2, Vector3(0.6, 0, -2))
                var r0 := nid.momentum_refreshes
                _swing()
                _rec("two_enemies_one_refresh", nid.momentum_refreshes == r0 + 1 and _near(nid.momentum_mult(), 1.0 + bonus), "refreshes +%d x%.3f" % [nid.momentum_refreshes - r0, nid.momentum_mult()])
                _rec("both_enemies_were_hit", foe.health.hp < foe.health.max_hp and foe2.health.hp < foe2.health.max_hp, "")
                _place(foe2, Vector3(40, 0, 20))
            if _t == 3:   # destructible only, ally only: nothing
                nid.momentum_left = 0.0
                _place(foe, Vector3(40, 0, 0))
                var cv := Cover.new()
                add_child(cv)
                cv.global_position = Vector3(0, 0.5, -2)
                _place(ally, Vector3(0.8, 0, -1.8))
                ally.health.hp = ally.health.max_hp - 50.0
                var r0 := nid.momentum_refreshes
                _swing()
                _rec("destructible_or_ally_gives_nothing", cv.taken > 0.0 and nid.momentum_refreshes == r0 and nid.momentum_mult() == 1.0, "cover %.1f x%.3f" % [cv.taken, nid.momentum_mult()])
                cv.queue_free()
                _place(ally, Vector3(40, 0, 40))
            if _t == 5:   # slow multiplies on top; accel scaled
                _place(foe, Vector3(0, 0, -2))
                _swing()
                nid.apply_slow(0.6, 3.0)
                var base := float(nid.move_cfg.get("speed", 7.0))
                var c := nid.effective_move_cfg()
                _rec("slow_multiplies_on_top", _near(float(c.speed), base * 0.6 * (1.0 + bonus), 0.01), "speed %.3f want %.3f" % [float(c.speed), base * 0.6 * (1.0 + bonus)])
                _rec("accel_scaled", _near(float(c.get("accel_ground", 0)), float(nid.move_cfg.get("accel_ground", 70.0)) * (1.0 + bonus), 0.01), "accel %.2f" % float(c.get("accel_ground", 0)))
                nid.slow_mult = 1.0
                nid.slow_left = 0.0
                _place(foe, Vector3(40, 0, 0))
            if _t == 8:   # real ground speed: run, hit, keep running
                nid.momentum_left = 0.0
                _place(nid, Vector3(0, 0, 20))
                mover.on = true
            if _t == 30:
                _rec_v0 = Vector2(nid.velocity.x, nid.velocity.z).length()
                _place(foe, nid.global_position + Vector3(1.6, 0, -1.2))   # in the arc, not in the running line
                foe.velocity = Vector3.ZERO
                nid.combo_left = 0.0
                nid.melee_swing()
            if _t == 36:
                var v := Vector2(nid.velocity.x, nid.velocity.z).length()
                _rec("ground_speed_rises", v > _rec_v0 * 1.3, "%.2f -> %.2f m/s" % [_rec_v0, v])
                mover.on = false
            if _t == 40:   # death clears
                _place(nid, Vector3.ZERO)
                _place(foe, Vector3(0, 0, -2))
                _swing()
                nid.take_damage(99999, foe, nid.global_position, "primary")
                _rec("death_clears", nid.momentum_left == 0.0 and nid.momentum_mult() == 1.0, "left=%.2f" % nid.momentum_left)
            if _t == 42:
                _rec("death_removes_prop", _props().is_empty(), "%d" % _props().size())
                nid.respawn()
                _rec("respawn_without_bonus", nid.momentum_mult() == 1.0, "")
                done = true

var _rec_v0 := 0.0
