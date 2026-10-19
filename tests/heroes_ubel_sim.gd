extends Node3D
## Integration (Jolt, 60 Hz): Übel's Uninvited Guest ride. She leaps onto an enemy head, rides it while it walks
## (pinned on the head, collision exceptions both ways, MountLink net prop up), attacks it from above with Paper
## Cut and Clean Cut, and every end condition drops her: jump, Shift (no other head), Shift hop to another head
## (timer carries over), knockback, root, cancel_ride (stun hook), the timer, her death and the victim's death.
var results: Array = []
var done := false
var frame := 0
var ubel: Hero
var foe: Hero
var foe2: Hero
var inp := Scripted.new()
var mover := Mover.new()
var hp0 := 0.0
var p0 := Vector3.ZERO
var left0 := 0.0
var _step := 0
var _wait := 0
var _cases: Array = ["jump", "shift", "hop", "knockback", "root", "cancel", "timer", "death", "victim_death"]

class Scripted:
    var jump := false
    var fire := false
    func poll(_h) -> InputFrame:
        var f := InputFrame.new()
        f.jump = jump
        f.fire = fire
        jump = false
        return f

class Idle:
    func poll(_h) -> InputFrame:
        return InputFrame.new()

class Mover:
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
    bs.size = Vector3(200, 1, 200)
    cs.shape = bs
    sb.add_child(cs)
    sb.position = Vector3(0, -0.5, 0)
    add_child(sb)
    ubel = _hero("res://src/heroes/ubel.json", 0, Vector3(0, 0, 0))
    ubel.input_source = inp
    foe = _hero("res://src/heroes/cob.json", 1, Vector3(0, 0, -7))
    foe2 = _hero("res://src/heroes/the_best.json", 1, Vector3(60, 0, 60))

func ride():
    return ubel.abilities["ability1"]

func _place(h: Hero, pos: Vector3) -> void:
    h.global_position = pos
    h.velocity = Vector3.ZERO
    h.health.reset()

func _links() -> Array:
    return get_tree().get_nodes_in_group("net_props").filter(func(n): return String(n.get_meta("net_kind", "")).begins_with("mount:"))

## Puts Übel back on foe's head for the next end-condition case.
func _mount() -> bool:
    for h in [ubel, foe, foe2]:
        if h.dead:
            h.respawn()
    _place(ubel, Vector3(0, 0, 0))
    _place(foe, Vector3(0, 0, -6))
    _place(foe2, Vector3(60, 0, 60))
    ubel.yaw = 0.0
    ubel.rotation.y = 0.0
    ubel.pitch = 0.0
    foe.input_source = Idle.new()
    ride().cooldown.remaining = 0.0
    return ride().activate()

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    match frame:
        10:
            _place(foe2, Vector3(60, 0, 60))
            ubel.yaw = PI   # facing away: nobody in the cone
            ubel.rotation.y = PI
            _rec("no_target_no_leap", not ride().activate() and ride().cooldown.is_ready() and not ride().busy(), "")
            ubel.yaw = 0.0
            ubel.rotation.y = 0.0
            ubel.pitch = 0.0
            _rec("leap_starts", ride().activate() and ride().state == ride().STATE_LEAP and ride().victim == foe, "")
            _rec("cooldown_on_leap", ride().cooldown.remaining > 9.0, "%.2f" % ride().cooldown.remaining)
        40:
            var seat: Vector3 = foe.global_position + Vector3(0, float(foe.def.collider.height), 0)
            _rec("attached_on_head", ride().riding() and ubel.global_position.distance_to(seat) < 0.05, "pos=%s seat=%s" % [ubel.global_position, seat])
            _rec("mounted_on", ubel.mounted_on() == foe, "")
            _rec("collision_exceptions", ubel.get_collision_exceptions().has(foe) and foe.get_collision_exceptions().has(ubel), "")
            var ls := _links()
            _rec("mount_link_prop", ls.size() == 1 and String(ls[0].get_meta("net_kind")) == "mount:%d:%d" % [ubel.net_id, foe.net_id]
                and String(ls[0].get_meta("net_visual")) == "res://src/abilities/mount_link.gd", "%d" % ls.size())
            _rec("targetable_while_riding", ubel.collision_layer == 1 and ubel.visible, "")
            foe.yaw = PI
            foe.rotation.y = PI
            foe.input_source = mover   # victim keeps control and walks (+Z)
            p0 = foe.global_position
        80:
            var walked := foe.global_position.z - p0.z
            var seat: Vector3 = foe.global_position + Vector3(0, float(foe.def.collider.height), 0)
            _rec("victim_keeps_moving", walked > 2.0, "dz=%.2f" % walked)
            _rec("rider_follows", ubel.global_position.distance_to(seat) < 0.2, "d=%.3f" % ubel.global_position.distance_to(seat))
            hp0 = foe.health.hp
            ubel.pitch = -1.2   # looking down at the head
            ubel._try_fire()
        81:
            _rec("melee_hits_victim_while_mounted", hp0 - foe.health.hp >= 24.9, "dmg=%.1f" % (hp0 - foe.health.hp))
            var ahead: Vector3 = Vector3(ubel.look_dir().x, 0, ubel.look_dir().z).normalized()
            _place(foe2, foe.global_position + ahead * 3.5)   # an enemy on the ground in front of the victim
            hp0 = foe.health.hp
            var hp2 := foe2.health.hp
            _rec("clean_cut_while_mounted", ubel.abilities["ability2"].activate(), "")
            _rec("clean_cut_hits_victim", absf(hp0 - foe.health.hp - 60.0) < 0.01, "dmg=%.1f" % (hp0 - foe.health.hp))
            _rec("clean_cut_reaches_ground", absf(hp2 - foe2.health.hp - 60.0) < 0.01, "dmg=%.1f" % (hp2 - foe2.health.hp))
            _rec("still_riding_after_attacks", ride().riding(), "")
            _place(foe2, Vector3(60, 0, 60))
            foe.input_source = Idle.new()
            _step = 0
            _wait = 0
    if frame > 90 and _step < _cases.size():
        _run_case(_cases[_step])
    elif frame > 90 and _step >= _cases.size() and not done:
        _rec("no_links_left", _links().is_empty(), "%d" % _links().size())
        done = true

