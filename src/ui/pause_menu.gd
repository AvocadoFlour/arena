class_name PauseMenu
extends CanvasLayer
## Esc menu: resume, window mode, resolution, mouse sensitivity, quit.
var panel: PanelContainer
var mode_opt: OptionButton
var res_opt: OptionButton
var sens: HSlider

func _ready() -> void:
    layer = 10
    process_mode = Node.PROCESS_MODE_ALWAYS
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.55)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.add_child(center)
    panel = PanelContainer.new()
    panel.custom_minimum_size = Vector2(440, 0)
    center.add_child(panel)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    panel.add_child(v)
    var title := Label.new()
    title.text = "PAUSED  -  Settings"
    title.add_theme_font_size_override("font_size", 28)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(title)
    mode_opt = OptionButton.new()
    for m in Settings.MODES:
        mode_opt.add_item(m)
    mode_opt.selected = max(0, Settings.MODES.find(Settings.window_mode))
    mode_opt.item_selected.connect(func(i): Settings.window_mode = Settings.MODES[i]; _changed())
    v.add_child(_row("Window mode", mode_opt))
    res_opt = OptionButton.new()
    for r in Settings.RESOLUTIONS:
        res_opt.add_item("%d x %d" % [r.x, r.y])
    res_opt.selected = max(0, Settings.RESOLUTIONS.find(Settings.resolution))
    res_opt.item_selected.connect(func(i): Settings.resolution = Settings.RESOLUTIONS[i]; _changed())
    v.add_child(_row("Resolution", res_opt))
    sens = HSlider.new()
    sens.min_value = 0.2
    sens.max_value = 3.0
    sens.step = 0.05
    sens.value = Settings.sensitivity
    sens.custom_minimum_size = Vector2(200, 0)
    sens.value_changed.connect(func(x): Settings.sensitivity = x; _changed())
    v.add_child(_row("Mouse sensitivity", sens))
    var resume := Button.new()
    resume.text = "Resume"
    resume.pressed.connect(close)
    v.add_child(resume)
    var quit := Button.new()
    quit.text = "Quit to desktop"
    quit.pressed.connect(func(): get_tree().quit())
    v.add_child(quit)
    visible = false

func _row(label: String, c: Control) -> HBoxContainer:
    var h := HBoxContainer.new()
    var l := Label.new()
    l.text = label
    l.custom_minimum_size = Vector2(180, 0)
    h.add_child(l)
    c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    h.add_child(c)
    return h

func _changed() -> void:
    Settings.apply()
    Settings.save()

func open() -> void:
    visible = true
    get_tree().paused = true
    Actions.gameplay_enabled = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
    visible = false
    get_tree().paused = false
    Actions.gameplay_enabled = true
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
