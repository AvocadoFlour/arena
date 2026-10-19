extends Node3D
## Integration (Jolt, 60 Hz): physical-path checks that are NOT vision checks (Hero.los_clear: world geometry and
## shield walls block, heroes do not). Niđo's Stand-up Meeting pull (chest -> target centre) and Twin Tails'
## Staccato Note splash (impact point nudged off the surface -> target): a wall between blocks, an open path
## reaches, and a caster facing away / looking at the floor (stand-in for "blinded": the game has no blind
## state, and nothing here reads the view) still reaches. Also: an enemy Firewall (shield wall) blocks the pull.
var results: Array = []
var done := false
var frame := 0
var nid: Hero
var tt: Hero
var foe: Hero
var _cases := ["pull_wall", "pull_shield_wall", "pull_open", "pull_blind", "splash_wall", "splash_open", "splash_blind"]
var _i := 0
var _t := 0
var _wall: Node3D = null
var _shot = null

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
    nid = _hero("res://src/heroes/nidjo.json", 0, Vector3(-40, 0, 0))
    tt = _hero("res://src/heroes/twin_tails.json", 0, Vector3(-40, 0, 30))
    foe = _hero("res://src/heroes/cob.json", 1, Vector3(40, 0, 0))

func _place(h: Hero, pos: Vector3, yaw := 0.0, pitch := 0.0) -> void:
    h.global_position = pos
    h.velocity = Vector3.ZERO
    h.yaw = yaw
    h.pitch = pitch
    h.rotation.y = yaw
    h.health.reset()
    h.slow_mult = 1.0
    h.slow_left = 0.0

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
    var sb := StaticBody3D.new()
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    cs.shape = bs
    sb.add_child(cs)
    add_child(sb)
    sb.global_position = pos
    return sb

func _physics_process(_dt: float) -> void:
    frame += 1
    if done or frame < 5:
        return
    if _i >= _cases.size():
        done = true
        return
    var c: String = _cases[_i]
    _t += 1
    if c.begins_with("pull"):
        if _t == 1:
            _place(nid, Vector3.ZERO, PI if c == "pull_blind" else 0.0, -1.2 if c == "pull_blind" else 0.0)
            _place(foe, Vector3(0, 0, -5))
            if c == "pull_wall":
                _wall = _box(Vector3(0, 1.75, -2.5), Vector3(6, 3.5, 0.2))
            elif c == "pull_shield_wall":
                var fw = foe.abilities["ability2"]   # Cob's Geode Wall, moved between them
                fw.cooldown.remaining = 0.0
                fw.activate()
                fw.wall.global_position = Vector3(0, 1.3, -2.5)
                fw.wall.rotation = Vector3.ZERO
                _wall = fw.wall
        if _t == 3:
            _place(nid, Vector3.ZERO, PI if c == "pull_blind" else 0.0, -1.2 if c == "pull_blind" else 0.0)
            _place(foe, Vector3(0, 0, -5))
            var pl = nid.abilities["ability2"]
            pl.cooldown.remaining = 0.0
            pl.activate()
            var want := c == "pull_open" or c == "pull_blind"
            var got: bool = pl.last_pulled == 1 and foe.slow_mult < 1.0 and foe.velocity.length() > 0.5
            _rec(c + ("_pulls" if want else "_blocked"), got == want and (want or (pl.last_pulled == 0 and foe.slow_mult == 1.0)), "pulled=%d slow=%.2f v=%.2f" % [pl.last_pulled, foe.slow_mult, foe.velocity.length()])
            _next()
    else:
        if _t == 1:
            _place(tt, Vector3(0, 0, 0), PI if c == "splash_blind" else 0.0, -1.2 if c == "splash_blind" else 0.0)
            _wall = _box(Vector3(0, 1.75, -6), Vector3(6, 3.5, 0.2))
            _place(foe, Vector3(0, 0, -7.4) if c == "splash_wall" else Vector3(1.2, 0, -5.1))
        if _t == 3:
            _place(foe, Vector3(0, 0, -7.4) if c == "splash_wall" else Vector3(1.2, 0, -5.1))
            _shot = load("res://src/abilities/projectile_shot.gd").new(tt, tt.abilities["ability2"].def)
            add_child(_shot)
            _shot.launch(Vector3(0, 1.0, -0.6), Vector3(0, 0, -1))   # fixed path, whatever way she looks
        if _t == 25:
            var lost := foe.health.max_hp - foe.health.hp
            var want := c != "splash_wall"
            _rec(c + ("_splash_hits" if want else "_blocked"), (lost > 0.0) == want, "lost=%.1f slow=%.2f" % [lost, foe.slow_mult])
            _next()

func _next() -> void:
    if _wall != null:
        if _wall == foe.abilities["ability2"].wall:
            foe.abilities["ability2"].remove_wall()
        else:
            _wall.queue_free()
    _wall = null
    _place(nid, Vector3(-40, 0, 0))
    _place(tt, Vector3(-40, 0, 30))
    _place(foe, Vector3(40, 0, 0))
    _i += 1
    _t = 0
