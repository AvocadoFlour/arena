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
    bg.name = "Background"
    add_child(bg)
    screens.main = _main_screen()
    screens.heroes = _list_screen("Choose hero", heroes, func(e): return hero_button_text(e), "hero")
    screens.maps = _list_screen("Choose map", maps, func(e): return e.name, "map")
    screens.settings = _settings_screen()
    screens.audio = _audio_screen()
    var kb := KeybindScreen.new()
    kb.back.connect(func(): show_screen("settings"))
    screens.keybinds = kb
    for k in screens:
        bg.add_child(screens[k])
    if not options_only:
        refresh_difficulty()
    if options_only:
        layer = 30   # above the pause overlay
        visible = false
        for k in screens:
            screens[k].visible = false
    else:
        show_screen("main")

## Options-only mode (in-match pause overlay reuses Settings / Audio / Controls): starts on
## "settings"; navigating back to "main" hides the menu and emits options_closed instead.
signal options_closed
var options_only := false

func show_screen(n: String) -> void:
    if options_only and n == "main":
        current = ""
        for k in screens:
            screens[k].visible = false
        visible = false
        options_closed.emit()
        return
    if options_only:
        visible = true
    current = n
    if n == "heroes":
        _refresh_hero_detail.call_deferred()
    for k in screens:
        screens[k].visible = k == n
    _refresh_info()

func _refresh_info() -> void:
    if hero_info:
        hero_info.text = "Hero: %s     Map: %s" % [_name_of(heroes, UiCatalog.selected_hero), _name_of(maps, UiCatalog.selected_map)]
        if diff_ctl != null:
            hero_info.text += "     Bots: %s / %s" % [DifficultyControl.LABELS[Settings.bot_difficulty[0]], DifficultyControl.LABELS[Settings.bot_difficulty[1]]]

func _name_of(list: Array, path: String) -> String:
    for e in list:
        if e.path == path:
            return e.name
    return "-"

func _centered_column(scroll := false) -> Array:
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    var m := MenuStyle.margin()
    root.add_child(m)
    var v := VBoxContainer.new()
    v.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_theme_constant_override("separation", 14)
    if scroll:   # long pages scroll instead of overflowing on 720p / phone screens
        var sc := ScrollContainer.new()
        sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        v.size_flags_vertical = Control.SIZE_EXPAND_FILL
        sc.add_child(v)
        m.add_child(sc)
    else:
        m.add_child(v)
    return [root, v]

## Network hook (core fills this; UI builds no Host/Join flow). Empty and hidden until used.
## Core: `main_menu.add_menu_entry("Host", cb)` adds a touch-sized button in the slot right under Play;
## `main_menu.add_screen("host", control)` registers a full screen reachable via `show_screen("host")`.
var network_slot: VBoxContainer

func add_menu_entry(text: String, cb: Callable) -> Button:
    var b := MenuStyle.button(text, cb)
    b.name = text.replace(" ", "")
    b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    network_slot.add_child(b)
    network_slot.visible = true
    return b

func add_screen(n: String, c: Control) -> void:
    c.set_anchors_preset(Control.PRESET_FULL_RECT)
    screens[n] = c
    $Background.add_child(c)   # runs c._ready(), so polish sees the built widgets
    MenuStyle.polish(c)
    c.visible = current == n

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
        if item[0] == "Play":
            network_slot = VBoxContainer.new()
            network_slot.name = "NetworkSlot"
            network_slot.add_theme_constant_override("separation", 10)
            network_slot.visible = false
            v.add_child(network_slot)
    return rv[0]

## Hero-select entry: name + role label (from the def's "role") + HP.
static func hero_button_text(e: Dictionary) -> String:
    return "%s    %s    %d HP" % [e.name, UiCatalog.role_label(e.get("role", "")), e.get("max_hp", 0)]

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
        var cb := (func(): select(kind, e.path)) if kind == "hero" else (func(): select(kind, e.path); show_screen("main"))
        var b := MenuStyle.button(fmt.call(e), cb)
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.toggle_mode = kind == "hero"
        b.set_meta("path", e.path)
        col.add_child(b)
    if kind == "hero":
        # Hero select: list | detail (3D preview + role + abilities). Picking a hero updates the detail
        # and stays here; Back returns. The split stacks vertically on narrow screens.
        v.remove_child(scroll)
        var split := HeroSplit.new()
        split.size_flags_vertical = Control.SIZE_EXPAND_FILL
        v.add_child(split)
        scroll.custom_minimum_size.x = 360
        split.add_child(scroll)
        hero_detail = HeroDetail.new()
        split.add_child(hero_detail)
        hero_list = col
    if kind == "map":
        scroll.custom_minimum_size.y = 200
        v.add_child(MenuStyle.label("Bot difficulty", 24))
        diff_picker = DifficultyPicker.new()
        diff_picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        v.add_child(diff_picker)
        diff_picker.picked.connect(pick_difficulty)
    v.add_child(MenuStyle.button("Back", func(): show_screen("main")))
    return rv[0]

