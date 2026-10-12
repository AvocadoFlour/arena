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
    b.pressed.connect(cb)
    return b

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
