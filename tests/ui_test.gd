extends "res://tests/test_base.gd"
## UI unit tests. Needs a SceneTree (`tree`) for menu tests; run via tests/ui_run_tests.gd.
var tree: SceneTree

func test_catalog_lists_heroes_from_data() -> void:
    var hs := UiCatalog.list_heroes()
    check(hs.size() >= 1, "at least one hero")
    var ids: Array = hs.map(func(h): return h.id)
    check(ids.has("kestrel"), "kestrel discovered: %s" % [ids])
    for f in DirAccess.get_files_at("res://src/heroes"):
        if f.ends_with(".json"):
            check(hs.any(func(h): return h.path.ends_with(f)), "every hero json listed: " + f)

func test_catalog_picks_up_new_hero_automatically() -> void:
    var dir := "user://ui_test_heroes"
    DirAccess.make_dir_recursive_absolute(dir)
    for n in ["a_new.json", "bad.json"]:
        var f := FileAccess.open(dir + "/" + n, FileAccess.WRITE)
        f.store_string('{"id":"zz","name":"Zephyr","role":"Tank","max_hp":400}' if n == "a_new.json" else "not json")
        f.close()
    var hs := UiCatalog.list_heroes(dir)
    check(hs.size() == 1 and hs[0].name == "Zephyr", "new hero found, malformed skipped: %s" % [hs])
    for n in ["a_new.json", "bad.json"]:
        DirAccess.remove_absolute(dir + "/" + n)

func test_catalog_lists_maps() -> void:
    var ms := UiCatalog.list_maps()
    check(ms.size() >= 1, "at least one map")

func test_damage_number_scaling() -> void:
    near(DamageNumber.scale_for_distance(2.0), 1.0, 0.001, "close = base")
    near(DamageNumber.scale_for_distance(16.0), 2.0, 0.001, "2x at 16 m")
    near(DamageNumber.scale_for_distance(500.0), DamageNumber.MAX_SCALE, 0.001, "clamped")
    var d := DamageNumber.new(13.6, "primary", false)
    check(d.text == "14", "rounded text")
    check(d.outline_size >= 12, "thick outline")
    d.free()

func test_rebind_and_swap() -> void:
    Keybinds.reset_defaults()
    var ev := InputEventKey.new()
    ev.physical_keycode = KEY_F
    check(Keybinds.rebind("reload", ev) == "", "no conflict")
    check(Keybinds.binding_text("reload") == "F", "reload -> F (%s)" % Keybinds.binding_text("reload"))
    var e2 := InputEventKey.new()
    e2.physical_keycode = KEY_E   # ability2's key
    check(Keybinds.rebind("reload", e2) == "ability2", "swap reported")
    check(Keybinds.binding_text("ability2") == "F", "ability2 got old key")
    var m := InputEventMouseButton.new()
    m.button_index = MOUSE_BUTTON_RIGHT
    Keybinds.rebind("ability1", m)
    check(Keybinds.binding_text("ability1") == "Mouse Right", "mouse binding")
    Keybinds.reset_defaults()

func test_keybinds_persist() -> void:
    var path := "user://ui_test_keybinds.cfg"
    Keybinds.reset_defaults()
    var ev := InputEventKey.new()
    ev.physical_keycode = KEY_G
    Keybinds.rebind("jump", ev)
    Keybinds.save(path)
    Keybinds.reset_defaults()
    check(Keybinds.binding_text("jump") == "Space", "reset")
    check(Keybinds.load_saved(path), "loaded")
    check(Keybinds.binding_text("jump") == "G", "persisted G")
    Keybinds.reset_defaults()
    DirAccess.remove_absolute(path)

func test_main_menu_structure_and_play() -> void:
    var mm := MainMenu.new()
    tree.root.add_child(mm)
    for n in ["Play", "Heroselect", "Mapselect", "Settings", "Quit"]:
        var b = mm.screens.main.find_child(n, true, false)
        check(b is Button, "button " + n)
        if b:
            check(b.custom_minimum_size.y >= 64, "touch-size " + n)
    check(mm.screens.has("keybinds"), "keybind screen")
    var hero_buttons: Array = mm.screens.heroes.find_children("*", "Button", true, false)
    check(hero_buttons.size() == UiCatalog.list_heroes().size() + 1, "one button per hero + back")
    var got := []
    mm.play_requested.connect(func(h, m): got.append([h, m]))
    mm.show_screen("heroes")
    check(mm.screens.heroes.visible and not mm.screens.main.visible, "screen switch")
    mm.play()
    check(got.size() == 1 and got[0][0].ends_with(".json") and got[0][1].ends_with(".json"), "play emits paths %s" % [got])
    mm.free()

func test_keybind_screen_capture() -> void:
    Keybinds.reset_defaults()
    var ks := KeybindScreen.new()
    tree.root.add_child(ks)
    ks._start("fire")
    var esc := InputEventKey.new()
    esc.physical_keycode = KEY_ESCAPE
    esc.pressed = true
    check(ks.capture(esc) and ks.waiting == "", "esc cancels")
    check(Keybinds.binding_text("fire") == "Mouse Left", "unchanged")
    ks._start("fire")
    var k := InputEventKey.new()
    k.physical_keycode = KEY_V
    k.pressed = true
    check(ks.capture(k), "captured")
    check(ks.buttons.fire.text == "V", "button shows V")
    ks.free()
    Keybinds.reset_defaults()
    Keybinds.save()
