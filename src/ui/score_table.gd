class_name ScoreTable
extends HBoxContainer
## Team-column score table shared by the Tab scoreboard and the match-end summary.
## One panel per team; each row: badge (hero initials), player name, K, D, damage, healing.
## Rows are >= 52 px tall (touch-friendly); the local player's row is highlighted.
## Colours come from TeamPalette, seen from the local player: own row self blue, the own team's panel ally green,
## other teams' panels red; other players' names + badge rings ally green / enemy red (FFA: everyone but self red).
## Rebuilt on every refresh (Tab scoreboard 4 Hz), so a team change or hero swap recolours at once.
const COLS := ["", "Player", "K", "D", "Damage", "Healing"]
const ROW_H := 52.0
const HIGHLIGHT := TeamPalette.SELF   ## the local player's own row
var row_total := 0

static func team_title(team: int) -> String:
    return "Team %d" % (team + 1) if team >= 0 else "No team"

## Panel colour of team `t` (rows = its MatchStats rows): ally/enemy by TeamPalette.team_relation; in FFA a
## panel holding only the local player is self blue.
static func panel_color(t: int, rows: Array, player, mode: String) -> Color:
    if player != null and is_instance_valid(player) and not rows.is_empty() and rows.all(func(r): return r.hero == player):
        return TeamPalette.SELF if mode == "ffa" else TeamPalette.ALLY
    return TeamPalette.color(TeamPalette.team_relation(t, player, mode))

## `mode` "" = resolve from the composition root (TeamPalette.mode_near).
func build(stats: MatchStats, heroes: Array, player, mode := "") -> void:
    if mode == "":
        mode = TeamPalette.mode_near(self)
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
        sb.border_color = panel_color(t, groups[t], player, mode)
        panel.set_meta("relation_color", sb.border_color)
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
            var rel_col := TeamPalette.color(TeamPalette.relation(r.hero, player, mode))
            var badge := HeroBadge.for_hero(r.hero, 44, player, mode)
            grid.add_child(badge)
            var nm := _cell(r.name, HIGHLIGHT if me else rel_col, 22)
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
