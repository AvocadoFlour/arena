extends "res://tests/test_base.gd"
## Kill feed, score table and capture bars in TeamPalette colours seen from the local player (self blue, ally
## green, enemy red; FFA: everyone but self red), recoloured on team change / local hero swap; client mode guess
## from capture zones (no MatchRules on clients).
var tree: SceneTree

class FakeHero extends Node:
    var display_name := ""
    var team := 0
    var def = null
    func _init(n: String, t: int, d = null) -> void:
        display_name = n
        team = t
        def = d

class FakeRules extends Node:
    var mode := "control"

class HostRoot extends Node:
    var rules: FakeRules = null

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func _host(mode: String) -> HostRoot:
    var r := HostRoot.new()
    r.rules = FakeRules.new()
    r.rules.mode = mode
    r.add_child(r.rules)
    tree.root.add_child(r)
    return r

## Online client root: no MatchRules (rules == null), the map built capture zones iff Control.
func _client(control: bool) -> HostRoot:
    var r := HostRoot.new()
    if control:
        r.add_child(CaptureZone.new())
    tree.root.add_child(r)
    return r

func _heroes() -> Array:
    var me := FakeHero.new("You", 0, _def("cob"))
    var ally := FakeHero.new("Ally 1", 0, _def("twin_tails"))
    var foe := FakeHero.new("Bot 2", 1, _def("the_best"))
    for h in [me, ally, foe]:
        h.add_to_group("heroes")
        tree.root.add_child(h)
    return [me, ally, foe]

func _free(a: Array) -> void:
    for x in a:
        if is_instance_valid(x):
            x.free()

func _feed(root: Node, me) -> KillFeed:
    var kf := KillFeed.new()
    kf.player = me
    root.add_child(kf)
    return kf

func _cols(row: Node) -> Array:
    var k: Label = row.find_child("Killer", true, false)
    var v: Label = row.find_child("Victim", true, false)
    var b: HeroBadge = row.find_child("Ability", true, false)
    return [k.label_settings.font_color, v.label_settings.font_color, b.ring]

func test_palette_values_and_no_team_id_colours_left() -> void:
    check(TeamPalette.SELF == Color("#3ea0ff") and TeamPalette.ALLY == Color("#3ee07a") and TeamPalette.ENEMY == Color("#ff4848"), "self blue / ally green / enemy red")
    for f in ["kill_feed.gd", "score_table.gd", "capture_widget.gd"]:
        var src := FileAccess.get_file_as_string("res://src/ui/" + f)
        check(not src.contains("TEAM_COLORS") and not src.contains("Color(\"#"), f + ": no per-team-id colour table, palette only")
        check(src.contains("TeamPalette."), f + " uses TeamPalette")
    check(ScoreTable.HIGHLIGHT == TeamPalette.SELF, "own score row = self blue")
    check(TeamPalette.team_relation(0, null, "control") == "enemy" and TeamPalette.team_relation(1, FakeHero.new("x", 1), "ffa") == "enemy", "team relation: no player / FFA -> enemy")

func test_kill_feed_control() -> void:
    var root := _host("control")
    var hs := _heroes()
    var me = hs[0]; var ally = hs[1]; var foe = hs[2]
    var kf := _feed(root, me)
    check(kf.feed_mode() == "control", "mode from MatchRules")
    var c := _cols(kf.on_kill({"killer": ally, "victim": foe, "kind": "primary", "ability_id": ""}))
    check(c[0] == TeamPalette.ALLY and c[1] == TeamPalette.ENEMY and c[2] == TeamPalette.ALLY, "ally kills enemy: green / red, green ring %s" % [c])
    c = _cols(kf.on_kill({"killer": foe, "victim": me, "kind": "primary", "ability_id": ""}))
    check(c[0] == TeamPalette.ENEMY and c[1] == TeamPalette.SELF and c[2] == TeamPalette.ENEMY, "enemy kills me: red / blue %s" % [c])
    c = _cols(kf.on_kill({"killer": me, "victim": foe, "kind": "primary", "ability_id": ""}))
    check(c[0] == TeamPalette.SELF and c[2] == TeamPalette.SELF, "my kill: blue name + ring")
    var w: Node = kf.on_kill({"killer": null, "victim": ally, "kind": "fall", "ability_id": ""})
    c = _cols(w)
    check(c[0] == TeamPalette.NEUTRAL and c[1] == TeamPalette.ALLY, "World grey, ally victim green")
    _free([kf, root] + hs)

