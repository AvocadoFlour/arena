class_name HitMath
extends RefCounted
## Pure hit-detection helpers (unit-tested; the game uses physics raycasts for walls).

## Distance along normalized ray d to sphere, or -1.0 on miss.
static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
    var oc := o - c
    var b := oc.dot(d)
    var cc := oc.dot(oc) - r * r
    var disc := b * b - cc
    if disc < 0.0:
        return -1.0
    var s := sqrt(disc)
    var t := -b - s
    if t < 0.0:
        t = -b + s
    return t if t >= 0.0 else -1.0

## Ray vs vertical capsule (feet at base, total height h, radius r). -1.0 on miss.
static func ray_capsule(o: Vector3, d: Vector3, base: Vector3, h: float, r: float, max_t: float = 1000.0) -> float:
    var best := -1.0
    var steps := 64
    for i in steps + 1:
        var t := max_t * float(i) / float(steps)
        var p := o + d * t
        var y := clampf(p.y, base.y + r, base.y + h - r)
        var c := Vector3(base.x, y, base.z)
        var hit := ray_sphere(o, d, c, r)
        if hit >= 0.0 and (best < 0.0 or hit < best):
            best = hit
    return best

## Linear falloff: full damage at centre, 50% at the edge, 0 outside.
static func aoe_damage(center: Vector3, radius: float, base: float, target: Vector3) -> float:
    var dist := center.distance_to(target)
    if dist > radius:
        return 0.0
    return base * lerpf(1.0, 0.5, dist / radius)

## Random direction inside a cone of half-angle deg around dir.
static func spread_dir(dir: Vector3, deg: float, rng: RandomNumberGenerator) -> Vector3:
    var n := dir.normalized()
    if deg <= 0.0:
        return n
    var perp := n.cross(Vector3.UP)
    if perp.length() < 0.01:
        perp = n.cross(Vector3.RIGHT)
    perp = perp.normalized()
    var perp2 := n.cross(perp).normalized()
    var a := deg_to_rad(deg) * sqrt(rng.randf())
    var th := rng.randf() * TAU
    return (n * cos(a) + (perp * cos(th) + perp2 * sin(th)) * sin(a)).normalized()
