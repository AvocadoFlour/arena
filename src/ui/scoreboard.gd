class_name Scoreboard
extends Control
## Shown while the "scoreboard" action (Tab by default, rebindable) is held. Lists every hero in
## group "heroes" with K / D / damage, player highlighted.
var stats: MatchStats
var player
var grid: GridContainer
var held_override := -1   ## tests: 1 = force held, 0 = force released, -1 = read input

func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)
    var panel := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.03, 0.05, 0.1, 0.85)
    sb.set_corner_radius_all(10)
    sb.set_content_margin_all(24)
    panel.add_theme_stylebox_override("panel", sb)
    panel.custom_minimum_size = Vector2(720, 0)
    center.add_child(panel)
    grid = GridContainer.new()
    grid.columns = 5
    grid.add_theme_constant_override("h_separation", 28)
    grid.add_theme_constant_override("v_separation", 8)
    panel.add_child(grid)
    visible = false

func is_held() -> bool:
    if held_override >= 0:
        return held_override == 1
    return InputMap.has_action("scoreboard") and Input.is_action_pressed("scoreboard")

func _process(_dt: float) -> void:
    var want := is_held()
    if want != visible:
        visible = want
    if visible:
        refresh()

func refresh() -> void:
    if grid == null or stats == null:
        return
    for c in grid.get_children():
        grid.remove_child(c)
        c.queue_free()
    for t in ["Player", "Team", "K", "D", "Damage"]:
        grid.add_child(_cell(t, Color(0.7, 0.8, 1.0)))
    for r in stats.sorted_rows(get_tree().get_nodes_in_group("heroes")):
        var col := Color(1, 0.85, 0.3) if r.hero == player else Color.WHITE
        for v in [r.name, str(r.team), str(r.kills), str(r.deaths), str(int(round(r.damage)))]:
            grid.add_child(_cell(v, col))

func row_count() -> int:
    return grid.get_child_count() / grid.columns - 1

func _cell(t: String, col: Color) -> Label:
    var l := Label.new()
    l.text = t
    l.add_theme_font_size_override("font_size", 22)
    l.add_theme_color_override("font_color", col)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l
