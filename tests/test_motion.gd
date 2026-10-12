extends "res://tests/test_base.gd"
const CFG := {"speed": 7.0, "accel_ground": 70, "accel_air": 18, "jump_velocity": 8.5, "gravity": 22}

func test_gravity_accumulates() -> void:
    var v := Vector3.ZERO
    for i in 60:
        v = Motion.step_velocity(v, Vector3.ZERO, false, false, CFG, 1.0 / 60.0)
    near(v.y, -22, 0.01, "1s of gravity")

func test_jump_only_on_floor() -> void:
    near(Motion.step_velocity(Vector3.ZERO, Vector3.ZERO, true, true, CFG, 1.0 / 60.0).y, 8.5, 0.001, "jump")
    check(Motion.step_velocity(Vector3.ZERO, Vector3.ZERO, false, true, CFG, 1.0 / 60.0).y < 0, "no air jump")

func test_accel_to_max_speed() -> void:
    var v := Vector3.ZERO
    for i in 30:
        v = Motion.step_velocity(v, Vector3(0, 0, -1), true, false, CFG, 1.0 / 60.0)
    near(Vector3(v.x, 0, v.z).length(), 7.0, 0.001, "capped at speed")
    v = Motion.step_velocity(Vector3.ZERO, Vector3(5, 0, 5), true, false, CFG, 1.0)
    near(Vector3(v.x, 0, v.z).length(), 7.0, 0.001, "wish normalized")