var diff_picker: DifficultyPicker
var diff_ctl: DifficultyControl

## Pre-match bot difficulty: saved in Settings (last choice) and pushed to GameConfig (INTERFACES §8).
func pick_difficulty(team: int, level: String) -> void:
    if diff_ctl == null or not diff_ctl.prematch_available(team):
        refresh_difficulty()
        return
    Settings.bot_difficulty[team] = level
    Settings.save()
    diff_ctl.apply_prematch(team, level)
    refresh_difficulty()

## Applies the saved choice to GameConfig and syncs the picker (disabled rows say "Not available yet").
func refresh_difficulty() -> void:
    if diff_ctl == null:
        diff_ctl = DifficultyControl.new()
    var na := false
    for t in [0, 1]:
        var ok := diff_ctl.prematch_available(t)
        na = na or not ok
        if ok:
            diff_ctl.apply_prematch(t, String(Settings.bot_difficulty[t]))
        if diff_picker:
            diff_picker.set_row(t, String(Settings.bot_difficulty[t]), ok)
    if diff_picker:
        diff_picker.note.text = ("Your team: " + MatchPage.NA + " (all bots use the Enemy team setting)") if na else ""
    _refresh_info()

var hero_detail: HeroDetail
var hero_list: VBoxContainer

## List + detail container: side by side when wide, stacked when narrow (detail first = preview on top).
class HeroSplit extends BoxContainer:
    func _ready() -> void:
        add_theme_constant_override("separation", 16)
        resized.connect(func(): set_narrow(size.x < HeroDetail.NARROW))
    func set_narrow(n: bool) -> void:
        vertical = n
        if get_child_count() == 2:
            var detail := get_child(0) if get_child(0) is HeroDetail else get_child(1)
            move_child(detail, 0 if n else 1)

func _refresh_hero_detail() -> void:
    if hero_detail == null or not hero_detail.is_inside_tree():
        return
    if hero_detail.preview == null:
        return
    hero_detail.show_path(UiCatalog.selected_hero)
    for b in hero_list.get_children():
        if b is Button:
            b.set_pressed_no_signal(b.get_meta("path", "") == UiCatalog.selected_hero)

func select(kind: String, path: String) -> void:
    if kind == "hero":
        UiCatalog.selected_hero = path
        _refresh_hero_detail()
    else:
        UiCatalog.selected_map = path
    _refresh_info()

func _settings_screen() -> Control:
    var rv := _centered_column(true)
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
    var fov := HSlider.new()
    fov.name = "FovSlider"
    fov.min_value = Settings.FOV_MIN
    fov.max_value = Settings.FOV_MAX
    fov.step = 1
    fov.value = Settings.fov
    fov.value_changed.connect(func(x): Settings.fov = x; _changed())
    v.add_child(_row("Field of view", fov))
    var lq := MenuStyle.toggle("Low quality (faster on weak GPUs / phones)", Settings.low_quality,
        func(on): Settings.set_low_quality(on); Settings.save())
    lq.name = "LowQualityToggle"
    v.add_child(lq)
    var dn := MenuStyle.toggle("Damage numbers", Settings.damage_numbers,
        func(on): Settings.damage_numbers = on; Settings.save())
    dn.name = "DamageNumbersToggle"
    v.add_child(dn)
    v.add_child(MenuStyle.button("Audio", func(): show_screen("audio")))
    v.add_child(MenuStyle.button("Controls / key bindings", func(): show_screen("keybinds")))
    var sh_note := MenuStyle.label("", 18)
    sh_note.name = "ControlsHintNote"
    var sh := MenuStyle.button("Show controls hint", func():
        sh_note.text = "" if ControlsHint.request_show(get_tree()) else "The controls hint will show at the start of the next match.")
    sh.name = "ShowControlsHint"
    v.add_child(sh)
    v.add_child(sh_note)
    v.add_child(MenuStyle.button("Back", func(): show_screen("main")))
    return rv[0]

func _audio_screen() -> Control:
    var rv := _centered_column()
    var v: VBoxContainer = rv[1]
    v.add_child(MenuStyle.title("Audio"))
    for bus in Settings.AUDIO_BUSES:
        var sl := HSlider.new()
        sl.name = bus + "Slider"
        sl.min_value = 0.0
        sl.max_value = 1.0
        sl.step = 0.05
        sl.value = Settings.volume(bus)
        sl.value_changed.connect(func(x): Settings.set_volume(bus, x); Settings.save())
        v.add_child(_row(bus + " volume", sl))
    v.add_child(MenuStyle.button("Back", func(): show_screen("settings")))
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
