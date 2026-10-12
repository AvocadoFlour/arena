class_name KeybindScreen
extends Control
## Rebinding screen: one large row per action; click, then press a key / mouse button.
## Esc cancels capture. Saves to user://keybinds.cfg immediately.
signal back
var buttons := {}
var waiting := ""
var status: Label

func _ready() -> void:
    Keybinds.ensure_ui_actions()
    set_anchors_preset(Control.PRESET_FULL_RECT)
    var m := MenuStyle.margin()
    add_child(m)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    m.add_child(v)
    v.add_child(MenuStyle.title("Controls"))
    status = MenuStyle.label("Click an action, then press a key or mouse button. Esc cancels.", 18)
    v.add_child(status)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(scroll)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 20)
    grid.add_theme_constant_override("v_separation", 8)
    scroll.add_child(grid)
    for a in Keybinds.actions():
        var l := MenuStyle.label(Keybinds.pretty(a), 22)
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grid.add_child(l)
        var b := MenuStyle.button("", func(): _start(a))
        b.custom_minimum_size.x = 260
        grid.add_child(b)
        buttons[a] = b
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    row.add_child(MenuStyle.button("Reset defaults", func(): Keybinds.reset_defaults(); Keybinds.save(); refresh()))
    row.add_child(MenuStyle.button("Back", func(): waiting = ""; back.emit()))
    v.add_child(row)
    refresh()

func refresh() -> void:
    for a in buttons:
        buttons[a].text = "Press a key..." if a == waiting else Keybinds.binding_text(a)

func _start(a: String) -> void:
    waiting = a
    refresh()

## Feed a captured event (also used by tests). Returns true if consumed.
func capture(ev: InputEvent) -> bool:
    if waiting == "" or not ev.is_pressed() or ev.is_echo():
        return false
    if ev is InputEventKey and (ev.physical_keycode == KEY_ESCAPE or ev.keycode == KEY_ESCAPE):
        waiting = ""
        refresh()
        return true
    if not (ev is InputEventKey or ev is InputEventMouseButton):
        return false
    var displaced := Keybinds.rebind(waiting, ev)
    status.text = ("Swapped with %s." % Keybinds.pretty(displaced)) if displaced != "" else "Saved."
    waiting = ""
    Keybinds.save()
    refresh()
    return true

func _input(ev: InputEvent) -> void:
    if visible and capture(ev):
        get_viewport().set_input_as_handled()
