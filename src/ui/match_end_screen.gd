class_name MatchEndScreen
extends CanvasLayer
## Match-end screen: VICTORY / DEFEAT / DRAW banner, final scoreboard, Play again / Main menu / Quit.
## Driven by show_results(result) where result = {winner_team: int (-1 draw), reason: String}
## (proposed Events.match_ended, docs/requests/ui.md). Emits play_again / main_menu for the root.
signal play_again
signal main_menu
var banner: Label
var reason_l: Label
var board: VBoxContainer
var outcome := ""

func _ready() -> void:
    layer = 15
    process_mode = Node.PROCESS_MODE_ALWAYS
    var bg := ColorRect.new()
    bg.color = Color(0, 0, 0, 0.75)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    var m := MenuStyle.margin()
    bg.add_child(m)
    var v := VBoxContainer.new()
    v.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_theme_constant_override("separation", 14)
    m.add_child(v)
    banner = MenuStyle.title("")
    banner.add_theme_font_size_override("font_size", 64)
    v.add_child(banner)
    reason_l = MenuStyle.label("", 22)
    reason_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(reason_l)
    board = VBoxContainer.new()
    v.add_child(board)
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 16)
    row.add_child(MenuStyle.button("Play again", func(): play_again.emit()))
    row.add_child(MenuStyle.button("Main menu", func(): main_menu.emit()))
    row.add_child(MenuStyle.button("Quit", func(): get_tree().quit()))
    v.add_child(row)
    visible = false

static func outcome_for(winner_team: int, player_team: int) -> String:
    if winner_team < 0:
        return "DRAW"
    return "VICTORY" if winner_team == player_team else "DEFEAT"

func show_results(result: Dictionary, stats: MatchStats = null, player = null) -> void:
    var pt: int = player.team if player else 0
    outcome = outcome_for(int(result.get("winner_team", -1)), pt)
    banner.text = outcome
    banner.add_theme_color_override("font_color", {"VICTORY": Color(1, 0.85, 0.3), "DEFEAT": Color(1, 0.35, 0.35)}.get(outcome, Color.WHITE))
    reason_l.text = str(result.get("reason", ""))
    for c in board.get_children():
        c.queue_free()
    if stats:
        for r in stats.sorted_rows(get_tree().get_nodes_in_group("heroes")):
            var l := MenuStyle.label("%s    %d / %d    %d dmg" % [r.name, r.kills, r.deaths, int(round(r.damage))], 22)
            l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            board.add_child(l)
    visible = true
    if DisplayServer.get_name() != "headless":
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
