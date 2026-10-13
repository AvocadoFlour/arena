class_name DifficultyPicker
extends VBoxContainer
## Two rows (Your team / Enemy team) of Easy / Normal / Hard toggle buttons (touch-sized, one pressed per row).
## Emits picked(team, level). The owner decides enabled state and notes (set_row / set_note).
signal picked(team: int, level: String)
var rows := {}     ## team -> {"btns": {level: Button}, "group": ButtonGroup}
var note: Label

func _ready() -> void:
    name = "DifficultyPicker"
    add_theme_constant_override("separation", 10)
    for t in [0, 1]:
        var row := HBoxContainer.new()
        row.name = "DiffTeam%d" % t
        row.add_theme_constant_override("separation", 8)
        var l := MenuStyle.label("Your team" if t == 0 else "Enemy team", 20)
        l.custom_minimum_size = Vector2(150, 0)
        row.add_child(l)
        var g := ButtonGroup.new()
        var btns := {}
        for lv in DifficultyControl.LEVELS:
            var b := MenuStyle.button(DifficultyControl.LABELS[lv], _on_pick.bind(t, lv))
            b.name = DifficultyControl.LABELS[lv]
            b.toggle_mode = true
            b.button_group = g
            b.custom_minimum_size = Vector2(110, 64)
            row.add_child(b)
            btns[lv] = b
        rows[t] = {"btns": btns, "group": g}
        add_child(row)
    note = MenuStyle.label("", 18)
    note.name = "DiffNote"
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.custom_minimum_size = Vector2(400, 0)
    add_child(note)

func _on_pick(t: int, lv: String) -> void:
    picked.emit(t, lv)

## Shows `level` as pressed (no signal) and enables/disables the row.
func set_row(team: int, level: String, enabled: bool) -> void:
    for lv in rows[team].btns:
        var b: Button = rows[team].btns[lv]
        b.set_pressed_no_signal(lv == level)
        b.disabled = not enabled

func pressed_level(team: int) -> String:
    for lv in rows[team].btns:
        if rows[team].btns[lv].button_pressed:
            return lv
    return ""

func button(team: int, level: String) -> Button:
    return rows[team].btns[level]
