class_name ControlsHint
extends CanvasLayer
## First-time controls hint, shown by the HUD at match start while `Settings.controls_hint_seen` is false.
## Lists move, look, jump, primary, Shift / E / Q (with the current hero's ability names from AbilityInfo),
## reload (only for weapons with ammo), scoreboard and pause, each with its live key label (Hud.key_label,
## re-read every frame, so rebinds show at once).
## Dismissed by any key, mouse click, tap or gamepad button (that one press is consumed; nothing else
## is blocked: every control ignores the mouse except the toggle). Fades out on its own after
## AUTO_FADE seconds. "Don't show again" (on by default) sets and saves the seen flag when it closes.
## Settings > "Show controls hint" calls request_show(): clears the flag and shows it now if in a match.
signal closed
const AUTO_FADE := 8.0
const FADE_TIME := 0.6
const GROUP := "controls_hint"
var hud   ## Hud: player (current hero, follows swaps) + ability_entry(slot)
var panel: PanelContainer
var grid: GridContainer
var toggle: CheckButton
var footer: Label
var shown_for := 0.0
var fading := false

func _ready() -> void:
    layer = 35   # above the pause overlay (10) and its options screens (30)
    process_mode = Node.PROCESS_MODE_ALWAYS
    add_to_group(GROUP)
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)
    panel = PanelContainer.new()
    panel.name = "Panel"
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.05, 0.07, 0.12, 0.88)
    sb.border_color = MenuStyle.ACCENT
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(12)
    sb.set_content_margin_all(20)
    panel.add_theme_stylebox_override("panel", sb)
    panel.anchor_left = 0.5
    panel.anchor_right = 0.5
    panel.anchor_top = 0.08
    panel.anchor_bottom = 0.08
    panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
    panel.custom_minimum_size.x = 560
    root.add_child(panel)
    var v := VBoxContainer.new()
    v.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v.add_theme_constant_override("separation", 10)
    panel.add_child(v)
    var t := MenuStyle.label("Controls", 30)
    t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(t)
    grid = GridContainer.new()
    grid.name = "Rows"
    grid.columns = 3
    grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
    grid.add_theme_constant_override("h_separation", 18)
    grid.add_theme_constant_override("v_separation", 4)
    v.add_child(grid)
    toggle = MenuStyle.toggle("Don't show again", true, func(_on): pass)
    toggle.name = "DontShowAgain"
    toggle.focus_mode = Control.FOCUS_NONE   # keys always dismiss, never toggle
    toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    v.add_child(toggle)
    footer = MenuStyle.label("Press any key, click or tap to close", 16)
    footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    footer.modulate = Color(1, 1, 1, 0.7)
    v.add_child(footer)
    for n in v.find_children("*", "Label", true, false):
        n.mouse_filter = Control.MOUSE_FILTER_IGNORE
    visible = false

## Rows [action label, key label, detail] for a hero def (keys are read live from the InputMap).
## `entry_for(slot)` returns the AbilityInfo entry for a slot (defaults to AbilityInfo.describe).
static func rows(def, entry_for := Callable()) -> Array:
    var d: Dictionary = def if def is Dictionary else {}
    var name_of := func(slot: String) -> String:
        var e: Dictionary = entry_for.call(slot) if entry_for.is_valid() else AbilityInfo.describe(String(d.get("id", "")), slot, d)
        return String(e.get("name", ""))
    var move := " ".join(["move_forward", "move_left", "move_back", "move_right"].map(func(a): return Hud.key_label(a)))
    var out := [["Move", move, ""], ["Look", "MOUSE", ""], ["Jump", Hud.key_label("jump"), ""]]
    for slot in ["primary", "ability1", "ability2", "ultimate"]:
        out.append([AbilityInfo.SLOT_LABELS[slot], Hud.key_label(AbilityInfo.SLOT_ACTIONS[slot]), name_of.call(slot)])
    if Hud.shows_ammo(d):
        out.append(["Reload", Hud.key_label("reload"), ""])
    out.append(["Scoreboard", Hud.key_label("scoreboard"), "hold"])
    out.append(["Pause", Hud.key_label("pause"), "menu, settings, match"])
    return out

## Show at match start only for real play: not after "Don't show again", not in headless / smoke /
## screenshot / demo runs (Settings.skip_apply), so automated runs never write the flag.
static func should_show() -> bool:
    return not Settings.controls_hint_seen and not Settings.skip_apply and DisplayServer.get_name() != "headless"

## Settings button: clear the flag (so the next match start shows it) and show it now in a running match.
## Returns true if a hint was shown now (false = main menu: it shows at the next match start).
static func request_show(tree: SceneTree) -> bool:
    Settings.controls_hint_seen = false
    Settings.save()
    var any := tree.get_node_count_in_group(GROUP) > 0
    tree.call_group(GROUP, "show_hint")
    return any

func _def():
    return hud.player.def if hud != null and hud.player != null else {}

func refresh() -> void:
    var r := rows(_def(), Callable(hud, "ability_entry") if hud != null and hud.has_method("ability_entry") else Callable())
    while grid.get_child_count() < r.size() * 3:
        var l := MenuStyle.label("", 20)
        l.mouse_filter = Control.MOUSE_FILTER_IGNORE
        l.autowrap_mode = TextServer.AUTOWRAP_OFF
        grid.add_child(l)
    while grid.get_child_count() > r.size() * 3:
        var c := grid.get_child(grid.get_child_count() - 1)
        grid.remove_child(c)
        c.free()
    for i in r.size():
        var a: Label = grid.get_child(i * 3)
        var k: Label = grid.get_child(i * 3 + 1)
        var n: Label = grid.get_child(i * 3 + 2)
        a.text = r[i][0]
        k.text = r[i][1]
        k.add_theme_color_override("font_color", MenuStyle.ACCENT)
        n.text = r[i][2]

func show_hint() -> void:
    shown_for = 0.0
    fading = false
    panel.modulate.a = 1.0
    toggle.set_pressed_no_signal(true)
    refresh()
    visible = true

func is_showing() -> bool:
    return visible and not fading

## Close now (dismiss) or after the fade; saves the seen flag if "Don't show again" is on.
func dismiss() -> void:
    if not visible:
        return
    visible = false
    fading = false
    if toggle.button_pressed:
        Settings.controls_hint_seen = true
        Settings.save()
    closed.emit()

func _process(dt: float) -> void:
    if not visible:
        return
    shown_for += dt
    if not fading:
        refresh()   # live key labels / hero swap
        if shown_for >= AUTO_FADE:
            fading = true
    if fading:
        panel.modulate.a = maxf(0.0, panel.modulate.a - dt / FADE_TIME)
        if panel.modulate.a <= 0.0:
            dismiss()

## Only the dismiss press is consumed; mouse motion (look) and releases pass through. A click or tap
## on the toggle goes to the toggle instead of closing the hint.
func _input(event: InputEvent) -> void:
    if not visible:
        return
    if handle(event):
        get_viewport().set_input_as_handled()

## Returns true if the event dismissed the hint (also used by tests).
func handle(event: InputEvent) -> bool:
    if not visible or not event.is_pressed() or event.is_echo():
        return false
    if event is InputEventMouseButton or event is InputEventScreenTouch:
        if toggle.get_global_rect().has_point(event.position):
            return false
    elif not (event is InputEventKey or event is InputEventJoypadButton):
        return false
    dismiss()
    return true
