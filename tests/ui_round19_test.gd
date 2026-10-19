extends "res://tests/test_base.gd"
## First-time controls hint (ControlsHint) + Esc overlay "Controls" reference page (read-only KeybindScreen).
var tree: SceneTree

class MockPlayer extends RefCounted:
    var def := {}

class MockHud extends RefCounted:
    var player := MockPlayer.new()
    var asked := []
    func ability_entry(slot: String) -> Dictionary:
        asked.append(slot)
        return AbilityInfo.describe(String(player.def.get("id", "")), slot, player.def)

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func _key(k: int) -> InputEventKey:
    var e := InputEventKey.new()
    e.physical_keycode = k
    e.pressed = true
    return e

func _hint(id := "cob") -> ControlsHint:
    var h := ControlsHint.new()
    var hud := MockHud.new()
    hud.player.def = _def(id)
    h.hud = hud
    tree.root.add_child(h)
    return h

func _row(rows: Array, label: String) -> Array:
    for r in rows:
        if r[0] == label:
            return r
    return []

func _texts(h: ControlsHint) -> Array:
    return h.grid.get_children().map(func(l): return l.text)

func test_rows_per_hero_live_keys_and_ability_names() -> void:
    AbilityInfo.reset()
    Keybinds.reset_defaults()
    for e in UiCatalog.list_heroes():
        var id := String(e.id)
        var d := _def(id)
        var r := ControlsHint.rows(d)
        check(_row(r, "Move") == ["Move", "W A S D", ""], id + " move: " + str(_row(r, "Move")))
        check(_row(r, "Look").size() == 3 and _row(r, "Jump")[1] == "SPACE", id + " look + jump")
        for slot in ["primary", "ability1", "ability2", "ultimate"]:
            var want_name := String(AbilityInfo.describe(id, slot, d).name)
            var row := _row(r, AbilityInfo.SLOT_LABELS[slot])
            check(row.size() == 3 and row[1] == Hud.key_label(AbilityInfo.SLOT_ACTIONS[slot]) and row[2] == want_name and want_name != "",
                "%s %s: %s" % [id, slot, str(row)])
        check(_row(r, "Ability 1")[1] == "SHIFT" and _row(r, "Ability 2")[1] == "E" and _row(r, "Ultimate")[1] == "Q"
            and _row(r, "Primary")[1] == "MOUSE LEFT", id + " default keys")
        check((_row(r, "Reload").size() > 0) == Hud.shows_ammo(d), id + " reload only with ammo")
        check(_row(r, "Scoreboard")[1] == "TAB" and _row(r, "Pause")[1] == "ESCAPE", id + " tab + esc")
    check(_row(ControlsHint.rows(_def("nidjo")), "Reload").is_empty() and not _row(ControlsHint.rows(_def("cob")), "Reload").is_empty(), "melee: no reload; cob: reload")

func test_hint_uses_hud_entries_and_updates_live_after_rebind() -> void:
    AbilityInfo.reset()
    Keybinds.reset_defaults()
    var h := _hint("the_best")
    h.show_hint()
    check(h.visible and h.is_showing(), "shown")
    check(h.hud.asked.has("ability1") and h.hud.asked.has("ultimate"), "names via Hud.ability_entry")
    var t := _texts(h)
    check(t.has(String(AbilityInfo.describe("the_best", "ultimate").name)) and t.has("SHIFT") and not t.has("Reload"), "the_best rows: " + str(t))
    Keybinds.rebind("ability2", _key(KEY_F))
    h._process(0.1)
    check(_texts(h).has("F") and _row(ControlsHint.rows(h.hud.player.def), "Ability 2")[1] == "F", "rebind shows live")
    h.hud.player.def = _def("cob")   # hero swap
    h._process(0.1)
    check(_texts(h).has("Reload") and _texts(h).has(String(AbilityInfo.describe("cob", "ability1").name)), "follows hero swap")
    Keybinds.reset_defaults()
    h.free()

