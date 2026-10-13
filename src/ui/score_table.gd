class_name ScoreTable
extends HBoxContainer
## Team-column score table shared by the Tab scoreboard and the match-end summary.
## One panel per team; each row: badge (hero initials), player name, K, D, damage, healing.
## Rows are >= 52 px tall (touch-friendly); the local player's row is highlighted.
const COLS := ["", "Player", "K", "D", "Damage", "Healing"]
const ROW_H := 52.0
const HIGHLIGHT := Color(1, 0.85, 0.3)
var row_total := 0

static func team_title(team: int) -> String:
    return "Team %d" % (team + 1) if team >= 0 else "No team"

func build(stats: MatchStats, heroes: Array, player) -> void:
    for c in get_children():
        remove_child(c)
        c.queue_free()
    add_theme_constant_override("separation", 20)
    alignment = BoxContainer.ALIGNMENT_CENTER
    row_total = 0
    var groups := stats.by_team(heroes)
    var teams := groups.keys()
    teams.sort()
    for t in teams:
        var panel := PanelContainer.new()
        panel.name = "Team%d" % t
        panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.03, 0.05, 0.1, 0.85)
        sb.border_color = HeroBadge.TEAM_COLORS.get(t, Color.WHITE)
        sb.border_width_top = 4
        sb.set_corner_radius_all(10)
        sb.set_content_margin_all(16)
        panel.add_theme_stylebox_override("panel", sb)
        var v := VBoxContainer.new()
        panel.add_child(v)
        var title := MenuStyle.label(team_title(t), 24)
        title.add_theme_color_override("font_color", sb.border_color)
        v.add_child(title)
        var grid := GridContainer.new()
        grid.name = "Grid"
        grid.columns = COLS.size()
        grid.add_theme_constant_override("h_separation", 18)
        grid.add_theme_constant_override("v_separation", 6)
        v.add_child(grid)
        for h in COLS:
            grid.add_child(_cell(h, Color(0.7, 0.8, 1.0), 18))
        for r in groups[t]:
            var me: bool = player != null and r.hero == player
            var col := HIGHLIGHT if me else Color.WHITE
            var badge := HeroBadge.for_hero(r.hero, 44)
            grid.add_child(badge)
            var nm := _cell(r.name, col, 22)
            nm.custom_minimum_size = Vector2(200, ROW_H)
            nm.clip_text = true
            grid.add_child(nm)
            for val in [str(r.kills), str(r.deaths), str(int(round(r.damage))), stats.healing_text(r.healing)]:
                grid.add_child(_cell(val, col, 22))
            row_total += 1
        add_child(panel)

func _cell(t: String, col: Color, fs: int) -> Label:
    var l := Label.new()
    l.text = t
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.custom_minimum_size.y = ROW_H if fs > 18 else 0.0
    l.add_theme_font_size_override("font_size", fs)
    l.add_theme_color_override("font_color", col)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l
