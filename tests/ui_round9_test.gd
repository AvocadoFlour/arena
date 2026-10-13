extends "res://tests/test_base.gd"
## UI queue 3: in-match pause/options overlay (offline pause, online no-pause), Esc levels,
## Leave match hook, ability_ready event with polling fallback.
var tree: SceneTree

func _menu() -> PauseMenu:
    var m := PauseMenu.new()
    tree.root.add_child(m)
    return m

func _esc() -> InputEventKey:
    var e := InputEventKey.new()
    e.physical_keycode = KEY_ESCAPE
    e.pressed = true
    return e

func test_overlay_buttons_touch_sized() -> void:
    var m := _menu()
    for n in ["Resume", "Settings", "Leavematch"]:
        var b: Button = m.panel.find_child(n, true, false)
        check(b != null and b.custom_minimum_size.y >= 64 and b.custom_minimum_size.x >= 320, "button " + n)
    check(not m.visible, "hidden initially")
    m.free()

func test_offline_pauses_and_blocks_input() -> void:
    var keep: int = Net.mode
    Net.mode = Net.OFFLINE
    var m := _menu()
    m.open()
    check(m.visible and tree.paused and not Actions.gameplay_enabled, "offline: paused + input blocked")
    m.close()
    check(not m.visible and not tree.paused and Actions.gameplay_enabled, "resume restores")
    Net.mode = keep
    m.free()

func test_online_never_pauses() -> void:
    var keep: int = Net.mode
    Net.mode = Net.CLIENT
    var m := _menu()
    m.open()
    check(m.visible and not tree.paused, "online: simulation keeps running")
    check(not Actions.gameplay_enabled, "online: gameplay input blocked")
    check((m.panel.find_child("OnlineNote", true, false) as Label).text != "", "online note")
    m.close()
    check(Actions.gameplay_enabled and not tree.paused, "closed")
    Net.mode = keep
    m.free()

func test_settings_reuse_and_escape_levels() -> void:
    Net.mode = Net.OFFLINE
    var m := _menu()
    m.open()
    m.open_settings()
    check(m.settings_open() and m.options.current == "settings" and not m.panel.visible, "settings screen shown")
    check(m.options.screens.settings.find_child("FovSlider", true, false) != null, "same settings screen (FOV)")
    check(m.options.screens.settings.find_child("LowQualityToggle", true, false) != null, "same settings screen (low quality)")
    m.options.show_screen("keybinds")
    check(m.handle_escape() and m.options.current == "settings", "Esc: controls -> settings")
    m.options.show_screen("audio")
    check(m.handle_escape() and m.options.current == "settings", "Esc: audio -> settings")
    check(m.handle_escape() and not m.settings_open() and m.panel.visible and m.visible, "Esc: settings -> pause panel")
    check(m.handle_escape() and not m.visible and not tree.paused, "Esc: closes overlay")
    check(not m.handle_escape(), "closed: Esc not consumed (main.gd opens)")
    m.free()

func test_back_button_in_settings_returns_to_overlay() -> void:
    var m := _menu()
    m.open()
    m.open_settings()
    var back: Button = m.options.screens.settings.find_children("*", "Button", true, false).filter(func(b): return b.text == "Back")[0]
    back.pressed.emit()
    check(not m.settings_open() and m.panel.visible, "Back -> pause panel")
    m.close()
    m.free()

func test_rebind_escape_cancel_does_not_close_overlay() -> void:
    var m := _menu()
    m.open()
    m.open_settings()
    m.options.show_screen("keybinds")
    var ks: KeybindScreen = m.options.screens.keybinds
    ks._start("jump")
    check(ks.capture(_esc()) and ks.waiting == "", "rebind Esc cancels capture")
    check(m.visible and m.settings_open() and m.options.current == "keybinds", "overlay + controls still open")
    m.close()
    m.free()

func test_leave_match_hooks() -> void:
    var m := _menu()
    var got := []
    m.leave_requested.connect(func(): got.append("leave"))
    m.find_child("Leavematch", true, false).pressed.emit()
    check(got == ["leave"], "preferred hook: leave_requested")
    m.free()
    var m2 := _menu()
    var me := MatchEndScreen.new()
    tree.root.add_child(me)
    m2._match_end_hook = me
    var via := []
    me.main_menu.connect(func(): via.append("menu"))
    m2.leave()
    check(via == ["menu"], "fallback: documented match_end.main_menu route")
    m2.free()
    me.free()

func test_ability_ready_event_preferred() -> void:
    var hud := Hud.new()
    var bus := Node.new()
    check(not hud.bind_ready_event(bus) and not hud.ready_event, "no signal -> polling fallback")
    bus.add_user_signal("ability_ready")
    check(hud.bind_ready_event(bus) and hud.ready_event, "event bound when present")
    var before: int = Settings.sfx.play_count.get("ready", 0)
    Settings.sfx.last_play.erase("ready")
    hud.player = bus   # any object identity works for the hero check
    bus.emit_signal("ability_ready", bus, "ability1")
    check(Settings.sfx.play_count.get("ready", 0) == before + 1, "event plays ready cue")
    hud.free()
    var h2 := Hud.new()
    check(h2.bind_ready_event(Events) == Events.has_signal("ability_ready"), "Events: bound iff core has the signal")
    h2.free()
    bus.free()
