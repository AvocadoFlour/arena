extends "res://tests/test_base.gd"
## Match-end screen on real viewport sizes (the Windows bug: award-card text 1 px wide, buttons off screen, no way out),
## (layout at real sizes: tests/ui_match_end_sim.gd, which needs frames) buttons per session kind (offline / host / client), Esc, cursor freed, gameplay HUD hidden.
var tree: SceneTree
const R8 := "res://tests/ui_round8_test.gd"

class MockNet extends RefCounted:
    var mode := "offline"
    func is_online() -> bool: return mode != "offline"
    func is_host() -> bool: return mode == "host"
    func is_client() -> bool: return mode == "client"

class MockRoot extends Node:
    var calls := 0
    func rematch() -> void: calls += 1

class PlainRoot extends Node:
    pass

## A full lobby: 3v3 (control) or me vs 5 bots (ffa), healing tracked so all 3 award cards show.
func _lobby(mode: String) -> Array:
    var F = load(R8).FakeHero
    var ids := ["cob", "nidjo", "the_best", "tomo", "twin_tails"]
    var hs := []
    var me = F.new("You (The Best)", 0, _def("the_best"))
    hs.append(me)
    for i in 5:
        var team := (0 if i < 2 else 1) if mode == "control" else 1
        var label: String = "Ally %d (%s)" if team == 0 else "Bot %d (%s)"
        hs.append(F.new(label % [i + 1, ids[i].capitalize()], team, _def(ids[i])))
    for h in hs:
        h.add_to_group("heroes")
        tree.root.add_child(h)
    var s := MatchStats.new()
    s.healing_tracked = true
    s.on_damage({"source": hs[3], "target": me, "amount": 812.0})
    s.on_kill({"killer": hs[3], "victim": me, "kind": "primary"})
    s.on_kill({"killer": hs[1], "victim": hs[4], "kind": "primary"})
    s.on_heal({"source": hs[5], "target": hs[4], "amount": 640.0})
    s.on_damage({"source": me, "target": hs[4], "amount": 300.0})
    return [s, me, hs]

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func _free(l: Array) -> void:
    for h in l[2]:
        h.free()
    l[0].free()

## End screen inside a SubViewport of `size`; `base` set = the game's stretch (canvas_items) at that window size.
func _screen_in(size: Vector2i, base := Vector2i.ZERO) -> Array:
    var vp := SubViewport.new()
    vp.size = size
    if base != Vector2i.ZERO:
        vp.size_2d_override = base
        vp.size_2d_override_stretch = true
    tree.root.add_child(vp)
    var me := MatchEndScreen.new()
    me.quit_fn = func(): pass
    vp.add_child(me)
    return [vp, me]

func _inside(r: Rect2, area: Rect2) -> bool:
    return area.grow(0.5).encloses(r)

func _check_fits(me: MatchEndScreen, area: Rect2, what: String) -> void:
    check(me.highlights_row.get_child_count() == 3, what + ": 3 award cards")
    for card in me.highlights_row.get_children():
        check(card.size.x >= MatchEndScreen.CARD_MIN.x, "%s: card width %s" % [what, card.size.x])
        for l in card.find_children("*", "Label", true, false):
            var line: int = l.get_line_height()
            check(l.size.x >= 100.0, "%s: card label '%s' width %s" % [what, l.text, l.size.x])
            check(l.get_line_count() <= 2 and l.size.y <= line * 2 + 4, "%s: '%s' not one char per line (%d lines)" % [what, l.text, l.get_line_count()])
        check(_inside(card.get_global_rect(), Rect2(Vector2.ZERO, Vector2(area.size.x, me.board.size.y + area.size.y))), what + ": card within width")
        check(card.get_global_rect().position.x >= 0 and card.get_global_rect().end.x <= area.size.x + 0.5, "%s: card x inside %s" % [what, card.get_global_rect()])
    check(_inside(me.banner.get_global_rect(), area), "%s: banner inside %s" % [what, me.banner.get_global_rect()])
    check(_inside(me.scroll.get_global_rect(), area), what + ": summary area inside")
    check(me.buttons.size() >= 2, what + ": buttons")
    for k in me.buttons:
        var b: Button = me.buttons[k]
        check(b.visible and _inside(b.get_global_rect(), area), "%s: button %s inside (%s)" % [what, b.text, b.get_global_rect()])
    for l in me.table.find_children("*", "Label", true, false):
        if l.text != "":
            check(l.size.x >= 8.0, "%s: table label '%s' width %s" % [what, l.text, l.size.x])

