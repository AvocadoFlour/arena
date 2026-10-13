class_name MenuStyle
extends RefCounted
## Shared touch-friendly widgets: large hit targets (>= 64 px tall on the 1280x720 base),
## big fonts, containers + anchors so layouts scale with stretch mode canvas_items/expand.
const MIN_BUTTON := Vector2(320, 64)

static func button(text: String, cb: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = MIN_BUTTON
    b.add_theme_font_size_override("font_size", 26)
    b.focus_mode = Control.FOCUS_ALL
    b.pressed.connect(click)
    b.pressed.connect(cb)
    style_button(b)
    return b

const ACCENT := Color("#3ea0ff")
const PANEL := Color(0.08, 0.11, 0.18, 0.95)

static func _box(bg: Color, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.set_corner_radius_all(10)
    sb.set_border_width_all(bw)
    sb.border_color = border
    sb.content_margin_left = 18
    sb.content_margin_right = 18
    sb.content_margin_top = 8
    sb.content_margin_bottom = 8
    return sb

## Menu click sound (Settings.sfx). Also used by polish() for buttons built elsewhere.
static func click() -> void:
    var st = Engine.get_main_loop().root.get_node_or_null("Settings") if Engine.get_main_loop() is SceneTree else null
    if st and st.sfx:
        st.sfx.play("click")

static func style_button(b: BaseButton) -> void:
    b.add_theme_stylebox_override("normal", _box(Color(0.12, 0.17, 0.27)))
    b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.24, 0.38), ACCENT, 2))
    b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.3)))
    b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), ACCENT, 3))

static func style_line_edit(e: LineEdit) -> void:
    e.custom_minimum_size.y = maxf(e.custom_minimum_size.y, MIN_BUTTON.y)
    e.custom_minimum_size.x = maxf(e.custom_minimum_size.x, 360)
    e.add_theme_font_size_override("font_size", 24)
    e.add_theme_stylebox_override("normal", _box(Color(0.03, 0.05, 0.09), Color(0.3, 0.38, 0.5), 2))
    e.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), ACCENT, 3))

## Touch-sized on/off toggle row (CheckButton, >= 64 px).
static func toggle(text: String, on: bool, cb: Callable) -> CheckButton:
    var c := CheckButton.new()
    c.text = text
    c.button_pressed = on
    c.custom_minimum_size = MIN_BUTTON
    c.add_theme_font_size_override("font_size", 22)
    c.toggled.connect(func(_on): click())
    c.toggled.connect(cb)
    return c

## Visual-only pass over a screen built elsewhere (e.g. core NetPanel via MainMenu.add_screen):
## enforces touch sizes and the shared look on buttons/line edits, and narrows/spaces the content
## column. Never touches text, signals, or behaviour.
static func polish(root: Node) -> void:
    for n in root.find_children("*", "", true, false):
        if n is Button:
            n.custom_minimum_size.y = maxf(n.custom_minimum_size.y, MIN_BUTTON.y)
            n.custom_minimum_size.x = maxf(n.custom_minimum_size.x, MIN_BUTTON.x)
            style_button(n)
            if not n.pressed.is_connected(click):
                n.pressed.connect(click)
        elif n is LineEdit:
            style_line_edit(n)
        elif n is MarginContainer and not n.has_meta("polished"):
            n.set_meta("polished", true)
            for side in ["left", "right"]:
                n.add_theme_constant_override("margin_" + side, 160)
        elif n is VBoxContainer and n.get_parent() is MarginContainer and not n.has_meta("polished"):
            n.set_meta("polished", true)
            n.add_theme_constant_override("separation", 18)

static func label(text: String, size := 22) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return l

static func title(text: String) -> Label:
    var l := label(text, 44)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l

static func margin() -> MarginContainer:
    var m := MarginContainer.new()
    m.set_anchors_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        m.add_theme_constant_override("margin_" + side, 48)
    return m
