class_name TailSway
extends SkeletonModifier3D
## Procedural sway on hair-tail bone chains, applied after the AnimationTree pose (visual only).
## The owner sets `fwd`, `side`, `air`, `run` each frame from replicated state (velocity, on-floor).
var chains: Array = []      ## Array of Array[int] bone indices, root first
var fwd := 0.0
var side := 0.0
var air := 0.0
var run := 0.0
var t := 0.0

func setup(skel: Skeleton3D, prefixes: Array) -> void:
    for p in prefixes:
        # one chain per side suffix (tail_0.L..tail_4.L and tail_0.R..), root first
        var by_side := {}
        for i in skel.get_bone_count():
            var n := skel.get_bone_name(i)
            if n.begins_with(p):
                var sfx := n.get_extension()
                if not by_side.has(sfx):
                    by_side[sfx] = []
                by_side[sfx].append(i)
        for sfx in by_side:
            chains.append(by_side[sfx])

func _process_modification() -> void:
    var skel := get_skeleton()
    if skel == null:
        return
    t += get_process_delta_time() if is_inside_tree() else 0.016
    var f := clampf(fwd, -1.0, 1.0)
    var sd := clampf(side, -1.0, 1.0)
    var a := clampf(air, 0.0, 1.0)
    for ci in chains.size():
        var chain: Array = chains[ci]
        var ph := float(ci) * 1.7
        for k in chain.size():
            var b: int = chain[k]
            var w := 0.08 + 0.04 * k           # small per-bone angles; they accumulate down the chain
            # trail backwards with forward speed, lift when airborne, idle sway, run bounce
            var ax := (f * 0.25 + a * 0.3 + sin(t * 2.3 + ph + k * 0.6) * 0.035 + sin(t * 11.0 + k) * 0.03 * run) * w
            var az := (-sd * 0.4 + sin(t * 1.6 + ph + k * 0.5) * 0.04) * w
            var q := skel.get_bone_pose_rotation(b)
            skel.set_bone_pose_rotation(b, q * Quaternion(Vector3.RIGHT, ax) * Quaternion(Vector3.FORWARD, az))   # bone-local
