class_name PauseMenu
extends CanvasLayer
## In-match Esc overlay: Resume, Settings (reuses MainMenu's Settings / Audio / Controls screens in
## options-only mode), Leave match. main.gd opens it on the "pause" action (INTERFACES §1).
## Offline: pauses the tree. Online (`Net.is_online()`, §10): never pauses the simulation; only shows
## the overlay and blocks gameplay input (`Actions.gameplay_enabled = false`).
## "Controls": read-only reference of every action and its current bindings (KeybindScreen in
## read_only mode); its "Change key bindings" opens the options' rebind screen, whose Back (or Esc)
## returns to the Controls page.
## Esc while open: closes the settings sub-screen first, then the overlay. The key-rebinding screen
## consumes its own Esc in _input (capture cancel), so it never reaches here.
signal leave_requested
signal resumed
var panel: PanelContainer
var options: MainMenu
var paused_tree := false   ## whether *we* paused the tree (offline only)
var match_page: MatchPage
var match_ctl: MatchControl
var swap_layer: CanvasLayer  ## holds match_page.countdown; own layer so it stays up after the overlay closes
var controls_bg: ColorRect      ## holds controls_page (opaque, like the menu screens)
var controls_page: KeybindScreen ## read-only Controls reference
var _from_controls := false      ## rebind screen was opened from the Controls page
var _match_end_hook = null ## fallback leave route: the HUD match-end screen's documented main_menu signal

func _ready() -> void:
    layer = 10
    process_mode = Node.PROCESS_MODE_ALWAYS
    var dim := ColorRect.new()
    dim.name = "Dim"
    dim.color = Color(0, 0, 0, 0.6)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.add_child(center)
    panel = PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = MenuStyle.PANEL
    sb.set_corner_radius_all(14)
    sb.set_content_margin_all(28)
    panel.add_theme_stylebox_override("panel", sb)
    center.add_child(panel)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 16)
    panel.add_child(v)
    v.add_child(MenuStyle.title("PAUSED"))
    var note := MenuStyle.label("", 18)
    note.name = "OnlineNote"
    note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(note)
    for item in [["Resume", close], ["Match", open_match], ["Settings", open_settings], ["Controls", open_controls], ["Leave match", leave]]:
        var b := MenuStyle.button(item[0], item[1])
        b.name = item[0].replace(" ", "")
        b.custom_minimum_size = Vector2(360, 72)
        v.add_child(b)
    match_page = MatchPage.new()
    match_page.visible = false
    center.add_child(match_page)
    match_page.back.connect(close_match)
    swap_layer = CanvasLayer.new()
    swap_layer.name = "SwapLayer"
    swap_layer.layer = 9
    swap_layer.process_mode = Node.PROCESS_MODE_ALWAYS
    swap_layer.add_child(match_page.countdown)
    add_child(swap_layer)   # CanvasLayer visibility doesn't propagate to child layers: stays up when we hide
    set_control(MatchControl.new(get_parent()))
    match_page.set_difficulty_control(DifficultyControl.new(null, get_parent()))
    options = MainMenu.new()
    options.options_only = true
    options.options_closed.connect(_on_options_closed)
    add_child(options)
    options.screens.keybinds.back.connect(_on_rebind_back)
    controls_bg = ColorRect.new()
    controls_bg.name = "ControlsPage"
    controls_bg.color = Color(0.04, 0.06, 0.1, 0.92)
    controls_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    controls_bg.visible = false
    dim.add_child(controls_bg)
    controls_page = KeybindScreen.new()
    controls_page.read_only = true
    controls_bg.add_child(controls_page)
    controls_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    controls_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    controls_page.back.connect(close_controls)
    controls_page.rebind_requested.connect(open_rebind)
    visible = false

## Swap the Match page's adapter (tests pass mocks; default = parent composition root + Net).
func set_control(c: MatchControl) -> void:
    match_ctl = c
    match_page.setup(c)

func open_match() -> void:
    panel.visible = false
    match_page.visible = true
    match_page.refresh()

func close_match() -> void:
    match_page.visible = false
    panel.visible = true

func open_controls() -> void:
    panel.visible = false
    controls_bg.visible = true
    controls_page.refresh()

func close_controls() -> void:
    controls_bg.visible = false
    panel.visible = true

func controls_open() -> bool:
    return controls_bg != null and controls_bg.visible

## "Change key bindings": the existing rebind screen (options, keybinds).
func open_rebind() -> void:
    _from_controls = true
    controls_bg.visible = false
    panel.visible = false
    options.show_screen("keybinds")

## Rebind screen Back: return to the Controls page when we came from it (after its own -> settings).
func _on_rebind_back() -> void:
    if not _from_controls:
        return
    _from_controls = false
    options.show_screen("main")   # hides options -> options_closed -> panel
    open_controls()

func match_open() -> bool:
    return match_page != null and match_page.visible

static func online() -> bool:
    return Net.is_online()

func open() -> void:
    visible = true
    panel.visible = true
    var on := online()
    (panel.find_child("OnlineNote", true, false) as Label).text = "Online match - the game keeps running" if on else ""
    paused_tree = not on
    if paused_tree:
        get_tree().paused = true
    Actions.gameplay_enabled = false
    if DisplayServer.get_name() != "headless":
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
    if options and options.visible:
        options.visible = false
    if match_page:
        match_page.visible = false
    if controls_bg:
        controls_bg.visible = false
    _from_controls = false
    visible = false
    if paused_tree:
        get_tree().paused = false
    paused_tree = false
    Actions.gameplay_enabled = true
    if DisplayServer.get_name() != "headless":
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    resumed.emit()

func open_settings() -> void:
    panel.visible = false
    options.show_screen("settings")

func _on_options_closed() -> void:
    panel.visible = true

func settings_open() -> bool:
    return options != null and options.visible

## Esc while open: one level back. Returns true if consumed.
func handle_escape() -> bool:
    if not visible:
        return false
    if match_open():
        close_match()
        return true
    if controls_open():
        close_controls()
        return true
    if settings_open():
        if options.current == "keybinds" and _from_controls:
            _on_rebind_back()
        elif options.current == "settings":
            options.show_screen("main")    # -> options_closed -> back to the pause panel
        elif options.current == "keybinds":
            options.show_screen("settings")
        else:
            options.show_screen("settings")  # audio etc.
        return true
    close()
    return true

func _unhandled_input(event: InputEvent) -> void:
    # Children receive input before main.gd, so while open we own Esc; closed, main.gd opens us.
    if visible and event.is_action_pressed("pause"):
        handle_escape()
        get_viewport().set_input_as_handled()

## Leave match -> main menu. Preferred: main.gd connects `leave_requested` (requested in
## docs/requests/ui.md). Until then, fall back to the documented match-end route
## (`hud.match_end.main_menu`, INTERFACES §9: main.gd reloads into the main menu, closing Net online).
func leave() -> void:
    if leave_requested.get_connections().size() > 0:
        leave_requested.emit()
        return
    var hook = _find_match_end()
    if hook:
        hook.main_menu.emit()
    else:
        push_warning("PauseMenu.leave: no leave hook connected")

func _find_match_end():
    if _match_end_hook != null:
        return _match_end_hook
    var p := get_parent()
    if p != null and "hud" in p and p.hud != null and "match_end" in p.hud:
        return p.hud.match_end
    return null
