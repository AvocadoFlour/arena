extends RefCounted
## Toon visual for Tomo's Breakpoint marker (net-prop visual hook, INTERFACES §10: ability def
## "visual": "res://src/abilities/breakpoint_visual.gd"): a spinning red diamond with a white core ring, built
## the same on host and clients. Visual only, deterministic.
static func build_prop(_kind: String, size: Vector3, color: Color) -> Node3D:
    var n := Node3D.new()
    n.set_script(load("res://src/abilities/prop_spin.gd"))
    n.name = "BreakpointMarker"
    var s := maxf(size.x, 0.12) * 1.6
    for up in [1.0, -1.0]:   # octahedron from two 4-sided cones
        var mi := MeshInstance3D.new()
        var cm := CylinderMesh.new()
        cm.top_radius = 0.0
        cm.bottom_radius = s
        cm.height = s * 1.3
        cm.radial_segments = 4
        cm.rings = 1
        mi.mesh = cm
        mi.position.y = up * s * 0.65
        mi.rotation.x = 0.0 if up > 0.0 else PI
        mi.material_override = ToonFx.mat(color)
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        n.add_child(mi)
    var ring := MeshInstance3D.new()
    var tm := TorusMesh.new()
    tm.inner_radius = s * 1.1
    tm.outer_radius = s * 1.35
    tm.rings = 12
    tm.ring_segments = 4
    ring.mesh = tm
    ring.rotation.x = PI * 0.5
    ring.material_override = ToonFx.mat(Color.WHITE, false)
    ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    n.add_child(ring)
    return n