func test_kill_feed_ffa_everyone_else_red() -> void:
    var root := _host("ffa")
    var hs := _heroes()
    var kf := _feed(root, hs[0])
    var c := _cols(kf.on_kill({"killer": hs[1], "victim": hs[2], "kind": "primary", "ability_id": ""}))
    check(c[0] == TeamPalette.ENEMY and c[1] == TeamPalette.ENEMY, "FFA: same-team-id bot is red too %s" % [c])
    c = _cols(kf.on_kill({"killer": hs[1], "victim": hs[0], "kind": "primary", "ability_id": ""}))
    check(c[1] == TeamPalette.SELF, "FFA: me still blue")
    _free([kf, root] + hs)

func test_kill_feed_recolours_on_team_change_and_hero_swap() -> void:
    var root := _host("control")
    var hs := _heroes()
    var me = hs[0]; var ally = hs[1]; var foe = hs[2]
    var kf := _feed(root, me)
    var r1 := kf.on_kill({"killer": ally, "victim": foe, "kind": "primary", "ability_id": ""})
    me.team = 1   # authoritative team id flips
    kf.recolor()
    var c := _cols(r1)
    check(c[0] == TeamPalette.ENEMY and c[1] == TeamPalette.ALLY and c[2] == TeamPalette.ENEMY, "after my team change: old ally red, old enemy green %s" % [c])
    me.team = 0
    kf.recolor()
    var r2 := kf.on_kill({"killer": me, "victim": foe, "kind": "primary", "ability_id": ""})
    var me2 := FakeHero.new("You", 1, _def("tomo"))   # local hero swap onto the other team: new node, old one gone
    tree.root.add_child(me2)
    me.free()
    kf.player = me2
    kf._process(KillFeed.RECOLOR_EVERY)   # the live timer path
    c = _cols(r2)
    check(c[0] == TeamPalette.SELF and c[1] == TeamPalette.ALLY, "gone hero keeps its colour, foe now ally %s" % [c])
    c = _cols(r1)
    check(c[0] == TeamPalette.ENEMY and c[1] == TeamPalette.ALLY, "older row recoloured too")
    _free([kf, root, me2] + hs)

func test_client_mode_from_capture_zones() -> void:
    var hs := _heroes()
    var croot := _client(true)
    var kf := _feed(croot, hs[0])
    check(kf.feed_mode() == "control", "client with capture zones -> control")
    var c := _cols(kf.on_kill({"killer": hs[1], "victim": hs[2], "kind": "primary", "ability_id": ""}))
    check(c[0] == TeamPalette.ALLY and c[1] == TeamPalette.ENEMY, "client Control: ally green, enemy red")
    var froot := _client(false)
    var kf2 := _feed(froot, hs[0])
    check(kf2.feed_mode() == "ffa", "client without zones -> ffa")
    c = _cols(kf2.on_kill({"killer": hs[1], "victim": hs[2], "kind": "primary", "ability_id": ""}))
    check(c[0] == TeamPalette.ENEMY, "client FFA: red")
    var t := ScoreTable.new()
    froot.add_child(t)
    var s := MatchStats.new()
    t.build(s, hs, hs[0])
    check(t.find_child("Team0", true, false).get_meta("relation_color") == TeamPalette.ENEMY, "score table resolves the client mode itself (FFA)")
    _free([kf, kf2, t, croot, froot] + hs)

func _table(mode: String, hs: Array) -> ScoreTable:
    var t := ScoreTable.new()
    tree.root.add_child(t)
    t.build(MatchStats.new(), hs, hs[0], mode)
    return t

func _row_name(t: ScoreTable, text: String) -> Label:
    for l in t.find_children("*", "Label", true, false):
        if l.text == text:
            return l
    return null

func _row_badge(t: ScoreTable, text: String) -> HeroBadge:
    var l := _row_name(t, text)
    var g := l.get_parent()
    return g.get_child(l.get_index() - 1)

