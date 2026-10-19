extends Node3D
## Integration (Jolt, 60 Hz): a left click during a movement ability must not lunge or change the trajectory.
## The Best: Fearless Leap with an enemy ahead in the lunge cone - a no-click leap is the reference; clicking
## mid-air gives the same landing point, no damage in the air, and the swing runs after the landing (buffered).
## Same for a click during Swagger Step (dash). The Best / Niđo / Übel jumping: a mid-air swing never lunges
## (no dash push, horizontal speed unchanged).
var results: Array = []
var done := false
var frame := 0
var best: Hero
var nidjo: Hero
var ubel: Hero
var foe: Hero
var inp := Scripted.new()
var _phase := 0
var _t := 0
var _ref_land := Vector3.INF
var _land := Vector3.INF
var _land_t := -1
var _air_dmg := 0.0
var _swing_t := -1
var _combo0 := 0
var _hero_j: Hero = null
var _jumpers: Array = []
var _vx0 := 0.0
var _in_cone := false

class Scripted:
    var fire := false
    var jump := false
    func poll(_h) -> InputFrame:
        var f := InputFrame.new()
        f.fire = fire
        f.jump = jump
        jump = false
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
    bs.size = Vector3(300, 1, 300)
    cs.shape = bs
    sb.add_child(cs)
    sb.position = Vector3(0, -0.5, 0)
    add_child(sb)
    best = _hero("res://src/heroes/the_best.json", 0, Vector3(0, 0, 0))
    nidjo = _hero("res://src/heroes/nidjo.json", 0, Vector3(-40, 0, 0))
    ubel = _hero("res://src/heroes/ubel.json", 0, Vector3(-80, 0, 0))
    foe = _hero("res://src/heroes/cob.json", 1, Vector3(0, 0, -16))
    _jumpers = [best, nidjo, ubel]

func _place(h: Hero, pos: Vector3) -> void:
    h.global_position = pos
    h.velocity = Vector3.ZERO
    h.dash_time = 0.0
    h.yaw = 0.0
    h.pitch = 0.0
    h.rotation.y = 0.0
    h.health.reset()
    h.combo_left = 0.0
    h.combo_step = 0

func _lost() -> float:
    return foe.health.max_hp - foe.health.hp

## One leap run; click: fire held for 3 ticks starting 42 ticks after the leap (mid-air, enemy ahead in the cone).
func _leap_run(click: bool) -> bool:
    var lp = best.abilities["ability1"]
    _t += 1
    if _t == 1:
        _place(best, Vector3.ZERO)
        _place(foe, Vector3(0, 0, -16))
        best.input_source = inp
        _land = Vector3.INF
        _land_t = -1
        _air_dmg = 0.0
        _swing_t = -1
        _combo0 = best.combo_step
        return false
    if _t == 3:
        lp.cooldown.remaining = 0.0
        lp.activate()
        return false
    if click and _t >= 45 and _t < 48:
        inp.fire = true
        if _t == 45:   # precondition: the enemy is inside the lunge window/cone while we click (the old bug)
            var p: Dictionary = best.def.get("primary", {})
            var dz := best.global_position.z - foe.global_position.z
            _in_cone = dz > float(p.get("range", 3.2)) * 0.8 and dz < float(p.get("range", 3.2)) + float(p.get("lunge", 5)) and lp.leaping()
    else:
        inp.fire = false
    if _land_t < 0:
        if lp.leaping():
            _air_dmg = _lost()
        elif _t > 4:
            _land_t = _t
            _land = best.global_position
    if _swing_t < 0 and best.combo_step != _combo0:
        _swing_t = _t
    return _t > 130

func _physics_process(_dt: float) -> void:
    frame += 1
    if done or frame < 5:
        return
    match _phase:
        0:
            if _leap_run(false):
                _ref_land = _land
                _rec("reference_leap_lands", _land != Vector3.INF and _swing_t < 0, "land=%s" % _land)
                _phase = 1
                _t = 0
        1:
            if _leap_run(true):
                var leap_ticks := _land_t
                _rec("click_happens_with_enemy_in_lunge_window", _in_cone, "")
                _rec("click_mid_air_same_landing", _land.distance_to(_ref_land) < 0.15, "ref=%s got=%s" % [_ref_land, _land])
                _rec("click_mid_air_no_air_damage", _air_dmg == 0.0, "air dmg=%.1f" % _air_dmg)
                _rec("click_mid_air_swing_after_landing", _swing_t >= leap_ticks and _swing_t <= leap_ticks + 2, "landed t=%d swing t=%d" % [leap_ticks, _swing_t])
                _rec("buffered_swing_hits_after_landing", _lost() > 0.0, "lost=%.1f" % _lost())
                _phase = 2
                _t = 0
        2:   # click during Swagger Step (dash): no lunge push, swing after the dash
            _t += 1
            var ds = best.abilities["ability2"]
            if _t == 1:
                _place(best, Vector3.ZERO)
                _place(foe, Vector3(0, 0, -9))
                _combo0 = best.combo_step
                _swing_t = -1
            if _t == 5:
                ds.cooldown.remaining = 0.0
                best.last_wish = Vector3(1, 0, 0)
                ds.activate()
                inp.fire = true
            if _t == 6:
                inp.fire = false
                _vx0 = best.dash_vel.x
            if _t == 7:
                _rec("dash_click_keeps_dash", is_equal_approx(best.dash_vel.x, _vx0) and absf(best.dash_vel.z) < 0.01, "dash_vel=%s" % best.dash_vel)
            if _swing_t < 0 and best.combo_step != _combo0:
                _swing_t = _t
            if _t == 40:
                var dash_end := 5 + int(ceil(float(ds.def.get("duration", 0.16)) * 60.0))
                _rec("dash_click_swings_after_dash", _swing_t >= dash_end, "dash end ~%d swing t=%d" % [dash_end, _swing_t])
                _phase = 3
                _t = 0
        3:   # jumping melee heroes: a mid-air swing never lunges
            _t += 1
            if _hero_j == null:
                if _jumpers.is_empty():
                    best.input_source = Idle.new()
                    done = true
                    return
                _hero_j = _jumpers.pop_front()
                _t = 1
            var h := _hero_j
            if _t == 1:
                for o in [best, nidjo, ubel]:
                    o.input_source = Idle.new()
                _place(h, Vector3(0, 0, 30))
                var p: Dictionary = h.def.get("primary", {})
                _place(foe, Vector3(0, 0, 30 - (float(p.get("range", 3)) + float(p.get("lunge", 3)) * 0.6)))
                h.input_source = inp
            if _t == 4:
                inp.jump = true
            if _t == 12:
                _vx0 = Vector2(h.velocity.x, h.velocity.z).length()
                inp.fire = true
            if _t == 13:
                inp.fire = false
                _rec(String(h.def.get("id", h.name)) + "_air_swing_no_lunge", h.dash_time == 0.0 and Vector2(h.velocity.x, h.velocity.z).length() <= _vx0 + 0.01 and not h.is_on_floor(), "dash=%.2f v=%.2f air=%s" % [h.dash_time, Vector2(h.velocity.x, h.velocity.z).length(), not h.is_on_floor()])
            if _t == 70:
                _place(h, Vector3(-40 * (3 - _jumpers.size()), 0, 0))
                _hero_j = null
