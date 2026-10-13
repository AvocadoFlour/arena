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

## Geode crystal wall: a staggered row of outlined toon crystals filling the box (`size`, centred), plus a
## faint translucent plate so the collision extent stays readable.
static func crystal_wall(size: Vector3, color: Color) -> Node3D:
    var root := Node3D.new()
    root.name = "CrystalWall"
    var n := maxi(3, int(ceil(size.x / 0.55)))
    for row in 2:
        for i in n:
            var u := (float(i) + 0.5 * row) / float(n) - 0.5 + 0.5 / float(n) * (1 - row)
            if u > 0.5:
                continue
            var h := size.y * (0.75 + 0.25 * absf(sin(float(i) * 2.3 + row)))
            if row == 1:
                h *= 0.7
            var w := size.x / float(n) * (1.25 if row == 0 else 1.0)
            var mi := ToonFx._mi(ToonFx.crystal_mesh(), AMBER if (i + row) % 4 == 1 else color)
            mi.scale = Vector3(w, h, maxf(w * 0.7, size.z * 1.4))
            mi.position = Vector3(u * size.x, -size.y * 0.5 + h * 0.5, (row - 0.5) * size.z * 0.6)
            mi.rotation.z = sin(float(i) * 1.7 + row) * 0.12
            root.add_child(mi)
    var plate := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    plate.mesh = bm
    var m := StandardMaterial3D.new()
    m.albedo_color = Color(color.r, color.g, color.b, 0.16)
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    plate.material_override = m
    plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(plate)
    return root
