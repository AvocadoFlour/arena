extends "res://tests/test_base.gd"

func test_ray_sphere() -> void:
    near(HitMath.ray_sphere(Vector3.ZERO, Vector3(0, 0, -1), Vector3(0, 0, -10), 1), 9, 0.001, "hit front")
    check(HitMath.ray_sphere(Vector3.ZERO, Vector3(0, 0, -1), Vector3(3, 0, -10), 1) < 0, "miss to side")
    check(HitMath.ray_sphere(Vector3.ZERO, Vector3(0, 0, -1), Vector3(0, 0, 10), 1) < 0, "behind = miss")

func test_ray_capsule() -> void:
    var base := Vector3(0, 0, -10)
    near(HitMath.ray_capsule(Vector3(0, 1, 0), Vector3(0, 0, -1), base, 1.8, 0.4), 9.6, 0.01, "body hit")
    check(HitMath.ray_capsule(Vector3(0, 2.5, 0), Vector3(0, 0, -1), base, 1.8, 0.4) < 0, "over head misses")
    check(HitMath.ray_capsule(Vector3(0.5, 1, 0), Vector3(0, 0, -1), base, 1.8, 0.4) < 0, "beside misses")

func test_aoe_falloff() -> void:
    near(HitMath.aoe_damage(Vector3.ZERO, 5, 100, Vector3.ZERO), 100, 0.001, "centre full")
    near(HitMath.aoe_damage(Vector3.ZERO, 5, 100, Vector3(5, 0, 0)), 50, 0.001, "edge half")
    near(HitMath.aoe_damage(Vector3.ZERO, 5, 100, Vector3(5.1, 0, 0)), 0, 0.001, "outside zero")

func test_spread_within_cone() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 1
    var d := Vector3(0, 0, -1)
    for i in 200:
        var s := HitMath.spread_dir(d, 5.0, rng)
        check(rad_to_deg(s.angle_to(d)) <= 5.001, "inside cone")