func _run_case(c: String) -> void:
    _wait += 1
    if _wait == 1:
        ride().end_ride("reset")
        if not _mount():
            _rec("remount_" + c, false, "")
            _step += 1
            _wait = 0
        return
    if _wait < 25:
        return   # leap (0.3 s) + settle
    if _wait == 25:
        if not ride().riding():
            _rec("riding_before_" + c, false, "state=%d" % ride().state)
        left0 = ride().ride_left
        match c:
            "jump":
                inp.jump = true
            "shift":
                ubel._use("ability1")
            "hop":
                _place(foe2, foe.global_position + Vector3(4, 0, 0))
                ubel._use("ability1")
            "knockback":
                foe.knockback(Vector3(0, 0, 1))   # victim pushed: rider stays
                ubel.knockback(Vector3(6, 3, 0))
            "root":
                ubel.apply_root(1.0)
            "cancel":
                ubel.cancel_ride("stun")
            "timer":
                pass
            "death":
                ubel.take_damage(9999, foe, ubel.global_position, "primary")
            "victim_death":
                foe.take_damage(9999, ubel, foe.global_position, "primary")
        return
    var t_end := 280 if c == "timer" else (120 if c == "jump" else 50)
    if _wait < t_end and not (c == "timer" and not ride().busy()):
        return
    var want: String = {"jump": "jump", "shift": "shift", "hop": "hop", "knockback": "knockback", "root": "root", "cancel": "stun",
        "timer": "timer", "death": "death", "victim_death": "victim_death"}[c]
    if c == "hop":
        _rec("hop_to_other_head", ride().riding() and ride().victim == foe2 and ubel.mounted_on() == foe2 and ride().last_end == "hop", "victim=%s end=%s" % [ride().victim, ride().last_end])
        _rec("hop_keeps_timer", ride().ride_left < left0 and ride().ride_left > left0 - 1.0, "%.2f -> %.2f" % [left0, ride().ride_left])
        _rec("hop_unpins_old", not ubel.get_collision_exceptions().has(foe) and ubel.get_collision_exceptions().has(foe2), "")
        _rec("hop_one_link", _links().size() == 1, "%d" % _links().size())
    else:
        _rec("ends_on_" + c, not ride().busy() and ride().last_end == want and ubel.mounted_on() == null, "busy=%s end=%s" % [ride().busy(), ride().last_end])
        _rec("unpinned_" + c, not ubel.get_collision_exceptions().has(foe) and not foe.get_collision_exceptions().has(ubel), "")
        _rec("link_gone_" + c, _links().is_empty(), "%d" % _links().size())
        if c == "jump":
            _rec("jump_hops_off_onto_floor", ubel.global_position.y < 0.2 and ubel.is_on_floor(), "y=%.2f" % ubel.global_position.y)
        if c == "timer":
            _rec("timer_is_ride_time", _wait > 25 + 60 * 3.5 and _wait < 25 + 60 * 4.2, "ticks=%d" % (_wait - 25))
    _step += 1
    _wait = 0
