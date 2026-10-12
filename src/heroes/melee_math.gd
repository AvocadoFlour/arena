class_name MeleeMath
extends RefCounted
## Pure melee hit test (unit-tested): target within `rng` (horizontal) and within half-angle `half_arc`
## (radians) of the horizontal forward vector `fwd`.
static func in_arc(origin: Vector3, fwd: Vector3, target: Vector3, rng: float, half_arc: float) -> bool:
    var to := Vector3(target.x - origin.x, 0, target.z - origin.z)
    var d := to.length()
    if d > rng:
        return false
    if d < 0.3:
        return true
    return fwd.angle_to(to) <= half_arc
