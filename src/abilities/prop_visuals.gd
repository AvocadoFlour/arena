extends RefCounted
## Toon visuals for networked props (core R9 hook, INTERFACES §10): ability defs set
## "visual": "res://src/abilities/prop_visuals.gd". Used by remote clients (Net.make_prop) and by the host's
## own gameplay nodes, so everyone sees the same thing. Visual only: the collision box is added by core
## (clients) or by the ability (host) and is unchanged. Layout is deterministic, so all peers match.
const AMBER := Color("#f59a33")

static func build_prop(kind: String, size: Vector3, color: Color) -> Node3D:
    if kind == "wall":
        return crystal_wall(size, color)
    return note(color)

## Spinning eighth-note glyph (Staccato Note).
static func note(color: Color) -> Node3D:
    var n := Node3D.new()
    n.set_script(load("res://src/abilities/prop_spin.gd"))
    n.name = "NoteGlyph"
    var g := ToonFx.note_node(color)
    g.scale = Vector3.ONE * 1.3
    n.add_child(g)
    return n

## Geode crystal wall: faceted hex prisms filling the box (`size`, centred): a row of tall base columns,
## then a denser band of smaller tilted crystals along the top edge, plus a faint translucent plate so the
## collision extent stays readable. Layout comes from a fixed-seed RNG (same on every peer).
static func crystal_wall(size: Vector3, color: Color) -> Node3D:
    var root := Node3D.new()
    root.name = "CrystalWall"
    var rng := RandomNumberGenerator.new()
    rng.seed = 7331 + int(size.x * 100.0) * 31 + int(size.y * 100.0)
    var light := color.lightened(0.35)
    var cols: Array = [color, color, light, AMBER]
    # tiers: [count per metre, height frac lo, hi, width (m) lo, hi, base y frac lo, hi, max tilt]
    var tiers := [[1.8, 0.62, 0.9, 0.42, 0.6, 0.0, 0.05, 0.12],
                  [2.6, 0.32, 0.5, 0.26, 0.4, 0.38, 0.55, 0.35],
                  [3.6, 0.2, 0.3, 0.16, 0.26, 0.66, 0.8, 0.55]]
    for ti in tiers.size():
        var t: Array = tiers[ti]
        var n := maxi(3, int(round(size.x * float(t[0]))))
        for i in n:
            var u := (float(i) + 0.5 + rng.randf_range(-0.3, 0.3)) / float(n) - 0.5
            var h := size.y * rng.randf_range(t[1], t[2])
            var w := rng.randf_range(t[3], t[4])
            var mi := ToonFx._mi(ToonFx.prism_mesh(), cols[rng.randi() % cols.size()])
            mi.scale = Vector3(w, h, w)
            mi.position = Vector3(u * (size.x - w * 0.6), -size.y * 0.5 + size.y * rng.randf_range(t[5], t[6]), rng.randf_range(-0.4, 0.4) * size.z)
            var tilt: float = t[7]
            mi.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-tilt, tilt) - u * 0.35 * (ti / 2.0))
            root.add_child(mi)
    var plate := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    plate.mesh = bm
    plate.material_override = ToonFx.glow_mat(color, 0.14)
    plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(plate)
    return root
