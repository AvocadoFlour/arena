extends "res://tests/test_base.gd"
## UI queue 2: team scoreboard with hero badges, healing column, match-end summary.
var tree: SceneTree

class FakeHero extends Node:
    var display_name := ""
    var team := 0
    var def = null
    func _init(n: String, t: int, d = null) -> void:
        display_name = n
        team = t
        def = d

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func _setup() -> Array:
    var me := FakeHero.new("You (Cob)", 0, _def("cob"))
    var ally := FakeHero.new("Bot 1 (Twin Tails)", 0, _def("twin_tails"))
    var foe := FakeHero.new("Bot 2 (The Best)", 1, _def("the_best"))
    for h in [me, ally, foe]:
        h.add_to_group("heroes")
        tree.root.add_child(h)
    var s := MatchStats.new()
    s.on_damage({"source": me, "target": foe, "amount": 150.0})
    s.on_damage({"source": foe, "target": ally, "amount": 400.0})
    s.on_kill({"killer": me, "victim": foe, "kind": "primary"})
    s.on_kill({"killer": me, "victim": foe, "kind": "primary"})
    s.on_kill({"killer": foe, "victim": ally, "kind": "primary"})
    return [s, me, ally, foe]

func _free(a: Array) -> void:
    for x in a:
        if is_instance_valid(x):
            x.free()

func test_badge_initials_and_colour() -> void:
    check(HeroBadge.initials_for("Twin Tails") == "TT", "two words")
    check(HeroBadge.initials_for("The Best") == "TB", "the best")
    check(HeroBadge.initials_for("Cob") == "CO", "one word -> 2 letters")
    check(HeroBadge.initials_for("") == "?", "empty")
    var cob := _def("cob")
    check(HeroBadge.color_for_def(cob) == Color("#6b6355"), "first hex model colour")
    check(HeroBadge.color_for_def({"model": [{"color": "team"}]}) == Color(0.4, 0.4, 0.45), "team-only -> grey")
    var h := FakeHero.new("Bot 1 (Cob)", 1, cob)
    var b := HeroBadge.for_hero(h)
    check(b.initials == "CO" and b.ring == TeamPalette.ENEMY, "uses def name + relation ring (no local player: enemy)")
    check(b.custom_minimum_size.x >= 44, "badge size")
    b.free()
    h.free()

func test_healing_untracked_shows_dash() -> void:
    var s := MatchStats.new()
    check(not s.healing_tracked and s.healing_text(0.0) == "-", "dash without heal event")
    var bus := Node.new()
    bus.add_user_signal("damage_dealt")
    bus.add_user_signal("killed")
    bus.add_user_signal("healed")
    s.bind(bus)
    check(s.healing_tracked, "auto-binds future healed signal")
    var h := FakeHero.new("x", 0)
    bus.emit_signal("healed", {"source": h, "target": h, "amount": 33.4})
    check(s.healing_text(s.rows[h].healing) == "33", "healing tallied")
    var plain := MatchStats.new()
    plain.bind(Events)
    check(plain.healing_tracked == Events.has_signal("healed"), "matches Events")
    _free([s, plain, bus, h])

func test_team_columns_scoreboard() -> void:
    var r := _setup()
    var sb := Scoreboard.new()
    sb.stats = r[0]
    sb.player = r[1]
    tree.root.add_child(sb)
    sb.held_override = 1
    sb._process(0.0)
    check(sb.visible and sb.row_count() == 3, "3 rows")
    var t0 = sb.table.find_child("Team0", true, false)
    var t1 = sb.table.find_child("Team1", true, false)
    check(t0 != null and t1 != null, "one column per team")
    var g0: GridContainer = t0.find_child("Grid", true, false)
    check(g0.columns == ScoreTable.COLS.size() and g0.get_child_count() == ScoreTable.COLS.size() * 3, "team 0: header + 2 rows")
    check(g0.get_child(ScoreTable.COLS.size()) is HeroBadge, "row starts with badge")
    var texts: Array = g0.get_children().filter(func(c): return c is Label).map(func(c): return c.text)
    check(texts.has("You (Cob)") and texts.has("150") and texts.has("-"), "name, damage, healing dash: %s" % [texts])
    var me_label: Label = g0.get_children().filter(func(c): return c is Label and c.text == "You (Cob)")[0]
    check(me_label.get_theme_color("font_color") == ScoreTable.HIGHLIGHT, "player highlighted")
    check(me_label.custom_minimum_size.y >= 48, "touch-height rows")
    sb.held_override = 0
    sb._process(0.0)
    check(not sb.visible, "hidden on release")
    sb.free()
    _free(r)

func test_highlights_and_totals() -> void:
    var r := _setup()
    var s: MatchStats = r[0]
    var hl := s.highlights([r[1], r[2], r[3]])
    var labels: Array = hl.map(func(x): return x.label)
    check(labels == ["Most kills", "Top damage"], "no healing highlight while untracked: %s" % [labels])
    check(hl[0].name == "You (Cob)" and hl[0].value == 2, "most kills")
    check(hl[1].name == "Bot 2 (The Best)" and hl[1].value == 400, "top damage")
    s.healing_tracked = true
    s.on_heal({"source": r[2], "target": r[1], "amount": 90.0})
    check(s.highlights([r[1], r[2], r[3]]).back().label == "Top healing", "top healing when tracked")
    var tt := s.team_totals([r[1], r[2], r[3]])
    check(tt[0].kills == 2 and int(tt[0].damage) == 150 and tt[1].kills == 1, "team totals")
    _free(r)

func test_match_end_summary() -> void:
    var r := _setup()
    var me := MatchEndScreen.new()
    tree.root.add_child(me)
    me.show_results({"winner_team": 0, "reason": "score"}, r[0], r[1])
    check(me.banner.text == "VICTORY", "banner")
    check(me.highlights_row.get_child_count() == 2, "2 highlight cards")
    for c in me.highlights_row.get_children():
        check(c.custom_minimum_size.y >= 96, "card touch size")
        check(c.find_children("*", "HeroBadge", true, false).size() == 1, "card badge")
    check(me.table.row_total == 3, "full team table")
    check(me.totals_l.text.contains("Team 1: 2 kills, 150 damage"), "totals: " + me.totals_l.text)
    for b in me.find_children("*", "Button", true, false):
        check(b.custom_minimum_size.y >= 64, "button touch size")
    me.show_results({"winner_team": 1, "reason": "score"}, r[0], r[1])
    check(me.highlights_row.get_child_count() == 2, "re-show doesn't duplicate")
    me.free()
    _free(r)
