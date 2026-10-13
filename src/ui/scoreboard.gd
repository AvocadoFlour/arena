class_name Scoreboard
extends Control
## Shown while the "scoreboard" action (Tab by default, rebindable) is held: team columns with hero
## badges and K / D / damage / healing per player (ScoreTable), player highlighted.
var stats: MatchStats
var player
var table: ScoreTable
var held_override := -1   ## tests: 1 = force held, 0 = force released, -1 = read input
var _t := 0.0

func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var m := MenuStyle.margin()
    m.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(m)
    var center := CenterContainer.new()
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    m.add_child(center)
    table = ScoreTable.new()
    table.mouse_filter = Control.MOUSE_FILTER_IGNORE
    table.custom_minimum_size = Vector2(900, 0)
    center.add_child(table)
    visible = false

func is_held() -> bool:
    if held_override >= 0:
        return held_override == 1
    return InputMap.has_action("scoreboard") and Input.is_action_pressed("scoreboard")

func _process(dt: float) -> void:
    var want := is_held()
    if want != visible:
        visible = want
        _t = 0.0
        if visible:
            refresh()
    elif visible:
        _t += dt
        if _t >= 0.25:   # 4 Hz is plenty while held
            _t = 0.0
            refresh()

func refresh() -> void:
    if table == null or stats == null:
        return
    table.build(stats, get_tree().get_nodes_in_group("heroes"), player)

func row_count() -> int:
    return table.row_total if table else 0
