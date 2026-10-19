extends "res://tests/test_base.gd"
## 1.0 must-have: precise ability descriptions. AbilityInfo adapter (HeroAbilities by path, mocked here; hero-JSON
## fallback), hero select list, Match page hero info pane, HUD ability tooltip (hover / long-press, live key,
## on-screen clamp, dismiss, never blocks input).
var tree: SceneTree
const MOCK := "res://tests/ui_mock_hero_abilities.gd"

class MockProvider extends RefCounted:
    func describe(hero_id: String, slot: String) -> Dictionary:
        if slot == "passive":
            return {}
        return {"name": "P-" + slot, "slot": slot, "type": "t", "text": "Provider %s %s" % [hero_id, slot], "stats": {"damage": 5, "cooldown": 2.5, "flag": true, "list": [1]}}
    func describe_all(hero_id: String) -> Array:
        return [describe(hero_id, "ability2"), describe(hero_id, "primary")]

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func _json_only() -> void:
    AbilityInfo.reset()
    AbilityInfo.api_path = "res://does/not/exist_hero_abilities.gd"

func test_mock_api_loaded_by_path_sorted_and_normalised() -> void:
    AbilityInfo.reset()
    AbilityInfo.api_path = MOCK
    check(AbilityInfo.has_api(), "mock script detected by path")
    var all := AbilityInfo.describe_all("cob")
    check(all.map(func(e): return e.slot) == ["primary", "ability1", "ability2", "ultimate"], "slot order: %s" % [all.map(func(e): return e.slot)])
    check(all.all(func(e): return e.source == "api" and e.text.begins_with("Mock text for cob") and e.stats is Dictionary), "api text used")
    var d := _def("cob")
    d.abilities.ability1["description"] = "Def flavour."
    var e := AbilityInfo.describe("cob", "ability1", d)
    check(e.name == "cob ability1" and e.description == "Def flavour.", "describe(): %s" % e)
    check(AbilityInfo.describe("cob", "passive").is_empty(), "absent slot -> {}")
    AbilityInfo.reset()

func test_provider_hook_and_stats_filter() -> void:
    AbilityInfo.reset()
    AbilityInfo.provider = MockProvider.new()
    var all := AbilityInfo.describe_all("the_best")
    check(all.size() == 2 and all[0].slot == "primary" and all[1].slot == "ability2", "provider entries sorted")
    var line := AbilityInfo.stats_text(all[0])
    check(line == "Damage per shot: 5\nCooldown: 2.5 s", "non-numeric / unknown stats skipped: " + line)
    AbilityInfo.reset()

func test_json_fallback_every_hero() -> void:
    _json_only()
    check(not AbilityInfo.has_api(), "no API -> fallback")
    for h in UiCatalog.list_heroes():
        var d := _def(h.id)
        var all := AbilityInfo.describe_all(h.id)
        var slots := all.map(func(e): return e.slot)
        check(slots.slice(0, 4) == ["primary", "ability1", "ability2", "ultimate"], "%s slots %s" % [h.id, slots])
        check(all[0].name == KillFeed.primary_name(d) and all[0].stats.get("damage") == d.primary.damage, h.id + " primary")
        for e in all.slice(1):
            var a: Dictionary = d.abilities[e.slot]
            check(e.source == "json" and e.name == a.name and e.type == a.type, "%s %s name/type" % [h.id, e.slot])
            if a.get("needs_ult", false) or e.slot == "ultimate":
                check(e.stats.get("ult_cost") == d.get("ultimate_cost", 500), "%s ult cost" % h.id)
            elif a.has("cooldown"):
                check(is_equal_approx(float(e.stats.cooldown), float(a.cooldown)), "%s %s cooldown" % [h.id, e.slot])
    var d := _def("cob")
    d.abilities.ability2["description"] = "Plain words."
    check(AbilityInfo.describe("cob", "ability2", d).text == "Plain words.", "def description is the fallback text")
    AbilityInfo.reset()

func test_real_api_when_present() -> void:
    AbilityInfo.reset()
    if not ResourceLoader.exists(AbilityInfo.api_path):
        check(not AbilityInfo.has_api(), "HeroAbilities not on this branch: JSON fallback")
        return
    check(AbilityInfo.has_api(), "HeroAbilities detected")
    for h in UiCatalog.list_heroes():
        var all := AbilityInfo.describe_all(h.id)
        check(all.size() >= 4 and all.all(func(e): return e.source == "api" and e.text != "" and e.name != ""), h.id + " described by HeroAbilities")
        check(all[0].slot == "primary", h.id + " primary first")
        var d := _def(h.id)
        if not d.primary.has("name"):
            check(all[0].name == KillFeed.primary_name(d), h.id + " unnamed primary labelled like the kill feed")

