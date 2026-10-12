class_name Motion
extends RefCounted
## Pure velocity integration for the fixed 60 Hz physics tick.
## Collision (capsule vs boxes, sliding along walls) is CharacterBody3D.move_and_slide().

const GRAVITY := 22.0

## cfg: {speed, accel_ground, accel_air, jump_velocity, gravity}
static func step_velocity(v: Vector3, wish: Vector3, on_floor: bool, jump: bool, cfg: Dictionary, dt: float) -> Vector3:
    var speed := float(cfg.get("speed", 7.0))
    var accel := float(cfg.get("accel_ground", 70.0)) if on_floor else float(cfg.get("accel_air", 18.0))
    var w := Vector3(wish.x, 0.0, wish.z)
    if w.length() > 1.0:
        w = w.normalized()
    var h := Vector3(v.x, 0.0, v.z).move_toward(w * speed, accel * dt)
    var vy := v.y
    if on_floor:
        if jump:
            vy = float(cfg.get("jump_velocity", 8.5))
        elif vy < 0.0:
            vy = 0.0
    else:
        vy -= float(cfg.get("gravity", GRAVITY)) * dt
    return Vector3(h.x, vy, h.z)
