extends "res://tests/test_base.gd"
## Miku queue 2: ping indicator (online only, thresholds, stall warning, placeholder) and
## connection-lost screen (title/reason, touch-size Return, documented return routes). Mocks only.
var tree: SceneTree

class MockNet extends Node:
    signal disconnected(reason: String)
    var online := true
    func is_online() -> bool: return online
    func is_client() -> bool: return online

class MockNetPing extends MockNet:
    var ping := 40
    var age := 0.05
    func ping_ms() -> int: return ping
    func last_packet_age() -> float: return age

func test_classify_thresholds() -> void:
    check(PingIndicator.classify(30, 0.0) == "good", "good")
    check(PingIndicator.classify(90, 0.0) == "ok", "ok")
    check(PingIndicator.classify(200, 0.0) == "bad", "bad")
    check(PingIndicator.classify(30, 1.0) == "stalled", "stall wins")
    check(PingIndicator.classify(-1, -1.0) == "unknown", "unknown")
    check(PingIndicator.text_for("unknown", -1) == "Ping --" and PingIndicator.text_for("good", 42) == "Ping 42 ms", "texts")
    check(PingIndicator.color_for("bad") == PingIndicator.COL_BAD and PingIndicator.color_for("stalled") == PingIndicator.COL_WARN, "colours")

func test_indicator_visibility_and_states() -> void:
    var n := MockNetPing.new()
    var pi := PingIndicator.new()
    pi.info = NetLinkInfo.new(n)
    n.online = false
    tree.root.add_child(pi)
    check(not pi.visible and pi.state == "hidden", "hidden offline")
    n.online = true
    pi.refresh()
    check(pi.visible and pi.state == "good" and pi.label.text == "Ping 40 ms", "online good")
    n.ping = 150
    pi.refresh()
    check(pi.state == "bad" and pi.dot.color == PingIndicator.COL_BAD, "bad red")
    n.age = 2.0
    pi.refresh()
    check(pi.state == "stalled" and pi.label.text == "Connection unstable", "stall warning")
    pi.free(); n.free()

func test_placeholder_when_net_has_no_ping() -> void:
    var n := MockNet.new()
    var pi := PingIndicator.new()
    pi.info = NetLinkInfo.new(n)
    tree.root.add_child(pi)
    check(pi.visible and pi.state == "unknown" and pi.label.text == "Ping --", "placeholder")
    pi.free(); n.free()
    var real := NetLinkInfo.new()
    check(real.ping_ms() == (int(Net.ping_ms()) if Net.has_method("ping_ms") else -1), "real Net: placeholder until ping_ms exists")
    check(real.online() == Net.is_online(), "real Net online query")

func test_connection_lost_screen() -> void:
    check(ConnectionLostScreen.title_for("host closed the connection") == "Host left", "host left")
    check(ConnectionLostScreen.title_for("could not connect") == "Connection lost", "lost")
    var s := ConnectionLostScreen.new()
    tree.root.add_child(s)
    check(not s.visible, "hidden initially")
    s.show_lost("host closed the connection")
    check(s.visible and s.title.text == "Host left" and s.reason_l.text != "", "shown with reason: " + s.reason_l.text)
    check(not Actions.gameplay_enabled, "input blocked")
    check(s.return_btn.text == "Return to menu" and s.return_btn.custom_minimum_size.y >= 96, "big touch button")
    var got := []
    s.return_requested.connect(func(): got.append("direct"))
    s.return_btn.pressed.emit()
    check(got == ["direct"], "return_requested")
    s.free()
    Actions.gameplay_enabled = true

func test_return_routes_documented() -> void:
    var s := ConnectionLostScreen.new()
    tree.root.add_child(s)
    var pm := PauseMenu.new()
    tree.root.add_child(pm)
    var me := MatchEndScreen.new()
    tree.root.add_child(me)
    var got := []
    pm.leave_requested.connect(func(): got.append("leave"))
    me.main_menu.connect(func(): got.append("menu"))
    s.routes = [pm.leave_requested, me.main_menu]
    s.go_back()
    check(got == ["leave"], "prefers pause overlay leave_requested")
    s.routes = [me.main_menu]
    s.go_back()
    check(got == ["leave", "menu"], "falls back to match_end.main_menu")
    s.free(); pm.free(); me.free()
    Actions.gameplay_enabled = true

func test_hud_hooks_disconnected_signal() -> void:
    var n := MockNet.new()
    var hud := Hud.new()
    tree.root.add_child(hud)
    hud.match_end = MatchEndScreen.new()
    hud.add_child(hud.match_end)
    hud._setup_net_ui(n)
    check(n.disconnected.get_connections().size() == 1, "connected to Net.disconnected")
    n.disconnected.emit("host closed the connection")
    check(hud.conn_lost.visible and hud.conn_lost.title.text == "Host left", "screen shown on disconnect")
    check(hud.conn_lost.routes.size() >= 1, "route resolved")
    hud.free(); n.free()
    Actions.gameplay_enabled = true
    var plain := Hud.new()
    check(Net.has_signal("disconnected"), "real Net has disconnected(reason)")
    plain.free()
