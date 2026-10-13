class_name ToonKit
extends RefCounted
## Reusable toon look for any hero model: flat 2-tone colour (toon.gdshader) + black inverted-hull
## outline (outline.gdshader, next_pass). Colours come from the imported materials' albedo.
const TOON := preload("res://src/heroes/toon/toon.gdshader")
const OUTLINE := preload("res://src/heroes/toon/outline.gdshader")

## Applies to every MeshInstance3D under `root`. Surfaces whose material name contains any of
## `no_outline` (e.g. flat face decals) get no outline. Returns number of surfaces converted.
static func apply(root: Node, outline_width: float = 0.008, no_outline: Array = []) -> int:
    var n := 0
    for mi in root.find_children("*", "MeshInstance3D", true, false):
        var mesh: Mesh = mi.mesh
        if mesh == null:
            continue
        for i in mesh.get_surface_count():
            var src: Material = mi.get_active_material(i)
            var col := Color.WHITE
            var mname := ""
            if src:
                mname = src.resource_name
                if src is BaseMaterial3D:
                    col = src.albedo_color
            mi.set_surface_override_material(i, make(col, outline_width, not no_outline.any(func(k): return mname.contains(k)), mname))
            n += 1
    return n

static func make(col: Color, outline_width: float = 0.008, outline: bool = true, name: String = "") -> ShaderMaterial:
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
