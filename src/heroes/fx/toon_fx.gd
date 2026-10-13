class_name ToonFx
extends RefCounted
## Flat toon effect shapes (same look as the hero toon kit: flat colour + black inverted-hull outline).
## All functions spawn self-freeing FxPiece nodes under `parent` (the world) and return them.
## Visual only: no collision, no gameplay state, never sent over the network.
const OUTLINE := 0.018       ## thicker than the heroes' outline so effects read at a distance
static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var enabled := true   ## tests / headless tools may switch effects off

static func mat(c: Color, outline := true) -> ShaderMaterial:
    var key := "%s|%s" % [c.to_html(), outline]
    if not _mats.has(key):
        _mats[key] = ToonKit.make(c, OUTLINE if outline else 0.0, outline, "fx")
    return _mats[key]

static func _mi(mesh: Mesh, c: Color, outline := true) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat(c, outline)
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mi

static func _piece(parent: Node, pos: Vector3, life: float) -> FxPiece:
    var p := FxPiece.new()
    p.life = life
    parent.add_child(p)
    p.global_position = pos
    return p

static func ok(parent) -> bool:
    return enabled and parent != null and is_instance_valid(parent) and parent.is_inside_tree()

# ------------------------------------------------------------------ meshes (shared)
static func ring_mesh() -> Mesh:
    if not _meshes.has("ring"):
        var m := TorusMesh.new()
        m.inner_radius = 0.86
        m.outer_radius = 1.0
        m.rings = 32
        m.ring_segments = 6
        _meshes["ring"] = m
    return _meshes.ring

static func spike_mesh() -> Mesh:   ## flat-ish 4-sided spike along +Y, base at origin
    if not _meshes.has("spike"):
        var m := CylinderMesh.new()
        m.top_radius = 0.0
        m.bottom_radius = 0.5
        m.height = 1.0
        m.radial_segments = 4
        m.rings = 1
        _meshes["spike"] = m
    return _meshes.spike

static func crystal_mesh() -> Mesh:  ## hex crystal along +Y
    if not _meshes.has("crystal"):
        var m := CylinderMesh.new()
        m.top_radius = 0.0
        m.bottom_radius = 0.5
        m.height = 1.0
        m.radial_segments = 6
        m.rings = 1
        _meshes["crystal"] = m
    return _meshes.crystal

static func blob_mesh() -> Mesh:     ## low-poly puff / pebble
    if not _meshes.has("blob"):
        var m := SphereMesh.new()
        m.radius = 0.5
        m.height = 1.0
        m.radial_segments = 7
        m.rings = 4
        _meshes["blob"] = m
    return _meshes.blob

static func box_mesh() -> Mesh:
    if not _meshes.has("box"):
        var m := BoxMesh.new()
        m.size = Vector3.ONE
        _meshes["box"] = m
    return _meshes.box

## Flat crescent (sword arc): angles in degrees around +Y, radius r0..r1, in the XZ plane.
static func arc_mesh(a0: float, a1: float, r0: float, r1: float, n: int = 14) -> Mesh:
    var key := "arc%s|%s|%s|%s" % [a0, a1, r0, r1]
    if _meshes.has(key):
        return _meshes[key]
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var th := 0.04
    for i in n:
        var u0 := float(i) / n
        var u1 := float(i + 1) / n
        var q0 := deg_to_rad(lerpf(a0, a1, u0))
        var q1 := deg_to_rad(lerpf(a0, a1, u1))
        # crescent: thin at both ends, widest in the middle
        var w0 := sin(u0 * PI)
        var w1 := sin(u1 * PI)
        var p := [Vector3(cos(q0), 0, sin(q0)) * r1, Vector3(cos(q1), 0, sin(q1)) * r1,
                  Vector3(cos(q1), 0, sin(q1)) * lerpf(r1, r0, w1), Vector3(cos(q0), 0, sin(q0)) * lerpf(r1, r0, w0)]
        for y in [th, -th]:
            var up := Vector3(0, signf(y), 0)
            var tri := [p[0], p[1], p[2], p[0], p[2], p[3]] if y > 0 else [p[0], p[2], p[1], p[0], p[3], p[2]]
            for v in tri:
                st.set_normal(up)
                st.add_vertex(v + Vector3(0, y, 0))
        # outer + inner rims so the hull outline has thickness
        for e in [[p[0], p[1]], [p[2], p[3]]]:
            var a: Vector3 = e[0]
            var b: Vector3 = e[1]
            var nrm := ((a + b) * 0.5).normalized()
            for v in [a + Vector3(0, th, 0), b + Vector3(0, th, 0), b - Vector3(0, th, 0), a + Vector3(0, th, 0), b - Vector3(0, th, 0), a - Vector3(0, th, 0)]:
                st.set_normal(nrm)
                st.add_vertex(v)
    var m := st.commit()
    _meshes[key] = m
    return m

