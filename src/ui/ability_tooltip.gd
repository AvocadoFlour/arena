class_name AbilityTooltip
extends PanelContainer
## HUD ability tooltip: name + live key binding (Hud.key_label), precise text and compact stats of the slot
## under the pointer. Shown on mouse hover (cursor visible, i.e. not captured) or on a touch long-press
## (LONG_PRESS s without dragging more than DRAG_CANCEL px). Never blocks input: it is MOUSE_FILTER_IGNORE
## everywhere and only *observes* events in feed() (the HUD calls it from _input, never marks them handled).
## Dismiss: pointer leaves (hover), any new click/tap, Esc/pause, or LINGER s after the finger lifts.
## Always kept inside the visible viewport rect (MARGIN px), above the icon when there is room, else below.
const LONG_PRESS := 0.45
const DRAG_CANCEL := 24.0
const LINGER := 4.0
const MARGIN := 8.0
const WIDTH := 440.0

var panels := {}             ## slot -> Control (HUD ability icon panels)
var entry_for: Callable      ## func(slot) -> AbilityInfo entry
var slot := ""               ## slot shown ("" = hidden)
var mode := ""               ## "hover" | "touch"
var _press_slot := ""
var _press_pos := Vector2.ZERO
var _press_t := 0.0
var _linger := -1.0
var _suppress := ""          ## hover slot dismissed by a click: stays hidden until the pointer leaves it
var title: Label
var body: Label
var stats: Label

func _ready() -> void:
    name = "AbilityTooltip"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    visible = false
    z_index = 10
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.04, 0.06, 0.1, 0.94)
    sb.border_color = Color(0.25, 0.6, 1.0, 0.9)
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(8)
    sb.set_content_margin_all(12)
    add_theme_stylebox_override("panel", sb)
    custom_minimum_size = Vector2(WIDTH, 0)
    var v := VBoxContainer.new()
    v.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v.add_theme_constant_override("separation", 6)
    add_child(v)
    title = _lab(v, "Title", 20, Color(1, 1, 1))
    body = _lab(v, "Text", 16, Color(0.88, 0.9, 0.95))
    stats = _lab(v, "Stats", 15, Color(0.55, 0.8, 1.0))

func _lab(parent: Control, n: String, sz: int, col: Color) -> Label:
    var l := Label.new()
    l.name = n
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.custom_minimum_size = Vector2(WIDTH - 24, 0)
    l.add_theme_font_size_override("font_size", sz)
    l.add_theme_color_override("font_color", col)
    parent.add_child(l)
    return l

func slot_at(pos: Vector2) -> String:
    for s in panels:
        var c: Control = panels[s]
        if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
            return s
    return ""

## Observe one input event (never consumes it). Returns true if the tooltip state changed.
func feed(ev: InputEvent, mouse_captured := false) -> bool:
    var before := [slot, mode]
    if ev is InputEventScreenTouch:
        if ev.pressed:
            if slot != "":
                hide_tip()
            _press_slot = slot_at(ev.position)
            _press_pos = ev.position
            _press_t = 0.0
        else:
            _press_slot = ""
            if mode == "touch":
                _linger = LINGER
    elif ev is InputEventScreenDrag:
        if _press_slot != "" and ev.position.distance_to(_press_pos) > DRAG_CANCEL:
            _press_slot = ""
    elif ev is InputEventMouseButton:
        if ev.pressed and ev.device != InputEvent.DEVICE_ID_EMULATION and slot != "":
            if mode == "hover":
                _suppress = slot
            hide_tip()
    elif ev is InputEventMouseMotion:
        if ev.device != InputEvent.DEVICE_ID_EMULATION and mode != "touch":
            var s := "" if mouse_captured else slot_at(ev.position)
            if s != _suppress:
                _suppress = ""
            if s != "" and s != _suppress:
                show_tip(s, "hover")
            elif mode == "hover":
                hide_tip()
    elif ev.is_action_pressed("pause"):
        hide_tip()
    return before != [slot, mode]

## Long-press timer and touch linger; call every frame.
func step(dt: float) -> void:
    if _press_slot != "":
        _press_t += dt
        if _press_t >= LONG_PRESS:
            show_tip(_press_slot, "touch")
            _press_slot = ""
            _linger = -1.0
    if _linger >= 0.0:
        _linger -= dt
        if _linger < 0.0:
            hide_tip()
    if slot != "":
        refresh()   # key binding is live (rebinds show immediately)

func _process(dt: float) -> void:
    step(dt)

func show_tip(s: String, how: String) -> void:
    slot = s
    mode = how
    visible = true
    refresh()

func hide_tip() -> void:
    slot = ""
    mode = ""
    _linger = -1.0
    visible = false

func refresh() -> void:
    var e: Dictionary = entry_for.call(slot) if entry_for.is_valid() else {}
    if e.is_empty():
        e = {"name": slot, "text": "", "stats": {}}
    title.text = "%s  [%s]" % [e.get("name", slot), Hud.key_label(AbilityInfo.SLOT_ACTIONS.get(slot, slot))]
    body.text = String(e.get("text", ""))
    if String(e.get("description", "")) != "" and e.description != e.text:
        body.text += ("\n" if body.text != "" else "") + String(e.description)
    body.visible = body.text != ""
    stats.text = AbilityInfo.stats_line(e.get("stats", {}), 6)
    stats.visible = stats.text != ""
    place()

## Above the icon, centred on it, clamped inside the visible rect; below it if there's no room above.
func place() -> void:
    reset_size()
    var sz := get_combined_minimum_size()
    size = sz
    var vr := get_viewport_rect() if is_inside_tree() else Rect2(0, 0, 1280, 720)
    var anchor := Rect2(vr.size * 0.5, Vector2.ZERO)
    if panels.has(slot) and is_instance_valid(panels[slot]):
        anchor = (panels[slot] as Control).get_global_rect()
    var p := Vector2(anchor.get_center().x - sz.x * 0.5, anchor.position.y - sz.y - MARGIN)
    if p.y < vr.position.y + MARGIN:
        p.y = anchor.end.y + MARGIN
    p.x = clampf(p.x, vr.position.x + MARGIN, maxf(vr.position.x + MARGIN, vr.end.x - sz.x - MARGIN))
    p.y = clampf(p.y, vr.position.y + MARGIN, maxf(vr.position.y + MARGIN, vr.end.y - sz.y - MARGIN))
    global_position = p
