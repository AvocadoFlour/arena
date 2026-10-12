extends Node3D
## Integration test: real Jolt physics, fixed 60 Hz tick, capsule CharacterBody3D vs box colliders.
const CFG := {"speed": 7.0, "jump_velocity": 8.5, "gravity": 22}
var body: CharacterBody3D
var frame := 0
var results: Array = []
var done := false
var apex := 0.0
var z0 := 0.0

func _box(pos: Vector3, size: Vector3) -> void:
    var sb := StaticBody3D.new()
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    cs.shape = bs
    sb.add_child(cs)
    sb.position = pos
    add_child(sb)

func _ready() -> void:
    _box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
    _box(Vector3(2.5, 2, 0), Vector3(1, 4, 40))        # wall face at x = 2.0
    _box(Vector3(-6, 0.5, 0), Vector3(2, 1, 2))        # 1 m block to land on
    body = CharacterBody3D.new()
    var cs := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = 0.4
    cap.height = 1.8
    cs.shape = cap
    cs.position.y = 0.9
    body.add_child(cs)
    body.floor_snap_length = 0.25
    add_child(body)
    body.global_position = Vector3(0, 3, 0)

func _rec(name: String, ok: bool, info: String) -> void:
    results.append([name, ok, info])

func _physics_process(dt: float) -> void:
    if done:
        return
    frame += 1
    var wish := Vector3.ZERO
    var jump := false
    if frame > 60 and frame <= 150:
        wish = Vector3(1, 0, -1).normalized()   # diagonal into the wall
    if frame == 151:
        jump = true
    body.velocity = Motion.step_velocity(body.velocity, wish, body.is_on_floor(), jump, CFG, dt)
    body.move_and_slide()
    if frame == 60:
        _rec("falls_and_lands_on_floor", body.is_on_floor() and absf(body.global_position.y) < 0.05, "y=%.3f floor=%s" % [body.global_position.y, body.is_on_floor()])
        z0 = body.global_position.z
    if frame == 150:
        var x := body.global_position.x
        var dz := z0 - body.global_position.z
        _rec("blocked_by_wall", x <= 1.6 + 0.02, "x=%.3f (wall at 2.0, radius 0.4)" % x)
        _rec("slides_along_wall", dz > 4.0, "slid dz=%.2f m" % dz)
    if frame > 151:
        apex = maxf(apex, body.global_position.y)
    if frame == 260:
        _rec("jump_apex", absf(apex - 8.5 * 8.5 / 44.0) < 0.15, "apex=%.3f want~%.3f" % [apex, 8.5 * 8.5 / 44.0])
        _rec("lands_after_jump", body.is_on_floor(), "y=%.3f" % body.global_position.y)
        done = true