func test_buttons_per_session_kind_and_esc() -> void:
    var net := MockNet.new()
    var root := MockRoot.new()
    var plain := PlainRoot.new()
    tree.root.add_child(root)
    tree.root.add_child(plain)
    var me := MatchEndScreen.new()
    var quits := []
    me.quit_fn = func(): quits.append(1)
    tree.root.add_child(me)
    var got := []
    me.play_again.connect(func(): got.append("again"))
    me.main_menu.connect(func(): got.append("menu"))
    me.set_control(RematchControl.new(plain, net))
    me.show_results({"winner_team": 1, "reason": "forced"})
    check(me.buttons.keys() == ["play_again", "main_menu", "quit"], "offline: " + str(me.buttons.keys()))
    check(me.buttons.play_again.text == "Play again" and me.buttons.main_menu.text == "Main menu" and me.buttons.quit.text == "Quit to desktop", "labels")
    for k in me.buttons:
        check(me.buttons[k].custom_minimum_size.y >= 64 and me.buttons[k].custom_minimum_size.x >= 200, "touch size " + k)
    me.buttons.play_again.pressed.emit()
    me.buttons.main_menu.pressed.emit()
    me.buttons.quit.pressed.emit()
    check(got == ["again", "menu"] and quits.size() == 1, "offline signals + quit: %s" % [got])
    check(me.reason_l.text == "Match over" and MatchEndScreen.reason_text("score") == "Target score reached", "plain reason, not 'score'")
    got.clear()
    var esc := InputEventKey.new()
    esc.physical_keycode = KEY_ESCAPE
    esc.pressed = true
    me._input(esc)
    check(got == ["menu"], "Esc = Main menu")
    net.mode = "host"
    me.show_results({"winner_team": 0, "reason": "score"})
    check(me.buttons.keys() == ["rematch", "main_menu", "quit"] and me.buttons.rematch.disabled and me.note_l.text != "", "host without hook: Rematch disabled + note")
    me.set_control(RematchControl.new(root, net))
    me.show_results({"winner_team": 0, "reason": "score"})
    check(not me.buttons.rematch.disabled and me.note_l.text == "", "host with hook: Rematch enabled")
    me.buttons.rematch.pressed.emit()
    check(root.calls == 1, "Rematch calls the core hook (everyone)")
    net.mode = "client"
    got.clear()
    me.show_results({"winner_team": 1, "reason": "score"})
    check(me.buttons.keys() == ["leave", "quit"] and me.buttons.leave.text == "Leave", "client: Leave: " + str(me.buttons.keys()))
    check(me.note_l.text.contains("host"), "client waits for the host when rematch exists")
    me.buttons.leave.pressed.emit()
    me._input(esc)
    check(got == ["menu", "menu"], "Leave / Esc -> main_menu (main.gd closes Net)")
    check(not RematchControl.new(root, net).start(), "client can't start a rematch")
    check(root.calls == 1, "no extra call")
    me.free(); root.free(); plain.free()

func test_mouse_freed_and_kept_free() -> void:
    var me := MatchEndScreen.new()
    tree.root.add_child(me)
    me.set_control(RematchControl.new(null, MockNet.new()))
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    me.show_results({"winner_team": 1, "reason": "score"})
    check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "cursor visible on match end (%d)" % Input.mouse_mode)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # e.g. main.gd click-to-capture
    me._process(0.016)
    check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "re-freed while shown")
    var bg: ColorRect = me.get_node("Background")
    check(bg.mouse_filter == Control.MOUSE_FILTER_STOP, "background eats clicks (no click-through recapture)")
    check(me.process_mode == Node.PROCESS_MODE_ALWAYS, "works in the paused tree")
    me.free()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func test_hud_hidden_behind_end_screen() -> void:
    var hud := Hud.new()
    tree.root.add_child(hud)
    var name_l := Label.new()
    hud.add_child(name_l)
    var layer := CanvasLayer.new()
    hud.add_child(layer)
    hud.conn_lost = ConnectionLostScreen.new()
    hud.add_child(hud.conn_lost)
    hud.match_end = MatchEndScreen.new()
    hud.add_child(hud.match_end)
    hud.match_end.set_control(RematchControl.new(null, MockNet.new()))
    var foe = load(R8).FakeHero.new("Bot 1 (Cob)", 1, _def("cob"))
    var bar := Node3D.new()
    tree.root.add_child(bar)
    hud._bars[foe] = bar
    hud.match_end.show_results({"winner_team": 1, "reason": "score"})
    check(hud.gameplay_hidden and not name_l.visible and not layer.visible, "gameplay HUD hidden")
    check(name_l.process_mode == Node.PROCESS_MODE_DISABLED, "and stopped (Tab scoreboard etc. can't re-show)")
    check(not bar.visible, "3D health bars / name tags hidden")
    check(hud.match_end.visible, "end screen shown")
    check(hud.conn_lost.process_mode != Node.PROCESS_MODE_DISABLED, "connection-lost screen untouched")
    hud.set_gameplay_visible(true)
    check(name_l.visible and name_l.process_mode != Node.PROCESS_MODE_DISABLED and not hud.gameplay_hidden, "restorable")
    hud.free(); bar.free(); foe.free()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func test_card_text_column_cannot_collapse() -> void:
    var me := MatchEndScreen.new()
    tree.root.add_child(me)
    var card := me._highlight_card({"label": "Top damage", "name": "Bot 3 (Twin Tails)", "value": 812, "hero": null})
    var v: VBoxContainer = card.get_child(0).get_child(1)
    check(v.size_flags_horizontal & Control.SIZE_EXPAND and v.custom_minimum_size.x >= 150, "text column expands with a real min width")
    var labels: Array = v.get_children()
    check(labels[0].autowrap_mode == TextServer.AUTOWRAP_OFF and labels[2].autowrap_mode == TextServer.AUTOWRAP_OFF, "title / value never wrap")
    check(card.get_combined_minimum_size().x >= MatchEndScreen.CARD_MIN.x, "card min width")
    card.free()
    me.free()