func test_dismiss_any_key_click_tap_and_seen_flag() -> void:
    var keep := Settings.controls_hint_seen
    Settings.controls_hint_seen = false
    var h := _hint()
    h.show_hint()
    var mm := InputEventMouseMotion.new()
    mm.relative = Vector2(30, 0)
    check(not h.handle(mm) and h.visible, "mouse look passes through")
    var rel := _key(KEY_W)
    rel.pressed = false
    check(not h.handle(rel) and h.visible, "release ignored")
    check(h.handle(_key(KEY_W)) and not h.visible, "any key dismisses")
    check(Settings.controls_hint_seen, "Don't show again (default on) -> seen")
    check(not ControlsHint.should_show(), "seen -> not shown again")
    Settings.controls_hint_seen = false
    h.show_hint()
    h.toggle.button_pressed = false
    var tap := InputEventScreenTouch.new()
    tap.pressed = true
    tap.position = Vector2(5, 700)
    check(h.handle(tap) and not h.visible and not Settings.controls_hint_seen, "tap dismisses; toggle off keeps it showing next time")
    h.show_hint()
    check(h.toggle.button_pressed, "toggle resets on each show")
    var c := InputEventMouseButton.new()
    c.button_index = MOUSE_BUTTON_LEFT
    c.pressed = true
    c.position = h.toggle.get_global_rect().get_center()
    check(not h.handle(c) and h.visible, "click on the toggle doesn't dismiss")
    c.position = Vector2(2, 2)
    check(h.handle(c) and not h.visible, "click elsewhere dismisses")
    h.show_hint()
    var jb := InputEventJoypadButton.new()
    jb.pressed = true
    check(h.handle(jb) and not h.visible, "gamepad button dismisses")
    Settings.controls_hint_seen = keep
    Settings.save()
    h.free()

func test_auto_fade_and_non_blocking_layout() -> void:
    var keep := Settings.controls_hint_seen
    var h := _hint()
    h.show_hint()
    var closed := []
    h.closed.connect(func(): closed.append(1))
    h._process(ControlsHint.AUTO_FADE - 0.5)
    check(h.visible and h.is_showing(), "still up before %s s" % ControlsHint.AUTO_FADE)
    check(ControlsHint.AUTO_FADE >= 7.0 and ControlsHint.AUTO_FADE <= 9.0, "about 8 s")
    h._process(0.55)
    check(h.visible and not h.is_showing() and h.panel.modulate.a < 1.0, "fading")
    for i in 10:
        h._process(0.1)
    check(not h.visible and closed.size() == 1, "faded out and closed")
    for n in h.find_children("*", "Control", true, false):
        if n == h.toggle:
            check(n.mouse_filter != Control.MOUSE_FILTER_IGNORE and n.custom_minimum_size.y >= 64 and n.focus_mode == Control.FOCUS_NONE, "touch-sized toggle, no key focus")
        else:
            check(n.mouse_filter == Control.MOUSE_FILTER_IGNORE, "ignores mouse: " + n.name)
    check(h.process_mode == Node.PROCESS_MODE_ALWAYS and h.layer > 30, "works over the paused overlay")
    Settings.controls_hint_seen = keep
    Settings.save()
    h.free()

