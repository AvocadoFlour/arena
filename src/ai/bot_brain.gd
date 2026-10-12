class_name BotBrain
extends RefCounted
## Bot AI as an input source: poll(hero) -> InputFrame (INTERFACES.md section 5).
## States: wander -> chase (when an enemy is visible). Inaccuracy comes from hero.extra_spread_deg.

var spread_deg := 6.0         ## applied by the spawner to hero.extra_spread_deg
var turn_rate := 4.0          ## rad/s
var sight := 40.0
var fire_cone := 0.15         ## rad: fire when aim error below this
var bounds := 17.0            ## wander area half-size
var use_abilities := false    ## demo/autopilot: dash, slam, ultimate
var state := "wander"
var target = null
var _rng := RandomNumberGenerator.new()
var _wander := Vector3.ZERO
var _wander_left := 0.0
var _strafe := 1.0
var _strafe_left := 0.0
var _think := 0.0

func _init(p: Dictionary = {}) -> void:
    _rng.randomize()
    for k in p:
        set(k, p[k])

func poll(h) -> InputFrame:
    var f := InputFrame.new()
    var dt := 1.0 / float(Engine.physics_ticks_per_second)
    _think -= dt
    if _think <= 0.0:
        _think = 0.2
        target = _find_target(h)
    if target and (target.dead or not is_instance_valid(target)):
        target = null
    if target:
        state = "chase"
        var to: Vector3 = (target.global_position + Vector3(0, 1.1, 0)) - h.eye_position()
        var err := _aim(h, f, to, dt)
        var dist := to.length()
        _strafe_left -= dt
        if _strafe_left <= 0.0:
            _strafe = -1.0 if _rng.randf() < 0.5 else 1.0
            _strafe_left = _rng.randf_range(0.8, 2.0)
        var keep := 10.0
        if use_abilities and h.abilities.has("ability2") and h.abilities["ability2"].cooldown.is_ready():
            keep = 3.0   # autopilot closes in to use ground slam
        var fwd := 1.0 if dist > keep else (-0.6 if dist < minf(5.0, keep - 1.0) else 0.0)
        f.move = Vector2(_strafe * 0.7, fwd).limit_length(1.0)
        f.fire = err < fire_cone
        if use_abilities:
            if dist > 9.0 and _rng.randf() < 0.02:
                f.ability1 = true
            if dist < 4.5 or (dist < 6.0 and not h.is_on_floor()):
                f.ability2 = true
            if dist < 9.0 and h.ult.is_full():
                f.ultimate = true
    else:
        state = "wander"
        _wander_left -= dt
        var flat := Vector3(_wander.x - h.global_position.x, 0, _wander.z - h.global_position.z)
        if _wander_left <= 0.0 or flat.length() < 1.5:
            _wander = Vector3(_rng.randf_range(-bounds, bounds), 0, _rng.randf_range(-bounds, bounds))
            _wander_left = _rng.randf_range(3.0, 6.0)
        flat.y = -h.pitch * 3.0
        _aim(h, f, flat, dt)
        f.move = Vector2(0, 1)
    if h.is_on_floor() and f.move.length() > 0.1 and Vector2(h.velocity.x, h.velocity.z).length() < 1.0 and _rng.randf() < 0.1:
        f.jump = true
    if h.weapon.ammo == 0:
        f.reload = true
    return f

## Turns toward `to` (rate-limited). Returns remaining aim error in radians.
func _aim(h, f: InputFrame, to: Vector3, dt: float) -> float:
    var want_yaw := atan2(-to.x, -to.z)
    var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
    var dy := wrapf(want_yaw - h.yaw, -PI, PI)
    var dp: float = want_pitch - h.pitch
    var lim := turn_rate * dt
    f.look = Vector2(clampf(dy, -lim, lim), clampf(dp, -lim, lim))
    return Vector2(dy - f.look.x, dp - f.look.y).length()

func _find_target(h):
    var best = null
    var best_d := sight
    var space = h.get_world_3d().direct_space_state
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o == h or o.dead or o.team == h.team:
            continue
        var d: float = h.global_position.distance_to(o.global_position)
        if d >= best_d:
            continue
        var q := PhysicsRayQueryParameters3D.create(h.eye_position(), o.global_position + Vector3(0, 1.1, 0))
        q.exclude = [h.get_rid()]
        var hit: Dictionary = space.intersect_ray(q)
        if hit.is_empty() or hit.collider == o:
            best = o
            best_d = d
    return best
