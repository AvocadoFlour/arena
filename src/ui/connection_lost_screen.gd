class_name ConnectionLostScreen
extends CanvasLayer
## Full-screen "Connection lost" / "Host left" notice with the reason and a big Return to menu button.
## Shown from Net.disconnected(reason) while in an online match. Return goes through the documented route:
## `return_requested` if someone connects it, else the pause overlay's `leave_requested` (main.gd →
## _restart(false), INTERFACES "Pause overlay"), else the match-end `main_menu` signal (§9).
signal return_requested
var title: Label
var reason_l: Label
var return_btn: Button
var reason := ""
var routes: Array = []   ## [Signal] fallbacks, tried in order (set by Hud)

static func title_for(r: String) -> String:
    var l := r.to_lower()
    return "Host left" if l.contains("host") and (l.contains("closed") or l.contains("left")) else "Connection lost"

func _ready() -> void:
    layer = 40   # above HUD, pause overlay and match-end
    process_mode = Node.PROCESS_MODE_ALWAYS
    var bg := ColorRect.new()
    bg.color = Color(0.02, 0.03, 0.06, 0.92)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    var m := MenuStyle.margin()
    bg.add_child(m)
    var v := VBoxContainer.new()
    v.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_theme_constant_override("separation", 22)
    m.add_child(v)
    title = MenuStyle.title("")
    title.add_theme_font_size_override("font_size", 56)
    v.add_child(title)
    reason_l = MenuStyle.label("", 24)
    reason_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(reason_l)
    return_btn = MenuStyle.button("Return to menu", go_back)
    return_btn.name = "ReturnToMenu"
    return_btn.custom_minimum_size = Vector2(420, 96)
    return_btn.add_theme_font_size_override("font_size", 32)
    return_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    v.add_child(return_btn)
    visible = false

func show_lost(r: String) -> void:
    reason = r
    title.text = title_for(r)
    reason_l.text = r.capitalize() if r != "" else "The connection to the other players was lost."
    visible = true
    Actions.gameplay_enabled = false
    if DisplayServer.get_name() != "headless":
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    return_btn.grab_focus.call_deferred()

func go_back() -> void:
    if return_requested.get_connections().size() > 0:
        return_requested.emit()
        return
    for s in routes:
        if s is Signal and not s.is_null():
            s.emit()
            return
    push_warning("ConnectionLostScreen: no return route")
