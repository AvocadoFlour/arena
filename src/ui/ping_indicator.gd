class_name PingIndicator
extends PanelContainer
## HUD connection indicator (top-left under FPS), visible only while online.
## Ping colours: < GOOD ms green, < OK ms yellow, else red. Warning state when no packet arrived for
## STALL s ("Connection unstable", orange, pulsing). Unknown ping (Net exposes none yet) = "Ping --" grey.
const GOOD := 60
const OK := 120
const STALL := 0.75
const COL_GOOD := Color("#3ee07a")
const COL_OK := Color("#ffd23e")
const COL_BAD := Color("#ff4848")
const COL_WARN := Color("#ff9a2e")
const COL_UNKNOWN := Color(0.7, 0.7, 0.75)
var info: NetLinkInfo
var label: Label
var dot: ColorRect
var state := "hidden"   ## hidden | unknown | good | ok | bad | stalled
var _t := 0.0

static func classify(ping: int, age: float) -> String:
    if age >= STALL:
        return "stalled"
    if ping < 0:
        return "unknown"
    if ping < GOOD:
        return "good"
    return "ok" if ping < OK else "bad"

static func color_for(st: String) -> Color:
    return {"good": COL_GOOD, "ok": COL_OK, "bad": COL_BAD, "stalled": COL_WARN}.get(st, COL_UNKNOWN)

static func text_for(st: String, ping: int) -> String:
    if st == "stalled":
        return "Connection unstable"
    return "Ping --" if ping < 0 else "Ping %d ms" % ping

func _ready() -> void:
    if info == null:
        info = NetLinkInfo.new()
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0.5)
    sb.set_corner_radius_all(6)
    sb.set_content_margin_all(6)
    add_theme_stylebox_override("panel", sb)
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", 8)
    h.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(h)
    dot = ColorRect.new()
    dot.custom_minimum_size = Vector2(14, 14)
    dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    h.add_child(dot)
    label = Label.new()
    label.add_theme_font_size_override("font_size", 18)
    label.add_theme_color_override("font_outline_color", Color.BLACK)
    label.add_theme_constant_override("outline_size", 5)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    h.add_child(label)
    refresh()

func refresh() -> void:
    if not info.online():
        state = "hidden"
        visible = false
        return
    visible = true
    var ping := info.ping_ms()
    state = classify(ping, info.last_packet_age())
    var c := color_for(state)
    dot.color = c
    label.text = text_for(state, ping)
    label.add_theme_color_override("font_color", c)

func _process(dt: float) -> void:
    _t += dt
    if _t >= 0.25:   # 4 Hz
        _t = 0.0
        refresh()
    if state == "stalled":
        modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 200.0))
    else:
        modulate.a = 1.0
