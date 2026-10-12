class_name MainMenu
extends CanvasLayer
## Main menu: Play, Hero select, Map select, Settings, Quit. Builds its screens in code.
## Hero/map lists come from UiCatalog (data folders), never hardcoded.
## Emits play_requested(hero_path, map_path); the composition root (src/main.gd) starts the match.
signal play_requested(hero_path: String, map_path: String)
var screens := {}
var current := ""
var heroes: Array = []
var maps: Array = []
var hero_info: Label
var map_info: Label
var sens: HSlider

func _ready() -> void:
    layer = 20
    process_mode = Node.PROCESS_MODE_ALWAYS
    heroes = UiCatalog.list_heroes()
    maps = UiCatalog.list_maps()
    if UiCatalog.selected_hero == "" and heroes.size() > 0:
        UiCatalog.selected_hero = heroes[0].path
    if UiCatalog.selected_map == "" and maps.size() > 0:
        UiCatalog.selected_map = maps[0].path
    var bg := ColorRect.new()
    bg.color = Color(0.04, 0.06, 0.1, 0.92)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    screens.main = _main_screen()
    screens.heroes = _list_screen("Choose hero", heroes, func(e): return "%s  -  %s  (%d HP)" % [e.name, e.role, e.max_hp], "hero")
    screens.maps = _list_screen("Choose map", maps, func(e): return e.name, "map")
    screens.settings = _settings_screen()
    var kb := KeybindScreen.new()
    kb.back.connect(func(): show_screen("settings"))
    screens.keybinds = kb
    for k in screens:
        bg.add_child(screens[k])
    show_screen("main")

func show_screen(n: String) -> void:
    current = n
    for k in screens:
        screens[k].visible = k == n
    _refresh_info()

func _refresh_info() -> void:
    if hero_info:
        hero_info.text = "Hero: %s     Map: %s" % [_name_of(heroes, UiCatalog.selected_hero), _name_of(maps, UiCatalog.selected_map)]

func _name_of(list: Array, path: String) -> String:
    for e in list:
        if e.path == path:
            return e.name
    return "-"

func _centered_column() -> Array:
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    var m := MenuStyle.margin()
    root.add_child(m)
    var v := VBoxContainer.new()
    v.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_theme_constant_override("separation", 14)
    m.add_child(v)
    return [root, v]

func _main_screen() -> Control:
    var rv := _centered_column()
    var v: VBoxContainer = rv[1]
    v.add_child(MenuStyle.title("ARENA"))
    hero_info = MenuStyle.label("", 20)
    hero_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(hero_info)
    for item in [["Play", play], ["Hero select", func(): show_screen("heroes")],
            ["Map select", func(): show_screen("maps")], ["Settings", func(): show_screen("settings")],
            ["Quit", func(): get_tree().quit()]]:
        var b := MenuStyle.button(item[0], item[1])
        b.name = item[0].replace(" ", "")
        b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        v.add_child(b)
    return rv[0]

func _list_screen(title: String, list: Array, fmt: Callable, kind: String) -> Control:
    var rv := _centered_column()
    var v: VBoxContainer = rv[1]
    v.add_child(MenuStyle.title(title))
    if list.is_empty():
        v.add_child(MenuStyle.label("Nothing found.", 22))
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(scroll)
    var col := VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.add_theme_constant_override("separation", 10)
    scroll.add_child(col)
    for e in list:
        var b := MenuStyle.button(fmt.call(e), func(): select(kind, e.path); show_screen("main"))
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        col.add_child(b)
    v.add_child(MenuStyle.button("Back", func(): show_screen("main")))
    return rv[0]

func select(kind: String, path: String) -> void:
    if kind == "hero":
        UiCatalog.selected_hero = path
    else:
        UiCatalog.selected_map = path
    _refresh_info()

func _settings_screen() -> Control:
    var rv := _centered_column()
    var v: VBoxContainer = rv[1]
    v.add_child(MenuStyle.title("Settings"))
    var mode := OptionButton.new()
    for m in Settings.MODES:
        mode.add_item(m)
    mode.selected = max(0, Settings.MODES.find(Settings.window_mode))
    mode.item_selected.connect(func(i): Settings.window_mode = Settings.MODES[i]; _changed())
    v.add_child(_row("Window mode", mode))
    var res := OptionButton.new()
    for r in Settings.RESOLUTIONS:
        res.add_item("%d x %d" % [r.x, r.y])
    res.selected = max(0, Settings.RESOLUTIONS.find(Settings.resolution))
    res.item_selected.connect(func(i): Settings.resolution = Settings.RESOLUTIONS[i]; _changed())
    v.add_child(_row("Resolution", res))
    sens = HSlider.new()
    sens.min_value = 0.2
    sens.max_value = 3.0
    sens.step = 0.05
    sens.value = Settings.sensitivity
    sens.value_changed.connect(func(x): Settings.sensitivity = x; _changed())
    v.add_child(_row("Mouse sensitivity", sens))
    v.add_child(MenuStyle.button("Controls / key bindings", func(): show_screen("keybinds")))
    v.add_child(MenuStyle.button("Back", func(): show_screen("main")))
    return rv[0]

func _row(label: String, c: Control) -> HBoxContainer:
    var h := HBoxContainer.new()
    var l := MenuStyle.label(label, 22)
    l.custom_minimum_size = Vector2(260, 0)
    h.add_child(l)
    c.custom_minimum_size = Vector2(320, 64)
    c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    h.add_child(c)
    return h

func _changed() -> void:
    Settings.apply()
    Settings.save()

func play() -> void:
    play_requested.emit(UiCatalog.selected_hero, UiCatalog.selected_map)
