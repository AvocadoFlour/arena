extends "res://tests/test_base.gd"
## Priority: Esc overlay Match page (bot steppers, hero switch with countdown, team switch),
## host-decides online behaviour, "not available yet" without hooks. Mocks only.
var tree: SceneTree

class MockNet extends RefCounted:
    var mode := "offline"
    func is_online() -> bool: return mode != "offline"
    func is_client() -> bool: return mode == "client"

class MockRoot extends Node:
    signal hero_swap_started(net_id: int, hero_id: String, delay: float)
    signal hero_swap_finished(net_id: int, hero_id: String)
    signal hero_swap_cancelled(net_id: int, reason: String)
    signal bot_counts_changed(counts: Dictionary)
    signal team_changed(net_id: int, team: int)
    var counts := {0: 2, 1: 3}
    var team := 0
    var hero_reqs: Array = []
    var team_reqs: Array = []
    func match_bot_counts() -> Dictionary: return counts.duplicate()
    func set_bot_count(t: int, n: int) -> bool:
        counts[t] = n
        bot_counts_changed.emit(counts)
        return true
    func request_hero_change(id: String) -> bool:
        hero_reqs.append(id)
        return true
    func request_team_change(t: int) -> bool:
        team_reqs.append(t)
        return true
    func local_team() -> int: return team
    func local_net_id() -> int: return 7

func _menu(root: Object, net: MockNet) -> PauseMenu:
    var m := PauseMenu.new()
    tree.root.add_child(m)
    m.set_control(MatchControl.new(root, net))
    return m

func _btn(m: PauseMenu, n: String) -> Button:
    return m.match_page.find_child(n, true, false)

func test_match_page_opens_and_is_touch_sized() -> void:
    var r := MockRoot.new()
    var m := _menu(r, MockNet.new())
    var b: Button = m.panel.find_child("Match", true, false)
    check(b != null and b.custom_minimum_size.y >= 64, "Match button")
    m.open()
    b.pressed.emit()
    check(m.match_open() and not m.panel.visible, "page shown")
    for n in ["Minus", "Plus", "Team0", "Team1", "Back"]:
        var x := _btn(m, n)
        check(x != null and x.custom_minimum_size.y >= 64 and x.custom_minimum_size.x >= 64, "touch " + n)
    check(m.match_page.hero_btns.size() == UiCatalog.list_heroes().size() and m.match_page.hero_btns.size() > 0, "hero list from UiCatalog")
    check(m.handle_escape() and not m.match_open() and m.panel.visible and m.visible, "Esc backs out of page")
    m.close()
    m.free()
    r.free()

func test_bot_steppers_offline_live_and_clamped() -> void:
    var r := MockRoot.new()
    var m := _menu(r, MockNet.new())
    m.open_match()
    var row: Node = m.match_page.find_child("BotsTeam1", true, false)
    var plus: Button = row.find_child("Plus", true, false)
    plus.pressed.emit()
    plus.pressed.emit()
    check(r.counts[1] == 5 and row.find_child("Value", true, false).text == "5", "live to 5")
    check(plus.disabled, "plus disabled at 5")
    var minus: Button = m.match_page.find_child("BotsTeam0", true, false).find_child("Minus", true, false)
    minus.pressed.emit(); minus.pressed.emit()
    check(r.counts[0] == 0 and minus.disabled, "down to 0, minus disabled")
    check(not m.match_ctl.set_bot_count(0, 9) or r.counts[0] == 5, "clamped to 5")
    m.close(); m.free(); r.free()

func test_client_bots_disabled_requests_sent() -> void:
    var r := MockRoot.new()
    var n := MockNet.new()
    n.mode = "client"
    var m := _menu(r, n)
    m.open_match()
    check(_btn(m, "Plus").disabled and _btn(m, "Minus").disabled, "client: steppers disabled")
    check(m.match_page.bot_note.text.contains("host"), "client note")
    check(not m.match_ctl.set_bot_count(1, 1) and r.counts[1] == 3, "client cannot set bots")
    var hb: Button = m.match_page.hero_btns[0]
    hb.pressed.emit()
    check(r.hero_reqs == [hb.get_meta("hero_id")] and m.match_page.hero_note.text.contains("host"), "hero request to host")
    check(_btn(m, "Team0").disabled and not _btn(m, "Team1").disabled, "current team disabled")
    _btn(m, "Team1").pressed.emit()
    check(r.team_reqs == [1], "team request")
    n.mode = "host"
    m.match_page.refresh()
    check(not _btn(m, "Plus").disabled and m.match_page.bot_note.text == "", "host may change bots")
    m.close(); m.free(); r.free()

func test_swap_countdown_visible_and_filtered() -> void:
    var r := MockRoot.new()
    var m := _menu(r, MockNet.new())
    var p := m.match_page
    var id: String = p.hero_btns[0].get_meta("hero_id")
    r.hero_swap_started.emit(3, id, 3.0)
    check(not p.countdown.visible, "other player's swap ignored")
    r.hero_swap_started.emit(7, id, 3.0)
    check(p.countdown.visible and p.countdown.text.ends_with("3") and p.countdown.text.contains(p.hero_btns[0].text), "countdown shown")
    check(p.hero_btns[0].disabled, "no double swap")
    p._process(1.2)
    check(p.countdown.text.ends_with("2"), "counts down")
    check(m.swap_layer != null and p.countdown.get_parent() == m.swap_layer, "countdown on its own layer")
    m.close()
    check(not m.visible and m.swap_layer.visible and p.countdown.is_visible_in_tree(), "countdown stays after overlay closes")
    r.hero_swap_finished.emit(7, id)
    check(not p.countdown.visible and not p.hero_btns[0].disabled, "done")
    r.hero_swap_started.emit(7, id, 3.0)
    r.hero_swap_cancelled.emit(7, "dead")
    check(not p.countdown.visible and p.hero_note.text.contains("dead"), "cancel")
    m.free(); r.free()

func test_missing_hooks_not_available() -> void:
    var r := Node.new()
    var m := _menu(r, MockNet.new())
    m.open_match()
    var p := m.match_page
    check(p.bot_note.text == MatchPage.NA and p.hero_note.text == MatchPage.NA and p.team_note.text == MatchPage.NA, "notes")
    check(_btn(m, "Plus").disabled and p.hero_btns[0].disabled and _btn(m, "Team0").disabled, "disabled")
    check(not m.match_ctl.request_hero("x") and not m.match_ctl.request_team(1) and m.match_ctl.bot_counts().is_empty(), "adapter no-ops")
    m.close(); m.free(); r.free()
    var dflt := PauseMenu.new()   # no parent hooks: default adapter must not error
    tree.root.add_child(dflt)
    check(dflt.match_ctl != null and not dflt.match_ctl.hero_available(), "default adapter")
    dflt.free()
