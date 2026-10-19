extends Node3D
## Integration (Jolt, 60 Hz): close-range and area damage needs a clear line (Hero.can_hit / Hero.los_clear).
## For every path - Übel Paper Cut (+ The Best's lunge target search), Clean Cut, The Best's Fearless Leap landing,
## Cob's Boulder Roll and Quarry Quake, Übel's Last Smile, Tomo's Force Push - an enemy in the open is hit, an
## enemy behind a world wall is not, and an enemy behind an enemy Geode Wall (real shield_wall node) is not.
## Breakable cover behind a world wall is not hit (melee, slam) but in the open it is; the hero Übel rides is
## still hit (Paper Cut, Clean Cut) even with geometry between their chests.
var results: Array = []
var done := false
var frame := 0
var ubel: Hero
var best: Hero
var cob: Hero
var tomo: Hero
var dummy: Hero
var waller: Hero
var cover: Cover = null
var _cases: Array = []
var _i := 0
var _wait := 0
var _obstacle: Node3D = null
var _hp0 := 0.0

class Idle:
    func poll(_h) -> InputFrame:
        return InputFrame.new()

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
    bs.size = Vector3(200, 1, 200)
    cs.shape = bs
    sb.add_child(cs)
    sb.position = Vector3(0, -0.5, 0)
    add_child(sb)
    ubel = _hero("res://src/heroes/ubel.json", 0, Vector3(-40, 0, 0))
    best = _hero("res://src/heroes/the_best.json", 0, Vector3(-40, 0, 20))
    cob = _hero("res://src/heroes/cob.json", 0, Vector3(-40, 0, 40))
    tomo = _hero("res://src/heroes/tomo.json", 0, Vector3(-40, 0, 60))
    dummy = _hero("res://src/heroes/twin_tails.json", 1, Vector3(40, 0, 0))
    waller = _hero("res://src/heroes/cob.json", 1, Vector3(40, 0, 40))
    # [name, attacker, target distance, wall distance]
    var paths := [["paper_cut", ubel, 2.0, 1.0], ["lunge", best, 7.0, 3.0], ["clean_cut", ubel, 3.5, 1.5],
        ["leap_landing", best, 2.2, 1.1], ["boulder_roll", cob, 1.55, 0.78], ["quarry_quake", cob, 4.0, 2.0],
        ["last_smile", ubel, 3.0, 1.5], ["force_push", tomo, 4.0, 2.0]]
    for p in paths:
        for ob in ["open", "world_wall", "shield_wall"]:
            _cases.append([p[0], p[1], p[2], p[3], ob, "hero"])
    for p in [["paper_cut", ubel, 2.0, 1.0], ["quarry_quake", cob, 3.0, 1.5]]:
        for ob in ["open", "world_wall"]:
            _cases.append([p[0], p[1], p[2], p[3], ob, "cover"])

func _place(h: Hero, pos: Vector3, yaw := 0.0) -> void:
    h.global_position = pos
    h.velocity = Vector3.ZERO
    h.yaw = yaw
    h.pitch = 0.0
    h.rotation.y = yaw
    h.dash_time = 0.0
    h.health.reset()
    h.overheal = 0.0

func _park_all() -> void:
    _place(ubel, Vector3(-40, 0, 0))
    _place(best, Vector3(-40, 0, 20))
    _place(cob, Vector3(-40, 0, 40))
    _place(tomo, Vector3(-40, 0, 60))
    _place(dummy, Vector3(40, 0, 0))
    _place(waller, Vector3(40, 0, 40))

func _make_obstacle(kind: String, mid: float) -> void:
    if kind == "world_wall":
        var sb := StaticBody3D.new()
        var cs := CollisionShape3D.new()
        var bs := BoxShape3D.new()
        bs.size = Vector3(6, 3.5, 0.1)
        cs.shape = bs
        sb.add_child(cs)
        add_child(sb)
        sb.global_position = Vector3(0, 1.75, -mid)
        _obstacle = sb
    elif kind == "shield_wall":
        var ab = waller.abilities["ability2"]
        ab.cooldown.remaining = 0.0
        ab.activate()
        ab.wall.global_position = Vector3(0, 1.3, -mid)
        ab.wall.rotation = Vector3.ZERO
        _obstacle = ab.wall

func _clear_obstacle() -> void:
    if _obstacle != null:
        if _obstacle == waller.abilities["ability2"].wall:
            waller.abilities["ability2"].remove_wall()
        else:
            _obstacle.queue_free()
    _obstacle = null
    if cover != null:
        cover.queue_free()
        cover = null