func test_stats_text_labels() -> void:
    var e := {"slot": "ability1", "type": "x", "stats": {"radius": 8, "duration": 3.5, "width": 3.4, "cooldown": 10}}
    check(AbilityInfo.stats_text(e) == "Radius: 8 m\nWall width: 3.4 m\nDuration: 3.5 s\nCooldown: 10 s", AbilityInfo.stats_text(e))
    check(AbilityInfo.stats_text({"slot": "ultimate", "stats": {"ult_cost": 600}}) == "Ultimate cost: 600 charge", "ult cost")
    check(AbilityInfo.stats_text({"stats": {}}) == "", "empty")
    check(AbilityInfo.stats_text({"slot": "primary", "type": "melee", "stats": {"damage": 32, "mag": 999, "reload_time": 1}}) == "Damage per hit: 32", "no-ammo sentinel hidden")

func test_slot_label_has_live_key() -> void:
    var keep := InputMap.action_get_events("ability1")
    var ev := InputEventKey.new()
    ev.physical_keycode = KEY_F
    Keybinds.rebind("ability1", ev)
    check(AbilityInfo.slot_label("ability1") == "Ability 1 [F]", AbilityInfo.slot_label("ability1"))
    check(AbilityInfo.slot_label("primary").begins_with("Primary [") and AbilityInfo.slot_label("passive") == "Passive", "primary/passive")
    InputMap.action_erase_events("ability1")
    for k in keep:
        InputMap.action_add_event("ability1", k)

func test_hero_detail_lists_all_slots() -> void:
    AbilityInfo.reset()
    AbilityInfo.api_path = MOCK
    var hd := HeroDetail.new()
    tree.root.add_child(hd)
    hd.show_def(_def("twin_tails"))
    for s in ["primary", "ability1", "ability2", "ultimate"]:
        var h: Label = hd.info.find_child("Slot_" + s, true, false)
        var t: Label = hd.info.find_child("Text_" + s, true, false)
        var st: Label = hd.info.find_child("Stats_" + s, true, false)
        var want: String = KillFeed.primary_name(_def("twin_tails")) if s == "primary" else "twin_tails " + s   # unnamed primary
        check(h != null and h.text.begins_with(AbilityInfo.slot_label(s)) and h.text.ends_with(want), "header %s: %s" % [s, h.text if h else "-"])
        check(t != null and t.text.contains("12 damage"), "text " + s)
        check(st != null and st.text.contains("Cooldown: 7 s"), "stats " + s)
    _json_only()
    hd.show_def(_def("twin_tails"))
    var d := _def("twin_tails")
    var h1: Label = hd.info.find_child("Slot_ability1", true, false)
    check(h1 != null and h1.text.ends_with(d.abilities.ability1.name), "fallback header")
    check((hd.info.find_child("Stats_ability1", true, false) as Label).text.contains("Cooldown: %s s" % StatLabels.num(d.abilities.ability1.cooldown)), "fallback cooldown")
    hd.free()
    AbilityInfo.reset()

func _match_menu() -> Array:
    var R = load("res://tests/ui_round13_test.gd")
    var r = R.MockRoot.new()
    var m := PauseMenu.new()
    tree.root.add_child(m)
    m.set_control(MatchControl.new(r, R.MockNet.new()))
    return [m, r]

func test_match_page_hero_info_pane() -> void:
    AbilityInfo.reset()
    AbilityInfo.api_path = MOCK
    var mr := _match_menu()
    var m: PauseMenu = mr[0]
    var page := m.match_page
    m.open()
    m.open_match()
    page.refresh()
    var first := String(page.hero_btns[0].get_meta("hero_id"))
    check(page.info_pane != null and page.info_hero == first, "defaults to a hero: " + page.info_hero)
    var other := String(page.hero_btns[1].get_meta("hero_id"))
    page.hero_btns[1].mouse_entered.emit()
    check(page.info_hero == other and page.info_title.text == page._base_name(page.hero_btns[1]), "hover highlights")
    var hdr: Label = page.info_pane.find_child("Slot_ability1", true, false)
    check(hdr != null and hdr.text.contains(other + " ability1"), "pane lists abilities")
    var ib: Button = page.find_child("Info_" + first, true, false)
    check(ib != null and ib.custom_minimum_size.x >= 64 and ib.custom_minimum_size.y >= 64, "touch-sized ? button")
    ib.pressed.emit()
    check(page.info_hero == first and ib.button_pressed and not page.info_btns[other].button_pressed, "? highlights (touch)")
    check(mr[1].hero_reqs.is_empty(), "? does not request a switch")
    page.refresh()
    check(page.info_hero == first, "pinned highlight survives refresh")
    page.hero_btns[1].pressed.emit()
    check(mr[1].hero_reqs == [other], "tapping the hero still requests the switch")
    m.close(); m.free(); mr[1].free()
    AbilityInfo.reset()

func _tip() -> Array:
    var root := Control.new()
    root.size = Vector2(1280, 720)
    tree.root.add_child(root)
    var tip := AbilityTooltip.new()
    var panels := {}
    for i in 3:
        var p := Panel.new()
        p.position = Vector2(500 + i * 160, 640)
        p.size = Vector2(150, 70)
        root.add_child(p)
        panels[["ability1", "ability2", "ultimate"][i]] = p
    root.add_child(tip)
    tip.panels = panels
    tip.entry_for = func(s): return {"name": "N-" + s, "slot": s, "text": "Long precise text " + "word ".repeat(40), "stats": {"damage": 9, "cooldown": 4}}
    return [root, tip, panels]

