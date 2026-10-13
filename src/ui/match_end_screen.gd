class_name MatchEndScreen
extends CanvasLayer
## Match-end screen: VICTORY / DEFEAT / DRAW banner, final scoreboard, Play again / Main menu / Quit.
## Driven by show_results(result) where result = {winner_team: int (-1 draw), reason: String}
## (proposed Events.match_ended, docs/requests/ui.md). Emits play_again / main_menu for the root.
signal play_again
signal main_menu
var banner: Label
var reason_l: Label
var board: VBoxContainer       ## summary: highlights row + team table
var highlights_row: HBoxContainer
var table: ScoreTable
var outcome := ""
var totals_l: Label

## Highlight card: plain label ("Top damage"), hero badge, player name and value. >= 96 px tall.
func _highlight_card(hl: Dictionary) -> PanelContainer:
    var pc := PanelContainer.new()
    pc.custom_minimum_size = Vector2(240, 96)
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.08, 0.11, 0.18, 0.95)
    sb.set_corner_radius_all(10)
    sb.set_content_margin_all(12)
    pc.add_theme_stylebox_override("panel", sb)
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", 12)
    pc.add_child(h)
    h.add_child(HeroBadge.for_hero(hl.hero, 56))
    var v := VBoxContainer.new()
    v.add_child(MenuStyle.label(hl.label, 18))
    v.add_child(MenuStyle.label(hl.name, 22))
    v.add_child(MenuStyle.label(str(hl.value), 26))
    h.add_child(v)
    return pc

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
    board.add_theme_constant_override("separation", 12)
    v.add_child(board)
    highlights_row = HBoxContainer.new()
    highlights_row.name = "Highlights"
    highlights_row.alignment = BoxContainer.ALIGNMENT_CENTER
    highlights_row.add_theme_constant_override("separation", 16)
    board.add_child(highlights_row)
    table = ScoreTable.new()
    board.add_child(table)
    totals_l = MenuStyle.label("", 20)
    totals_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    board.add_child(totals_l)
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
    for c in highlights_row.get_children():
        highlights_row.remove_child(c)
        c.queue_free()
    if stats:
        var heroes := get_tree().get_nodes_in_group("heroes")
        for hl in stats.highlights(heroes):
            highlights_row.add_child(_highlight_card(hl))
        table.build(stats, heroes, player)
        var tt := stats.team_totals(heroes)
        var parts := []
        var ts := tt.keys()
        ts.sort()
        for t in ts:
            parts.append("%s: %d kills, %d damage" % [ScoreTable.team_title(t), tt[t].kills, int(round(tt[t].damage))])
        totals_l.text = "     ".join(parts)
    visible = true
    if DisplayServer.get_name() != "headless":
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
