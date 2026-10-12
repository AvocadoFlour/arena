extends "res://tests/test_base.gd"
## UI round 3: ammo hidden for melee, role labels, audio/FOV settings, network menu slot.
var tree: SceneTree

func test_ammo_hidden_for_melee_defs() -> void:
    check(not Hud.shows_ammo({"primary": {"type": "melee", "mag": 999}}), "melee hidden")
    check(not Hud.shows_ammo({"primary": {"type": "melee", "mag": 30}}), "melee hidden regardless of mag")
    check(not Hud.shows_ammo({"primary": {"type": "hitscan", "mag": 999}}), "no-ammo sentinel hidden")
    check(Hud.shows_ammo({"primary": {"type": "hitscan", "mag": 24}}), "hitscan shown")
    check(Hud.shows_ammo({"primary": {"mag": 24}}), "default type = hitscan")
    for h in UiCatalog.list_heroes():
        var d = JSON.parse_string(FileAccess.get_file_as_string(h.path))
        check(Hud.shows_ammo(d) == (d.primary.get("type", "hitscan") != "melee"), "real def " + h.id)

func test_role_labels_from_defs() -> void:
    check(UiCatalog.role_label("support") == "Support", "support")
    check(UiCatalog.role_label("brawler") == "Brawler", "brawler")
    check(UiCatalog.role_label("tank") == "Tank", "tank")
    check(UiCatalog.role_label("") == "Unknown role" and UiCatalog.role_label(null) == "Unknown role", "missing role flagged")
    for h in UiCatalog.list_heroes():
        check(h.role != "", "def has role: " + h.id)
        var t := MainMenu.hero_button_text(h)
        check(t.contains(h.name) and t.contains(UiCatalog.role_label(h.role)), "button shows role: " + t)

func test_hero_select_buttons_show_roles() -> void:
    var mm := MainMenu.new()
    tree.root.add_child(mm)
    var texts: Array = mm.screens.heroes.find_children("*", "Button", true, false).map(func(b): return b.text)
    for h in UiCatalog.list_heroes():
        check(texts.has(MainMenu.hero_button_text(h)), "listed with role: " + h.id)
    mm.free()

func test_settings_persist_audio_fov() -> void:
    var keep_fov: float = Settings.fov
    var keep_vol: Dictionary = Settings.volumes.duplicate()
    var path := "user://ui_test_settings.cfg"
    Settings.fov = 95.0
    check(Settings.set_volume("Master", 0.5), "Master bus exists and is applied")
    check(not Settings.set_volume("Music", 0.3), "Music bus absent: stored only")
    near(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.5, 0.01, "master volume applied")
    Settings.save(path)
    Settings.fov = 75.0
    Settings.volumes = {"Master": 1.0, "Music": 1.0, "SFX": 1.0}
    check(Settings.load_from(path), "loaded")
    near(Settings.fov, 95.0, 0.01, "fov persisted")
    near(Settings.volume("Music"), 0.3, 0.01, "music persisted")
    near(Settings.volume("Master"), 0.5, 0.01, "master persisted")
    var cam := Camera3D.new()
    Settings.apply_fov(cam)
    near(cam.fov, 95.0, 0.01, "fov applied to camera")
    Settings.fov = 500.0
    Settings.apply_fov(cam)
    near(cam.fov, Settings.FOV_MAX, 0.01, "fov clamped")
    cam.free()
    Settings.fov = keep_fov
    Settings.volumes = keep_vol
    Settings.apply_audio()
    DirAccess.remove_absolute(path)

func test_settings_screens_have_fov_and_audio() -> void:
    var mm := MainMenu.new()
    tree.root.add_child(mm)
    check(mm.screens.settings.find_child("FovSlider", true, false) is HSlider, "fov slider")
    for b in Settings.AUDIO_BUSES:
        check(mm.screens.audio.find_child(b + "Slider", true, false) is HSlider, "audio slider " + b)
    mm.free()

func test_network_slot_hook() -> void:
    var mm := MainMenu.new()
    tree.root.add_child(mm)
    check(mm.network_slot != null and not mm.network_slot.visible, "empty hidden slot")
    var hit := []
    var b := mm.add_menu_entry("Host", func(): hit.append(1))
    check(mm.network_slot.visible and b.custom_minimum_size.y >= 64, "entry added, touch size")
    var main_btns: Array = mm.screens.main.find_children("*", "Button", true, false)
    check(main_btns[0].name == "Play" and main_btns[1] == b, "slot sits right under Play")
    b.pressed.emit()
    check(hit == [1], "callback")
    var scr := Control.new()
    mm.add_screen("host", scr)
    mm.show_screen("host")
    check(scr.visible and not mm.screens.main.visible, "custom screen")
    mm.free()
