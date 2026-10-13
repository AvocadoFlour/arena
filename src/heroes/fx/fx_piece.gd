class_name FxPiece
extends Node3D
## One short-lived toon effect piece (client-side, visual only). Animates itself from its own clock and
## frees itself at the end of `life`: moves with `drift` (+ `gravity`), spins, and scales with a "pop" curve
## (grow to `scale_to` in the first `grow` fraction, hold, shrink to zero at the end) - toon effects
## vanish by shrinking instead of alpha fades, so they stay flat and opaque with clean outlines.
var life := 0.5
var t := 0.0
var drift := Vector3.ZERO
var gravity := 0.0
var drag := 0.0
var spin := Vector3.ZERO
var scale_from := Vector3.ONE * 0.2
var scale_to := Vector3.ONE
var grow := 0.25
var shrink := 0.35          ## last fraction of life spent shrinking to 0
var orient := Basis()     ## rotation part; scale is applied on top every frame (set this, not `basis`)
var follow: Node3D = null   ## optional: stays offset from this node (e.g. aura at a hero's feet)
var follow_off := Vector3.ZERO

func _ready() -> void:
    add_to_group("toon_fx")
    basis = orient * Basis.from_scale(scale_from)

func _process(dt: float) -> void:
    t += dt
    if t >= life:
        queue_free()
        return
    var k := t / life
    if follow != null:
        if is_instance_valid(follow):
            global_position = follow.global_position + follow_off
    else:
        drift.y -= gravity * dt
        drift *= maxf(0.0, 1.0 - drag * dt)
        position += drift * dt
    if spin != Vector3.ZERO:
        orient = orient * Basis.from_euler(spin * dt)
    var s: Vector3
    if k < grow:
        var e := k / maxf(grow, 0.001)
        s = scale_from.lerp(scale_to, 1.0 - (1.0 - e) * (1.0 - e))   # ease-out
    elif k > 1.0 - shrink:
        var e := (k - (1.0 - shrink)) / maxf(shrink, 0.001)
        s = scale_to * maxf(0.001, 1.0 - e * e)
    else:
        s = scale_to
    basis = orient * Basis.from_scale(s.max(Vector3.ONE * 0.001))