# ------------------------------------------------------------------ effects
## Expanding flat ring on the ground (or around `normal`).
static func ring(parent: Node, pos: Vector3, radius: float, c: Color, life := 0.45, thickness := 0.08, normal := Vector3.UP) -> FxPiece:
    if not ok(parent):
        return null
    var p := _piece(parent, pos, life)
    p.add_child(_mi(ring_mesh(), c))
    if normal.cross(Vector3.UP).length() > 0.01:
        p.orient = Basis(Quaternion(Vector3.UP, normal.normalized()))
    p.scale_from = Vector3(radius * 0.2, thickness, radius * 0.2)
    p.scale_to = Vector3(radius, thickness, radius)
    p.grow = 0.55
    p.shrink = 0.3
    return p

## Star burst: `n` spikes radiating from pos in the plane perpendicular to `normal`.
static func burst(parent: Node, pos: Vector3, c: Color, n := 8, length := 0.8, life := 0.3, normal := Vector3.UP, width := 0.22) -> Array:
    var out: Array = []
    if not ok(parent):
        return out
    var b := Basis(Quaternion(Vector3.UP, normal.normalized())) if normal.cross(Vector3.UP).length() > 0.01 else Basis()
    if normal.dot(Vector3.UP) < -0.99:
        b = Basis(Vector3.RIGHT, PI)
    for i in n:
        var a := TAU * i / n + randf() * 0.2
        var dir := b * Vector3(cos(a), 0, sin(a))
        var p := _piece(parent, pos, life)
        p.add_child(_mi(spike_mesh(), c))
        p.orient = Basis(Quaternion(Vector3.UP, dir))
        var L := length * randf_range(0.7, 1.15)
        p.scale_from = Vector3(width * 0.5, L * 0.2, width * 0.15)
        p.scale_to = Vector3(width, L, width * 0.35)
        p.drift = dir * L * 1.5
        p.drag = 6.0
        p.grow = 0.35
        p.shrink = 0.45
        out.append(p)
    return out

## Chunks (rocks / puffs) thrown outward and up, falling with gravity.
static func chunks(parent: Node, pos: Vector3, c: Color, n := 6, size := 0.25, speed := 4.0, up := 4.0, life := 0.7, gravity := 14.0, mesh_kind := "blob") -> Array:
    var out: Array = []
    if not ok(parent):
        return out
    var mesh := crystal_mesh() if mesh_kind == "crystal" else (box_mesh() if mesh_kind == "box" else blob_mesh())
    for i in n:
        var a := TAU * i / n + randf() * 0.5
        var p := _piece(parent, pos, life)
        p.add_child(_mi(mesh, c))
        var s := size * randf_range(0.7, 1.3)
        p.scale_from = Vector3.ONE * s * 0.5
        p.scale_to = Vector3.ONE * s
        p.drift = Vector3(cos(a), 0, sin(a)) * speed * randf_range(0.6, 1.1) + Vector3(0, up * randf_range(0.7, 1.2), 0)
        p.gravity = gravity
        p.spin = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 8.0
        p.grow = 0.15
        p.shrink = 0.3
        out.append(p)
    return out

## Puff of dust/cloud that grows and drifts.
static func puff(parent: Node, pos: Vector3, c: Color, size := 0.4, life := 0.4, vel := Vector3(0, 0.6, 0)) -> FxPiece:
    if not ok(parent):
        return null
    var p := _piece(parent, pos, life)
    p.add_child(_mi(blob_mesh(), c))
    p.scale_from = Vector3.ONE * size * 0.4
    p.scale_to = Vector3(size, size * 0.75, size)
    p.drift = vel
    p.drag = 3.0
    p.grow = 0.4
    p.shrink = 0.4
    return p

