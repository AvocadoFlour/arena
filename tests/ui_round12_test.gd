extends "res://tests/test_base.gd"
## Miku queue 3: hero-select 3D preview + role/ability info, responsive, cheap, low_quality.
var tree: SceneTree

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func _preview() -> HeroPreview:
    var p := HeroPreview.new()
    tree.root.add_child(p)
    return p

func test_preview_uses_glb_when_referenced() -> void:
    var p := _preview()
    for h in UiCatalog.list_heroes():
        var d := _def(h.id)
        p.show_def(d)
        if d.has("model_scene"):
            check(p.source == "scene" or p.source == "glb", h.id + " uses its GLB (" + p.source + ")")
        else:
            check(p.source == "primitive", h.id + " primitive fallback")
        check(p.model != null and p.model.get_parent() == p.pivot, h.id + " model in preview world")
    check(tree.get_nodes_in_group("heroes").is_empty() or tree.get_nodes_in_group("heroes").all(func(n): return not p.is_ancestor_of(n)), "no gameplay heroes created")
    p.free()

func test_primitive_fallback_and_missing_glb() -> void:
    var p := _preview()
    var d := _def("cob")
    d.model_scene = {"path": "res://does/not/exist.glb"}
    p.show_def(d)
    check(p.source == "primitive" and p.model.get_child_count() == d.model.size(), "missing GLB -> primitives (%d parts)" % d.model.size())
    var team_part := HeroPreview.build_primitives([{"shape": "capsule", "radius": 0.3, "height": 1.2, "pos": [0, 0.9, 0], "color": "team"}])
    var mi: MeshInstance3D = team_part.get_child(0)
    check(mi.mesh is CapsuleMesh and mi.material_override.albedo_color == HeroPreview.TEAM_PREVIEW, "team colour part")
    team_part.free()
    p.free()

func test_selection_change_updates_preview_and_info() -> void:
    var mm := MainMenu.new()
    tree.root.add_child(mm)
    mm.show_screen("heroes")
    var hs := UiCatalog.list_heroes()
    for h in hs:
        mm.select("hero", h.path)
        check(mm.hero_detail.preview.def_id == h.id, "preview follows selection: " + h.id)
        var role: Label = mm.hero_detail.info.find_child("Role", true, false)
        check(role.text.begins_with(UiCatalog.role_label(h.role)), "role shown: " + role.text)
        var d := _def(h.id)
        for slot in ["ability1", "ability2", "ultimate"]:
            var l: Label = mm.hero_detail.info.find_child("Slot_" + slot, true, false)
            check(l != null and l.text.contains(d.abilities[slot].name), "%s %s listed" % [h.id, slot])
    check(mm.current == "heroes", "picking a hero stays on the screen")
    var btns: Array = mm.screens.heroes.find_children("*", "Button", true, false)
    check(btns.all(func(b): return b.custom_minimum_size.y >= 64), "touch-size buttons")
    var pressed: Array = btns.filter(func(b): return b.button_pressed)
    check(pressed.size() == 1 and pressed[0].get_meta("path") == UiCatalog.selected_hero, "selected hero marked")
    mm.free()

func test_slot_lines_and_description() -> void:
    var a := {"id": "x", "name": "Thing", "type": "shield_wall", "cooldown": 12.0}
    check(HeroDetail.slot_line("ability2", a) == "Ability 2: Thing  (shield wall, 12.0s cooldown)", HeroDetail.slot_line("ability2", a))
    check(HeroDetail.slot_line("ultimate", {"name": "U", "type": "nova", "cooldown": 1.0, "needs_ult": true}).contains("needs full ultimate"), "ultimate")
    var hd := HeroDetail.new()
    tree.root.add_child(hd)
    var d := _def("twin_tails")
    d.abilities.ability1["description"] = "Plain test text."
    hd.show_def(d)
    check(hd.info.find_children("*", "Label", true, false).any(func(l): return l.text == "Plain test text."), "description shown when present")
    hd.free()

func test_responsive_stack() -> void:
    var hd := HeroDetail.new()
    tree.root.add_child(hd)
    hd.layout_for_width(600)
    check(hd.vertical and hd.get_child(0) == hd.preview, "narrow: preview stacked on top")
    hd.layout_for_width(1200)
    check(not hd.vertical, "wide: side by side")
    hd.free()
    var sp := MainMenu.HeroSplit.new()
    var lst := Control.new()
    var det := HeroDetail.new()
    sp.add_child(lst)
    sp.add_child(det)
    sp.set_narrow(true)
    check(sp.vertical and sp.get_child(0) == det, "narrow split: detail (preview) above list")
    sp.set_narrow(false)
    check(not sp.vertical and sp.get_child(1) == det, "wide split: list left, detail right")
    sp.free()

func test_cheap_rendering_and_low_quality() -> void:
    var keep: bool = Settings.low_quality
    var p := _preview()
    check(p.vp.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "renders only while visible")
    Settings.set_low_quality(true)
    check(p.stretch_shrink == 2 and p.vp.msaa_3d == Viewport.MSAA_DISABLED and not p.light.shadow_enabled, "low quality applied live")
    Settings.set_low_quality(false)
    check(p.stretch_shrink == 1 and p.light.shadow_enabled, "normal quality")
    p.show_def(_def("cob"))
    p.visible = false
    var r := p.pivot.rotation.y
    p._process(1.0)
    check(p.pivot.rotation.y == r, "no spin while hidden")
    p.visible = true
    p._process(1.0)
    check(p.pivot.rotation.y > r, "spins when visible")
    var r2 := p.pivot.rotation.y
    p.drag(100)
    check(p.pivot.rotation.y > r2, "drag rotates")
    p.free()
    Settings.set_low_quality(keep)