func test_should_show_and_settings_button() -> void:
    var keep := Settings.controls_hint_seen
    Settings.controls_hint_seen = false
    check(not ControlsHint.should_show(), "headless / automated runs never show it")
    for n in tree.get_nodes_in_group(ControlsHint.GROUP):
        n.free()
    Settings.controls_hint_seen = true
    check(not ControlsHint.request_show(tree) and not Settings.controls_hint_seen, "no match: flag cleared for the next match start")
    var h := _hint()
    Settings.controls_hint_seen = true
    check(ControlsHint.request_show(tree) and h.visible and not Settings.controls_hint_seen, "in a match: shown now")
    h.free()
    var m := MainMenu.new()
    tree.root.add_child(m)
    var b: Button = m.screens.settings.find_child("ShowControlsHint", true, false)
    check(b != null and b.text == "Show controls hint" and b.custom_minimum_size.y >= 64, "Settings button")
    Settings.controls_hint_seen = true
    b.pressed.emit()
    var note: Label = m.screens.settings.find_child("ControlsHintNote", true, false)
    check(not Settings.controls_hint_seen and note.text.contains("next match"), "main menu: shows next match")
    m.free()
    var pm := PauseMenu.new()
    tree.root.add_child(pm)
    var h2 := _hint()
    pm.open()
    pm.open_settings()
    (pm.options.screens.settings.find_child("ShowControlsHint", true, false) as Button).pressed.emit()
    check(h2.visible, "from the pause Settings: shown now over the overlay")
    pm.close()
    pm.free()
    h2.free()
    Settings.controls_hint_seen = keep
    Settings.save()

func test_esc_controls_page_lists_every_action_live() -> void:
    Keybinds.reset_defaults()
    var pm := PauseMenu.new()
    tree.root.add_child(pm)
    pm.open()
    var b: Button = pm.panel.find_child("Controls", true, false)
    check(b != null and b.custom_minimum_size.y >= 64, "Controls button in the Esc overlay")
    b.pressed.emit()
    check(pm.controls_open() and not pm.panel.visible, "Controls page open")
    var page := pm.controls_page
    check(page.read_only and page.buttons.is_empty(), "read-only: no capture buttons")
    for a in Keybinds.actions():
        check(page.values.has(a) and page.values[a].text == Keybinds.bindings_text(a) and page.values[a].text != "-", "%s: %s" % [a, page.values[a].text if page.values.has(a) else "?"])
    check(page.values.fire.text == "Mouse Left" and page.values.ability1.text == "Shift" and page.values.scoreboard.text == "Tab", "default texts")
    check(not page.capture(_key(KEY_K)), "never captures")
    Keybinds.rebind("reload", _key(KEY_F))
    page._process(0.0)
    check(page.values.reload.text == "F", "updates after a rebind: " + page.values.reload.text)
    var ev := InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_RIGHT
    InputMap.action_add_event("ability1", ev)
    page._process(0.0)
    check(page.values.ability1.text == "Shift, Mouse Right", "all bindings listed: " + page.values.ability1.text)
    var ch: Button = page.find_child("ChangeKeyBindings", true, false)
    check(ch != null and ch.custom_minimum_size.y >= 64, "Change key bindings button")
    ch.pressed.emit()
    check(not pm.controls_open() and pm.settings_open() and pm.options.current == "keybinds", "jumps to the rebind screen")
    var ks: KeybindScreen = pm.options.screens.keybinds
    ks._start("jump")
    ks.capture(_key(KEY_G))
    check(Keybinds.binding_text("jump") == "G", "rebound on the existing screen")
    check(pm.handle_escape() and pm.controls_open() and not pm.settings_open(), "Esc from the rebind screen -> Controls page")
    check(page.values.jump.text == "G", "page shows the new key")
    ch.pressed.emit()
    ks.back.emit()
    check(pm.controls_open() and not pm.settings_open() and not pm.panel.visible, "Back from the rebind screen -> Controls page")
    check(pm.handle_escape() and not pm.controls_open() and pm.panel.visible and pm.visible, "Esc: Controls page -> pause panel")
    pm.open_settings()
    pm.options.show_screen("keybinds")
    ks.back.emit()
    check(pm.settings_open() and pm.options.current == "settings" and not pm.controls_open(), "rebind via Settings still returns to Settings")
    pm.open_controls()
    pm.close()
    check(not pm.controls_open() and not pm.visible, "resume closes the page")
    pm.free()
    Keybinds.reset_defaults()
    Keybinds.save()