## Eighth-note glyph (head + stem + flag), facing +Z of its basis.
static func note_node(c: Color) -> Node3D:
    var n := Node3D.new()
    var head := _mi(blob_mesh(), c)
    head.scale = Vector3(0.34, 0.26, 0.2)
    head.rotation.z = 0.4
    n.add_child(head)
    var stem := _mi(box_mesh(), c)
    stem.scale = Vector3(0.05, 0.55, 0.05)
    stem.position = Vector3(0.14, 0.3, 0)
    n.add_child(stem)
    var flag := _mi(box_mesh(), c)
    flag.scale = Vector3(0.22, 0.07, 0.05)
    flag.position = Vector3(0.24, 0.5, 0)
    flag.rotation.z = -0.6
    n.add_child(flag)
    return n

static func note(parent: Node, pos: Vector3, c: Color, life := 0.9, vel := Vector3(0, 1.5, 0), size := 1.0) -> FxPiece:
    if not ok(parent):
        return null
    var p := _piece(parent, pos, life)
    p.add_child(note_node(c))
    p.scale_from = Vector3.ONE * size * 0.3
    p.scale_to = Vector3.ONE * size
    p.drift = vel
    p.spin = Vector3(0, 2.5, 0)
    p.grow = 0.2
    p.shrink = 0.3
    return p

## Plus / cross glyph (heal pop).
static func plus(parent: Node, pos: Vector3, c: Color, size := 0.45, life := 0.6) -> FxPiece:
    if not ok(parent):
        return null
    var p := _piece(parent, pos, life)
    for r in [0.0, PI * 0.5]:
        var b := _mi(box_mesh(), c)
        b.scale = Vector3(1.0, 0.3, 0.3)
        b.rotation.z = r
        p.add_child(b)
    p.scale_from = Vector3.ONE * size * 0.3
    p.scale_to = Vector3.ONE * size
    p.drift = Vector3(0, 1.4, 0)
    p.spin = Vector3(0, 3.0, 0)
    p.grow = 0.25
    p.shrink = 0.3
    return p

## Flat bar between a and b (speed line / streak).
static func streak(parent: Node, a: Vector3, b: Vector3, c: Color, width := 0.08, life := 0.2) -> FxPiece:
    if not ok(parent) or a.distance_to(b) < 0.05:
        return null
    var p := _piece(parent, (a + b) * 0.5, life)
    var mi := _mi(box_mesh(), c)
    p.add_child(mi)
    var up := Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT
    p.orient = Basis.looking_at(b - a, up)
    var L := a.distance_to(b)
    p.scale_from = Vector3(width, width * 0.5, L)
    p.scale_to = Vector3(width, width * 0.5, L)
    p.grow = 0.01
    p.shrink = 0.6
    return p

## Crystal spike rising out of the ground (stays `life`, shrinks back at the end).
static func crystal(parent: Node, pos: Vector3, c: Color, height := 1.0, width := 0.35, life := 1.0, tilt := Vector3.ZERO) -> FxPiece:
    if not ok(parent):
        return null
    var p := _piece(parent, pos, life)
    p.add_child(_mi(crystal_mesh(), c))
    p.orient = Basis.from_euler(tilt)
    p.scale_from = Vector3(width * 0.4, 0.05, width * 0.4)
    p.scale_to = Vector3(width, height, width)
    p.grow = clampf(0.18 / life, 0.02, 0.4)
    p.shrink = clampf(0.25 / life, 0.02, 0.4)
    return p

## Flat sword-arc crescent at `xf` (arc in the local XZ plane, opening toward local -Z).
static func arc(parent: Node, xf: Transform3D, c: Color, a0 := 200.0, a1 := 340.0, r0 := 0.9, r1 := 2.0, life := 0.22) -> FxPiece:
    if not ok(parent):
        return null
    var p := _piece(parent, xf.origin, life)
    p.orient = xf.basis
    p.add_child(_mi(arc_mesh(a0, a1, r0, r1), c))
    p.scale_from = Vector3.ONE * 0.85
    p.scale_to = Vector3.ONE
    p.grow = 0.3
    p.shrink = 0.5
    return p