func test_score_table_control_ffa_and_team_change() -> void:
    var hs := _heroes()
    var t := _table("control", hs)
    check(t.find_child("Team0", true, false).get_meta("relation_color") == TeamPalette.ALLY, "own team panel green")
    check(t.find_child("Team1", true, false).get_meta("relation_color") == TeamPalette.ENEMY, "other team panel red")
    check(_row_name(t, "You").get_theme_color("font_color") == TeamPalette.SELF and _row_badge(t, "You").ring == TeamPalette.SELF, "my row blue")
    check(_row_name(t, "Ally 1").get_theme_color("font_color") == TeamPalette.ALLY and _row_badge(t, "Ally 1").ring == TeamPalette.ALLY, "ally name + ring green")
    check(_row_name(t, "Bot 2").get_theme_color("font_color") == TeamPalette.ENEMY and _row_badge(t, "Bot 2").ring == TeamPalette.ENEMY, "enemy name + ring red")
    t.free()
    t = _table("ffa", hs)
    check(t.find_child("Team0", true, false).get_meta("relation_color") == TeamPalette.ENEMY and _row_name(t, "Ally 1").get_theme_color("font_color") == TeamPalette.ENEMY, "FFA: everyone else red")
    check(_row_name(t, "You").get_theme_color("font_color") == TeamPalette.SELF, "FFA: me blue")
    t.free()
    hs[0].team = 1   # team change; the Tab scoreboard rebuilds at 4 Hz
    t = _table("control", hs)
    check(t.find_child("Team1", true, false).get_meta("relation_color") == TeamPalette.ALLY and _row_name(t, "Bot 2").get_theme_color("font_color") == TeamPalette.ALLY, "after team change: Bot 2 is my ally")
    check(_row_name(t, "Ally 1").get_theme_color("font_color") == TeamPalette.ENEMY, "old ally now red")
    t.free()
    var only := FakeHero.new("Solo", 3)
    tree.root.add_child(only)
    var t2 := ScoreTable.new()
    tree.root.add_child(t2)
    t2.build(MatchStats.new(), [only, hs[1]], only, "ffa")
    check(t2.find_child("Team3", true, false).get_meta("relation_color") == TeamPalette.SELF, "FFA: a panel holding only me is blue")
    _free([t2, only] + hs)

func test_scoreboard_passes_mode() -> void:
    var hs := _heroes()
    var sb := Scoreboard.new()
    sb.stats = MatchStats.new()
    sb.player = hs[0]
    sb.mode = "ffa"
    tree.root.add_child(sb)
    sb.refresh()
    check(_row_name(sb.table, "Ally 1").get_theme_color("font_color") == TeamPalette.ENEMY, "scoreboard FFA")
    sb.mode = "control"
    sb.refresh()
    check(_row_name(sb.table, "Ally 1").get_theme_color("font_color") == TeamPalette.ALLY, "scoreboard Control")
    _free([sb] + hs)

func _fill(w: CaptureWidget, id: String) -> Color:
    var bar: ProgressBar = w.find_child("bar_" + id, true, false)
    return (bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color

func test_capture_widget_relation_and_recolour() -> void:
    var hs := _heroes()
    var w := CaptureWidget.new()
    w.player = hs[0]
    tree.root.add_child(w)
    w.on_progress({"zone_id": "A", "team": 0, "progress": 0.5, "contested": false})
    w.on_progress({"zone_id": "B", "team": 1, "progress": 0.3, "contested": false})
    w.on_progress({"zone_id": "C", "team": -1, "progress": 0.0, "contested": false})
    w.on_progress({"zone_id": "D", "team": 1, "progress": 0.2, "contested": true})
    check(_fill(w, "A") == TeamPalette.ALLY and _fill(w, "B") == TeamPalette.ENEMY, "own team green, other red")
    check(_fill(w, "C") == CaptureWidget.NEUTRAL and _fill(w, "D") == CaptureWidget.CONTESTED, "neutral grey, contested yellow")
    w._process(0.0)
    hs[0].team = 1
    w._process(0.0)
    check(_fill(w, "A") == TeamPalette.ENEMY and _fill(w, "B") == TeamPalette.ALLY, "team change recolours at once")
    var me2 := FakeHero.new("You", 0)
    tree.root.add_child(me2)
    w.player = me2
    w._process(0.0)
    check(_fill(w, "A") == TeamPalette.ALLY and _fill(w, "B") == TeamPalette.ENEMY, "local hero swap recolours")
    _free([w, me2] + hs)

func test_hud_keeps_widgets_on_the_local_player() -> void:
    var src := FileAccess.get_file_as_string("res://src/ui/hud.gd")
    for s in ["kill_feed.player = player", "kill_feed.mode = bar_mode()", "scoreboard.player = player", "scoreboard.mode = kill_feed.mode", "capture_widget.player = player"]:
        check(src.contains(s), "HUD follows swaps: " + s)
