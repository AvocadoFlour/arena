extends "res://tests/test_base.gd"
## UI round 2: live key labels, scoreboard, match-end screen, capture widget (mock source).
var tree: SceneTree

class FakeHero extends Node:
    var display_name := ""
    var team := 0
    func _init(n: String, t: int) -> void:
        display_name = n
        team = t

func test_hud_key_labels_follow_rebind() -> void:
    Keybinds.reset_defaults()
    check(Hud.key_label("ability1") == "SHIFT", "default shift (%s)" % Hud.key_label("ability1"))
    var ev := InputEventKey.new()
    ev.physical_keycode = KEY_C
    Keybinds.rebind("ability1", ev)
    check(Hud.key_label("ability1") == "C", "live label C")
    Keybinds.reset_defaults()

func test_scoreboard_action_registered_and_rebindable() -> void:
    Keybinds.ensure_ui_actions()
    check(InputMap.has_action("scoreboard"), "scoreboard action")
    check(Keybinds.actions().has("scoreboard"), "listed on keybind screen")
    check(Keybinds.binding_text("scoreboard") == "Tab", "default Tab (%s)" % Keybinds.binding_text("scoreboard"))
    var ev := InputEventKey.new()
    ev.physical_keycode = KEY_CAPSLOCK
    Keybinds.rebind("scoreboard", ev)
    check(Keybinds.binding_text("scoreboard") != "Tab", "rebound")
    Keybinds.reset_defaults()
    check(Keybinds.binding_text("scoreboard") == "Tab", "reset restores Tab")

func _stats_with_heroes() -> Array:
    var a := FakeHero.new("You", 0)
    var b := FakeHero.new("Bot 1", 1)
    var c := FakeHero.new("Bot 2", 1)
    for h in [a, b, c]:
        h.add_to_group("heroes")
        tree.root.add_child(h)
    var s := MatchStats.new()
    s.on_damage({"source": a, "target": b, "amount": 120.0})
    s.on_kill({"killer": a, "victim": b, "kind": "primary"})
    s.on_kill({"killer": c, "victim": a, "kind": "primary"})
    s.on_kill({"killer": null, "victim": c, "kind": "fall"})
    s.on_kill({"killer": a, "victim": c, "kind": "primary"})
    return [s, a, b, c]

func _free(arr: Array) -> void:
    for x in arr:
        if is_instance_valid(x):
            x.free()

func test_match_stats_tally_and_sort() -> void:
    var r := _stats_with_heroes()
    var s: MatchStats = r[0]
    check(s.rows[r[1]].kills == 2 and s.rows[r[1]].deaths == 1, "player 2/1")
    near(s.rows[r[1]].damage, 120.0, 0.01, "damage")
    check(s.rows[r[3]].deaths == 2 and s.rows[r[3]].kills == 1, "world kill not credited")
    var rows := s.sorted_rows([r[2], r[3], r[1]])
    check(rows[0].name == "You", "top by kills")
    _free(r)

func test_scoreboard_shows_only_while_held() -> void:
    var r := _stats_with_heroes()
    var sb := Scoreboard.new()
    sb.stats = r[0]
    sb.player = r[1]
    tree.root.add_child(sb)
    sb.held_override = 0
    sb._process(0.0)
    check(not sb.visible, "hidden when released")
    sb.held_override = 1
    sb._process(0.0)
    check(sb.visible, "shown while held")
    check(sb.row_count() == 3, "one row per hero (%d)" % sb.row_count())
    sb.held_override = 0
    sb._process(0.0)
    check(not sb.visible, "hides on release")
    sb.free()
    _free(r)

func test_match_end_screen() -> void:
    check(MatchEndScreen.outcome_for(0, 0) == "VICTORY", "win")
    check(MatchEndScreen.outcome_for(1, 0) == "DEFEAT", "loss")
    check(MatchEndScreen.outcome_for(-1, 0) == "DRAW", "draw")
    var r := _stats_with_heroes()
    var me := MatchEndScreen.new()
    tree.root.add_child(me)
    check(not me.visible, "hidden at start")
    var got := []
    me.play_again.connect(func(): got.append("again"))
    me.show_results({"winner_team": 1, "reason": "Score limit"}, r[0], r[1])
    check(me.visible and me.banner.text == "DEFEAT", "shows defeat")
    check(me.board.get_child_count() == 3, "final scoreboard rows")
    var btns: Array = me.find_children("*", "Button", true, false)
    check(btns.size() == 3, "3 buttons")
    for b in btns:
        check(b.custom_minimum_size.y >= 64, "touch size " + b.text)
    btns[0].pressed.emit()
    check(got == ["again"], "play again signal")
    me.free()
    _free(r)

func test_capture_widget_with_mock_source() -> void:
    var w := CaptureWidget.new()
    tree.root.add_child(w)
    var plain := Node.new()
    check(not w.bind(plain), "rejects source without signals")
    plain.free()
    check(not w.visible, "hidden without data")
    var src := MockCaptureSource.new()
    check(w.bind(src), "binds mock")
    src.step(1.0)
    check(w.visible, "visible after progress")
    near(w.zones["A"].progress, 0.25, 0.001, "progress 25%")
    var bar: ProgressBar = w.find_child("bar_A", true, false)
    check(bar != null and absf(bar.value - 0.25) < 0.001, "bar reflects progress")
    src.contested = true
    src.step(1.0)
    check(w.zones["A"].contested and absf(w.zones["A"].progress - 0.25) < 0.001, "contested pauses")
    src.contested = false
    for i in 4:
        src.step(1.0)
    check(w.zones["A"].owner == 0 and w.zones["A"].progress == 1.0, "captured by team 0")
    w.free()
    src.free()

func test_hud_binds_capture_to_events_only_if_present() -> void:
    var w := CaptureWidget.new()
    var has := Events.has_signal("capture_progress") and Events.has_signal("capture_completed")
    check(w.bind(Events) == has, "bind(Events) matches signal availability")
    w.free()
