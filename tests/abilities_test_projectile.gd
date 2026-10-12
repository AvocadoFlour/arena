extends "res://tests/test_base.gd"
## Projectile kinematics (pure).
const Shot := preload("res://src/abilities/projectile_shot.gd")

func test_straight_flight() -> void:
    var p := Vector3.ZERO
    var v := Vector3(0, 0, -30)
    for i in 60:
        var r := Shot.step(p, v, 0.0, 1.0 / 60.0)
        p = r[0]
        v = r[1]
    near(p.z, -30.0, 0.001, "30 m in 1 s")
    near(p.y, 0.0, 0.001, "no drop")

func test_gravity_drop() -> void:
    var p := Vector3.ZERO
    var v := Vector3(0, 0, -20)
    for i in 60:
        var r := Shot.step(p, v, 10.0, 1.0 / 60.0)
        p = r[0]
        v = r[1]
    near(v.y, -10.0, 0.001, "vy after 1 s")
    near(p.y, -5.0, 0.1, "drop ~ g t^2 / 2")

func test_registry_has_types() -> void:
    for t in ["projectile", "shield_wall", "charge", "heal_beam", "rally", "leap", "team_buff"]:
        check(AbilityRegistry.TYPES.has(t), t)
