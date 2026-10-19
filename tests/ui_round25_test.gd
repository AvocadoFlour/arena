extends "res://tests/test_base.gd"
## ability3 (right mouse): rebindable action (UI-registered until core adds it), slot order, AbilityInfo /
## controls hint / Esc Controls page / hero select / kill feed / HeroSfx, graceful for heroes without one.
var tree: SceneTree

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

## A real hero def with an ability3 added (until Heroes ships one). Name taken from the hero's own ability2
## entry so no new creative name is invented.
func _with_a3(id := "cob") -> Dictionary:
    var d := _def(id)
    var a3: Dictionary = d.abilities.ability2.duplicate(true)
    a3["id"] = "test_a3"
    d.abilities["ability3"] = a3
    return d

func _row(rows: Array, label: String) -> Array:
    for r in rows:
        if r[0] == label:
            return r
    return []

func test_action_right_mouse_rebindable_and_ordered() -> void:
    Keybinds.ensure_ui_actions()
    Keybinds.reset_defaults()
    check(InputMap.has_action("ability3"), "ability3 action exists")
    var evs := InputMap.action_get_events("ability3")
    check(evs.size() == 1 and evs[0] is InputEventMouseButton and evs[0].button_index == MOUSE_BUTTON_RIGHT, "bound to right mouse")
    check(Keybinds.binding_text("ability3") == "Mouse Right" and Hud.key_label("ability3") == "MOUSE RIGHT", "shown as Mouse Right")
    check(Keybinds.pretty("ability3") == "Ability 3", "label: " + Keybinds.pretty("ability3"))
    var a := Keybinds.actions()
    check(a.count("ability3") == 1 and a.find("ability3") == a.find("ability2") + 1, "listed once, right after ability2: %s" % [a])
    var f := InputEventKey.new()
    f.physical_keycode = KEY_F
    Keybinds.rebind("ability3", f)
    check(Keybinds.binding_text("ability3") == "F", "rebind to F")
    var path := "user://test_kb_a3.cfg"
    Keybinds.save(path)
    Keybinds.reset_defaults()
    check(Keybinds.binding_text("ability3") == "Mouse Right", "reset defaults -> right mouse")
    Keybinds.load_saved(path)
    check(Keybinds.binding_text("ability3") == "F", "saved + loaded")
    var rmb := InputEventMouseButton.new()
    rmb.button_index = MOUSE_BUTTON_RIGHT
    Keybinds.reset_defaults()
    var swapped := Keybinds.rebind("fire", rmb)
    check(swapped == "ability3" and Keybinds.binding_text("ability3") == "Mouse Left", "fire on right mouse swaps with ability3")
    Keybinds.reset_defaults()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    check(not Actions.MOUSE_BINDINGS.has("ability3") or not InputMap.action_get_events("ability3").is_empty(), "core definition wins once it exists")

func test_ability_info_slot_order_and_missing_slot() -> void:
    check(AbilityInfo.SLOTS == ["primary", "ability1", "ability2", "ability3", "ultimate", "passive"], "slot order")
    check(AbilityInfo.SLOT_ACTIONS.ability3 == "ability3" and AbilityInfo.SLOT_LABELS.ability3 == "Ability 3", "action + label")
    for e in UiCatalog.list_heroes():
        var id := String(e.id)
        var d := _def(id)
        if d.get("abilities", {}).has("ability3"):
            continue
        check(AbilityInfo.describe(id, "ability3", d).is_empty(), id + ": no ability3 entry, no error")
        check(not AbilityInfo.describe_all(id, d).any(func(x): return x.slot == "ability3"), id + ": not listed")
    var d3 := _with_a3()
    var all := AbilityInfo.describe_all("cob", d3).map(func(x): return x.slot)
    check(all.find("ability3") == all.find("ability2") + 1 and all.find("ultimate") == all.find("ability3") + 1, "listed between ability2 and ultimate: %s" % [all])
    check(AbilityInfo.describe("cob", "ability3", d3).name == d3.abilities.ability3.name, "name from the def")

func test_controls_hint_row_only_with_ability3() -> void:
    Keybinds.reset_defaults()
    for e in UiCatalog.list_heroes():
        var d := _def(String(e.id))
        if not d.get("abilities", {}).has("ability3"):
            check(_row(ControlsHint.rows(d), "Ability 3").is_empty(), String(e.id) + ": no Ability 3 row")
    var r := ControlsHint.rows(_with_a3())
    var row := _row(r, "Ability 3")
    check(row == ["Ability 3", "MOUSE RIGHT", _with_a3().abilities.ability3.name], "row: %s" % [row])
    var labels: Array = r.map(func(x): return x[0])
    check(labels.find("Ability 3") == labels.find("Ability 2") + 1 and labels.find("Ultimate") == labels.find("Ability 3") + 1, "row order")

func test_esc_controls_page_names_and_hides() -> void:
    var page := KeybindScreen.new()
    page.read_only = true
    tree.root.add_child(page)
    check(page.labels.has("ability3") and page.values.has("ability3"), "Controls page has an ability3 row")
    page.set_hero_def(_def("tomo"))
    check(not page.labels.ability3.visible and not page.values.ability3.visible, "hidden for a hero without ability3")
    var d3 := _with_a3("tomo")
    page.set_hero_def(d3)
    check(page.labels.ability3.visible and page.labels.ability3.text == "Ability 3: " + String(d3.abilities.ability3.name), "named: " + page.labels.ability3.text)
    check(page.values.ability3.text == "Mouse Right", "binding shown")
    check(page.labels.ability1.text.begins_with("Ability 1: "), "other ability rows named too: " + page.labels.ability1.text)
    page.set_hero_def({})
    check(page.labels.ability3.visible and page.labels.ability3.text == "Ability 3", "no hero: plain row")
    page.free()
    var rb := KeybindScreen.new()
    tree.root.add_child(rb)
    check(rb.buttons.has("ability3") and rb.buttons.ability3.text == "Mouse Right", "rebind screen offers ability3")
    rb.free()
    check(FileAccess.get_file_as_string("res://src/ui/pause_menu.gd").contains("controls_page.set_hero_def("), "pause menu passes the local hero")

func test_hero_select_kill_feed_sfx_graceful() -> void:
    var d3 := _with_a3()
    check(HeroDetail.slot_line("ability3", d3.abilities.ability3).begins_with("Ability 3: "), "hero select line")
    check(KillFeed.slot_of(d3, "test_a3") == "ability3", "kill feed finds ability3 by id")
    var s := HeroSfx.new()
    tree.root.add_child(s)
    s.set_process(false)
    var h := Node3D.new()
    h.set_script(null)
    tree.root.add_child(h)
    check(HeroSfx.path_for("cob", "ability3") == "", "no ability3 sound mapped yet")
    var before := s.play_count.duplicate()
    s.on_ability_used(h, "ability3", "x")
    check(s.play_count == before, "ability3 cast plays nothing, no error")
    check(HeroSfx.SLOTS.size() == 5, "5-sounds-per-hero scheme unchanged")
    s.free(); h.free()

func test_hud_source_has_ordered_hidden_slot() -> void:
    var src := FileAccess.get_file_as_string("res://src/ui/hud.gd")
    check(src.contains('for slot in ["ability1", "ability2", "ability3", "ultimate"]'), "HUD slot order")
    check(src.contains("get_parent().visible = has"), "panel hidden when the hero has no such slot")
