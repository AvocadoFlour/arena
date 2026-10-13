class_name ToonKit
extends RefCounted
## Reusable toon look for any hero model: flat 2-tone colour (toon.gdshader) + black inverted-hull
## outline (outline.gdshader, next_pass). Colours come from the imported materials' albedo.
const TOON := preload("res://src/heroes/toon/toon.gdshader")
const OUTLINE := preload("res://src/heroes/toon/outline.gdshader")

## Toon-converted meshes, shared by every instance of the same source mesh + settings.
static var _cache: Dictionary = {}

## Applies to every MeshInstance3D under `root`. Surfaces whose material name contains any of
## `no_outline` (e.g. flat face decals) get no outline. Returns number of surfaces converted.
## The toon materials are baked into a shared copy of the mesh (cached per source mesh + settings) instead
## of per-instance surface overrides: cheaper with many heroes, and it avoids an engine error when an
## instance with surface overrides is freed while another instance of the same mesh is alive.
static func apply(root: Node, outline_width: float = 0.011, no_outline: Array = []) -> int:
    var n := 0
    for mi in root.find_children("*", "MeshInstance3D", true, false):
        var mesh: Mesh = mi.mesh
        if mesh == null:
            continue
        var key := "%d|%s|%s" % [mesh.get_instance_id(), outline_width, ",".join(no_outline)]
        if not _cache.has(key):
            var copy: Mesh = mesh.duplicate()
            for i in mesh.get_surface_count():
                var src: Material = mesh.surface_get_material(i)
                var col := Color.WHITE
                var mname := ""
                if src:
                    mname = src.resource_name
                    if src is BaseMaterial3D:
                        col = src.albedo_color
                copy.surface_set_material(i, make(col, outline_width, not no_outline.any(func(k): return mname.contains(k)), mname))
            _cache[key] = copy
        mi.mesh = _cache[key]
        n += mi.mesh.get_surface_count()
    return n

static func make(col: Color, outline_width: float = 0.011, outline: bool = true, name: String = "") -> ShaderMaterial:
    var m := ShaderMaterial.new()
    m.shader = TOON
    m.resource_name = "toon_" + name
    m.set_shader_parameter("albedo", col)
    if outline and outline_width > 0.0:
        var o := ShaderMaterial.new()
        o.shader = OUTLINE
        o.set_shader_parameter("width", outline_width)
        m.next_pass = o
    return m