func _act(nm: String, a: Hero) -> void:
    match nm:
        "paper_cut", "lunge":
            a.combo_left = 0.0
            a.melee_swing()
        "clean_cut":
            a.abilities["ability2"]._do()
        "leap_landing":
            var lp = a.abilities["ability1"]
            lp.airborne = true
            lp.on_landed()
        "boulder_roll":
            var ch = a.abilities["ability1"]
            ch.hit = []
            ch.left = 0.5
            ch.tick(0.001)
            ch.left = 0.0
        "quarry_quake":
            a.abilities["ultimate"]._impact()
        "last_smile", "force_push":
            a.ult.charge = a.ult.cost
            a.abilities["ultimate"].cooldown.remaining = 0.0
            a.abilities["ultimate"]._do()

func _physics_process(_dt: float) -> void:
    frame += 1
    if done or frame < 5:
        return
    if _i >= _cases.size():
        _ride_case()
        return
    var c: Array = _cases[_i]
    var nm: String = c[0]
    var a: Hero = c[1]
    var d: float = c[2]
    var mid: float = c[3]
    var ob: String = c[4]
    var tgt: String = c[5]
    _wait += 1
    if _wait == 1:
        _park_all()
        _make_obstacle(ob, mid)
        if tgt == "cover":
            cover = Cover.new()
            add_child(cover)
            cover.global_position = Vector3(0, 0.5, -d)
    if _wait < 3:
        return
    _place(a, Vector3.ZERO)
    if tgt == "hero":
        _place(dummy, Vector3(0, 0, -d), PI)
    _act(nm, a)
    var label := "%s_%s_%s" % [nm, tgt, ob]
    var lost := dummy.health.max_hp - dummy.health.hp
    var want_hit := ob == "open"
    if nm == "lunge":
        _rec(label + ("_lunges" if want_hit else "_no_lunge"), (a.dash_time > 0.0) == want_hit, "dash=%.2f lost=%.1f" % [a.dash_time, lost])
    elif tgt == "cover":
        _rec(label + ("_hit" if want_hit else "_blocked"), (cover.taken > 0.0) == want_hit, "taken=%.1f" % cover.taken)
    else:
        _rec(label + ("_hit" if want_hit else "_blocked"), (lost > 0.0) == want_hit, "lost=%.1f" % lost)
    _clear_obstacle()
    _park_all()
    _i += 1
    _wait = 0

## Übel rides the dummy; a slab between her chest and its chest does not stop Paper Cut or Clean Cut on it.
var _rs := 0
var _slab: StaticBody3D = null
func _ride_case() -> void:
    _rs += 1
    var r = ubel.abilities["ability1"]
    if _rs == 1:
        _park_all()
        _place(ubel, Vector3(0, 0, 0))
        _place(dummy, Vector3(0, 0, -4), PI)
        r.cooldown.remaining = 0.0
        r.activate()
        return
    if _rs < 45:
        return
    if _rs == 45:
        _rec("ride_mounted", r.riding() and ubel.mounted_on() == dummy, "state=%s" % r.state)
        _slab = StaticBody3D.new()
        var cs := CollisionShape3D.new()
        var bs := BoxShape3D.new()
        bs.size = Vector3(0.1, 4, 4)
        cs.shape = bs
        _slab.add_child(cs)
        add_child(_slab)
        _slab.global_position = dummy.global_position + Vector3(0.25, 1.5, 0)
        return
    if _rs == 47:
        var lp := ubel.chest()
        _rec("ride_slab_blocks_line", not Hero.los_clear(ubel, ubel.chest() + Vector3(0.6, 0, 0), dummy.chest(), dummy), "chest=%s" % lp)
        dummy.health.reset()
        ubel.combo_left = 0.0
        ubel.melee_swing()
        var l1 := dummy.health.max_hp - dummy.health.hp
        dummy.health.reset()
        ubel.abilities["ability2"]._do()
        var l2 := dummy.health.max_hp - dummy.health.hp
        _rec("ride_target_hit_by_paper_cut", l1 > 0.0, "lost=%.1f" % l1)
        _rec("ride_target_hit_by_clean_cut", l2 > 0.0, "lost=%.1f" % l2)
        _rec("ride_exempt_in_can_hit", ubel.can_hit(dummy), "")
        r.end_ride("shift")
        _slab.queue_free()
        done = true
