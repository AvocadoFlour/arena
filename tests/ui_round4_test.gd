extends "res://tests/test_base.gd"
## UI round 4: Music/SFX buses, low_quality setting + signal, Host/Join (NetPanel) visual polish.
var tree: SceneTree

func test_music_sfx_sliders_drive_buses() -> void:
    var keep: Dictionary = Settings.volumes.duplicate()
    for bus in ["Music", "SFX"]:
        var i := AudioServer.get_bus_index(bus)
        check(i > 0, bus + " bus exists")
        var mm := MainMenu.new()
        tree.root.add_child(mm)
        var sl: HSlider = mm.screens.audio.find_child(bus + "Slider", true, false)
        sl.value = 0.4
        near(db_to_linear(AudioServer.get_bus_volume_db(i)), 0.4, 0.01, bus + " slider applied to bus")
        sl.value = 0.0
        check(AudioServer.is_bus_mute(i), bus + " muted at 0")
        mm.free()
    Settings.volumes = keep
    Settings.apply_audio()
    Settings.save()

func test_low_quality_persist_and_signal() -> void:
    var keep: bool = Settings.low_quality
    Settings.set_low_quality(false)
    var got := []
    var cb := func(on): got.append(on)
    Settings.low_quality_changed.connect(cb)
    Settings.set_low_quality(true)
    Settings.set_low_quality(true)
    check(got == [true], "emits once on change (%s)" % [got])
    var path := "user://ui_test_lq.cfg"
    Settings.save(path)
    Settings.set_low_quality(false)
    check(Settings.load_from(path) and Settings.low_quality, "persisted")
    check(got == [true, false, true], "load emits change")
    Settings.low_quality_changed.disconnect(cb)
    Settings.set_low_quality(keep)
    DirAccess.remove_absolute(path)

func test_low_quality_toggle_on_settings_page() -> void:
    var keep: bool = Settings.low_quality
    Settings.set_low_quality(false)
    var mm := MainMenu.new()
    tree.root.add_child(mm)
    var t: CheckButton = mm.screens.settings.find_child("LowQualityToggle", true, false)
    check(t != null and t.custom_minimum_size.y >= 64, "touch-sized toggle")
    t.button_pressed = true
    check(Settings.low_quality, "toggle sets setting")
    check(mm.screens.settings.find_children("*", "ScrollContainer", true, false).size() > 0, "settings page scrolls")
    mm.free()
    Settings.set_low_quality(keep)
    Settings.save()

func test_net_screens_polished_without_behaviour_change() -> void:
    # Only "join" uses the real NetPanel: the host panel calls Net.fetch_public_ip() (HTTP to
    # api.ipify.org) in _ready, which a unit test must not do. Host polish is covered below.
    for kind in ["join"]:
        var mm := MainMenu.new()
        tree.root.add_child(mm)
        var p := NetPanel.new(kind)
        var closed := []
        p.closed.connect(func(): closed.append(1))
        mm.add_screen("net_" + kind, p)
        for e in p.find_children("*", "LineEdit", true, false):
            check(e.custom_minimum_size.y >= 64, kind + " line edit touch height")
            check(e.has_theme_stylebox_override("normal"), kind + " line edit styled")
        var btns: Array = p.find_children("*", "Button", true, false)
        check(btns.size() == 2, kind + " still 2 buttons")
        for b in btns:
            check(b.custom_minimum_size.y >= 64 and b.has_theme_stylebox_override("hover"), kind + " button styled: " + b.text)
        btns[1].pressed.emit()
        check(closed == [1], kind + " Back still emits closed")
        if kind == "join":
            p._go()   # empty address: core validation message unchanged
            check(p.status.text == "Enter an address first.", "join logic untouched")
        mm.free()

func test_polish_host_like_screen() -> void:
    var root := Control.new()
    var m := MarginContainer.new()
    var v := VBoxContainer.new()
    var e := LineEdit.new()
    e.text = "7777"
    e.custom_minimum_size = Vector2(360, 48)
    var b := Button.new()
    b.text = "Start hosting"
    var hits := []
    b.pressed.connect(func(): hits.append(1))
    root.add_child(m)
    m.add_child(v)
    v.add_child(e)
    v.add_child(b)
    MenuStyle.polish(root)
    MenuStyle.polish(root)   # idempotent
    check(e.custom_minimum_size.y >= 64 and e.text == "7777", "edit sized, text kept")
    check(b.custom_minimum_size.y >= 64 and b.text == "Start hosting", "button sized, text kept")
    b.pressed.emit()
    check(hits == [1], "signal untouched")
    check(m.get_theme_constant("margin_left") == 160, "column narrowed")
    root.free()