func _motion(pos: Vector2) -> InputEventMouseMotion:
    var e := InputEventMouseMotion.new()
    e.position = pos
    return e

func _touch(pos: Vector2, pressed: bool) -> InputEventScreenTouch:
    var e := InputEventScreenTouch.new()
    e.position = pos
    e.pressed = pressed
    return e

func test_tooltip_hover_live_key_and_dismiss() -> void:
    var a := _tip()
    var tip: AbilityTooltip = a[1]
    var c: Vector2 = (a[2].ability2 as Control).get_global_rect().get_center()
    tip.feed(_motion(c), true)
    check(not tip.visible, "no hover while the mouse is captured")
    tip.feed(_motion(c))
    check(tip.visible and tip.slot == "ability2" and tip.mode == "hover", "hover shows")
    check(tip.title.text == "N-ability2  [%s]" % Hud.key_label("ability2"), tip.title.text)
    check(tip.stats.text == "Damage: 9\nCooldown: 4 s" and tip.body.text.begins_with("Long precise"), "text + stats")
    var keep := InputMap.action_get_events("ability2")
    var ev := InputEventKey.new()
    ev.physical_keycode = KEY_G
    Keybinds.rebind("ability2", ev)
    tip.step(0.016)
    check(tip.title.text.ends_with("[G]"), "key binding live: " + tip.title.text)
    InputMap.action_erase_events("ability2")
    for k in keep:
        InputMap.action_add_event("ability2", k)
    var r := tip.get_global_rect()
    check(Rect2(Vector2.ZERO, tip.get_viewport_rect().size).encloses(r), "on-screen: %s in %s" % [r, tip.get_viewport_rect()])
    check(r.end.y <= (a[2].ability2 as Control).get_global_rect().position.y, "above the icon")
    var click := InputEventMouseButton.new()
    click.pressed = true
    click.button_index = MOUSE_BUTTON_LEFT
    click.position = c
    tip.feed(click)
    check(not tip.visible, "click dismisses")
    tip.feed(_motion(c + Vector2(2, 0)))
    check(not tip.visible, "stays dismissed while still on the icon")
    tip.feed(_motion(Vector2(10, 10)))
    tip.feed(_motion(c))
    check(tip.visible, "re-shows after leaving and coming back")
    tip.feed(_motion(Vector2(10, 10)))
    check(not tip.visible, "leaving hides")
    a[0].free()

func test_tooltip_long_press_touch() -> void:
    var a := _tip()
    var tip: AbilityTooltip = a[1]
    var c: Vector2 = (a[2].ultimate as Control).get_global_rect().get_center()
    tip.feed(_touch(c, true))
    tip.step(0.3)
    check(not tip.visible, "short press: nothing yet")
    tip.step(0.2)
    check(tip.visible and tip.mode == "touch" and tip.slot == "ultimate", "long press shows")
    var emu := InputEventMouseMotion.new()
    emu.device = InputEvent.DEVICE_ID_EMULATION
    emu.position = Vector2(5, 5)
    tip.feed(emu)
    check(tip.visible, "emulated mouse from touch ignored")
    tip.feed(_touch(c, false))
    check(tip.visible, "stays after lift")
    var r := tip.get_global_rect()
    check(Rect2(Vector2.ZERO, tip.get_viewport_rect().size).encloses(r), "right-edge icon still on-screen: %s" % r)
    tip.step(AbilityTooltip.LINGER + 0.1)
    check(not tip.visible, "auto-dismiss after linger")
    tip.feed(_touch(c, true))
    tip.step(0.5)
    tip.feed(_touch(Vector2(100, 100), true))
    check(not tip.visible, "next tap dismisses")
    tip.feed(_touch(Vector2(100, 100), false))
    tip.feed(_touch(c, true))
    var drag := InputEventScreenDrag.new()
    drag.position = c + Vector2(60, 0)
    tip.feed(drag)
    tip.step(1.0)
    check(not tip.visible, "drag (camera look) cancels the long press")
    tip.feed(_touch(c, false))
    tip.feed(_touch(Vector2(20, 20), true))
    tip.step(1.0)
    check(not tip.visible, "long press outside icons: nothing")
    a[0].free()

func test_tooltip_never_blocks_input() -> void:
    var a := _tip()
    var tip: AbilityTooltip = a[1]
    var nodes: Array = [tip] + tip.find_children("*", "Control", true, false)
    check(nodes.all(func(n): return n.mouse_filter == Control.MOUSE_FILTER_IGNORE), "tooltip ignores the mouse")
    tip.feed(_motion((a[2].ability1 as Control).get_global_rect().get_center()))
    check(tip.visible and tip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "still ignore while shown")
    var esc := InputEventAction.new()
    esc.action = "pause"
    esc.pressed = true
    tip.feed(esc)
    check(not tip.visible, "Esc/pause hides")
    a[0].free()
