extends "res://tests/test_base.gd"
## UI round 5: real Host/Join screens (Net.offline), kill feed, damage-number pop.
var tree: SceneTree

class FakeHero extends Node:
    var display_name := ""
    var team := 0
    var def := {}
    func _init(n: String, d := {}) -> void:
        display_name = n
        def = d

func _net_panel(kind: String) -> Array:
    Net.offline = true
    var mm := MainMenu.new()
    tree.root.add_child(mm)
    var p := NetPanel.new(kind)
    mm.add_screen("net_" + kind, p)
    return [mm, p]

func _check_polished(p: Control, kind: String) -> void:
    for e in p.find_children("*", "LineEdit", true, false):
        check(e.custom_minimum_size.y >= 64 and e.has_theme_stylebox_override("normal"), kind + " edit polished")
    for b in p.find_children("*", "Button", true, false):
        check(b.custom_minimum_size.y >= 64 and b.custom_minimum_size.x >= 320, kind + " button touch size: " + b.text)
        check(b.has_theme_stylebox_override("hover") and b.has_theme_stylebox_override("focus"), kind + " button styled: " + b.text)

func test_real_host_screen_offline() -> void:
    var r := _net_panel("host")
    var mm: MainMenu = r[0]
    var p: NetPanel = r[1]
    _check_polished(p, "host")
    var btns: Array = p.find_children("*", "Button", true, false)
    check(btns.map(func(b): return b.text) == ["Start hosting", "Back"], "button texts unchanged")
    check(p.find_children("*", "Label", true, false).any(func(l): return l.text == "HOST ONLINE GAME"), "title unchanged")
    check(p.port_edit.text == str(Net.DEFAULT_PORT), "default port text")
    check(p.status.text == "Finding your public IP...", "offline: no lookup result yet")
    p._on_ip("")   # what offline emits (deferred) -> core's fallback text
    check(p.status.text.begins_with("Could not look up your public IP"), "offline fallback text")
    var ports := []
    p.host_requested.connect(func(port): ports.append(port))
    btns[0].pressed.emit()
    check(ports == [Net.DEFAULT_PORT], "host_requested(port) unchanged")
    var closed := []
    p.closed.connect(func(): closed.append(1))
    btns[1].pressed.emit()
    check(closed == [1], "Back emits closed")
    mm.free()

func test_real_join_screen_offline() -> void:
    var r := _net_panel("join")
    var mm: MainMenu = r[0]
    var p: NetPanel = r[1]
    _check_polished(p, "join")
    var btns: Array = p.find_children("*", "Button", true, false)
    check(btns.map(func(b): return b.text) == ["Connect", "Back"], "button texts unchanged")
    check(p.addr_edit.placeholder_text.contains(str(Net.DEFAULT_PORT)), "placeholder unchanged")
    var got := []
    p.join_requested.connect(func(a, port): got.append([a, port]))
    p.addr_edit.text = "203.0.113.7:9001"
    btns[0].pressed.emit()
    check(got == [["203.0.113.7", 9001]], "join_requested(addr, port) %s" % [got])
    var closed := []
    p.closed.connect(func(): closed.append(1))
    btns[1].pressed.emit()
    check(closed == [1], "Back emits closed")
    mm.free()

func test_back_returns_to_main_via_core_wiring_shape() -> void:
    var r := _net_panel("join")
    var mm: MainMenu = r[0]
    var p: NetPanel = r[1]
    p.closed.connect(func(): mm.show_screen("main"))   # same wiring as INTERFACES §2.3
    mm.show_screen("net_join")
    check(p.visible and not mm.screens.main.visible, "on join screen")
    p.find_children("*", "Button", true, false)[1].pressed.emit()
    check(mm.screens.main.visible and not p.visible, "Back -> main menu")
    mm.free()

func test_kill_feed_weapon_names() -> void:
    var cob := FakeHero.new("Cob", JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/cob.json")))
    check(KillFeed.weapon_name(cob, "primary") == "Primary", "hitscan primary")
    check(KillFeed.weapon_name(cob, "ultimate") == "Quarry Quake", "ultimate name from def")
    check(KillFeed.weapon_name(cob, "charge") == "Boulder Roll", "ability named via type")
    check(KillFeed.weapon_name(FakeHero.new("M", {"primary": {"type": "melee"}}), "primary") == "Melee", "melee")
    check(KillFeed.weapon_name(null, "fall") == "Fall", "fall")
    check(KillFeed.weapon_name(null, "slam") == "Slam", "fallback kind")
    cob.free()

func test_kill_feed_order_cap_highlight_fade() -> void:
    var me := FakeHero.new("You")
    var bot := FakeHero.new("Bot")
    var kf := KillFeed.new()
    kf.player = me
    tree.root.add_child(kf)
    var first := kf.on_kill({"killer": me, "victim": bot, "kind": "primary"})
    check(first.get_meta("highlight") == "kill", "player kill highlighted")
    var second := kf.on_kill({"killer": bot, "victim": me, "kind": "primary"})
    check(kf.get_child(0) == second, "newest on top")
    check(second.get_meta("highlight") == "death", "player death highlighted")
    check(second.get_meta("text") == "Bot  [Primary]  You", "text: " + second.get_meta("text"))
    var other := kf.on_kill({"killer": bot, "victim": bot, "kind": "fall"})
    check(not other.has_meta("highlight"), "others not highlighted")
    for i in 6:
        kf.on_kill({"killer": null, "victim": bot, "kind": "fall"})
    check(kf.get_child_count() == KillFeed.MAX, "capped at %d (%d)" % [KillFeed.MAX, kf.get_child_count()])
    check(not is_instance_valid(first) or first.get_parent() != kf, "oldest dropped")
    check(str(kf.get_child(0).get_meta("text")).begins_with("World"), "world kill text")
    check(KillFeed.LIFETIME <= 6.0 and KillFeed.FADE > 0.0, "fades after a few seconds")
    kf.free()
    me.free()
    bot.free()

func test_damage_number_pop() -> void:
    var n := DamageNumber.pop_params(14, false)
    var big := DamageNumber.pop_params(80, false)
    var kill := DamageNumber.pop_params(14, true)
    check(n.punch > 1.0 and n.rise > 0.0 and n.life > 0.0, "normal: punch, rise, fade")
    check(big.size > n.size and big.punch > n.punch and big.rise > n.rise, "big hit emphasised")
    check(kill.size >= big.size, "killing blow strongest")
    var d := DamageNumber.new(80, "primary", false)
    tree.root.add_child(d)
    var tw := d.pop()
    check(tw != null and tw.is_valid(), "pop tween running")
    check(d.big and d.outline_size >= 22, "big outline")
    check(d.scale.x < big.size, "starts small, punches up")
    var k := DamageNumber.new(30, "slam", true)
    tree.root.add_child(k)
    k.pop()
    check(k.text == "30!", "kill marker")
    d.free()
    k.free()
