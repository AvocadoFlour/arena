extends SceneTree
## Online client probe for the Match page (run by tests/ui_net_match.sh, not by run_tests.gd):
## boots main.tscn as a client (-- --net_join=IP:PORT), then checks the bot steppers are disabled with the
## host note, presses a hero button and waits for the host-timed swap. Prints `UIPROBE {json}` and quits.
var m
var t := 0.0
var step := 0
var r := {}
var target := ""
var got := []
var net: Node   ## Net autoload (autoload identifiers are not compiled into -s scripts)

func _initialize() -> void:
    net = root.get_node("Net")
    m = load("res://src/main.tscn").instantiate()
    root.add_child(m)

func _process(dt: float) -> bool:
    t += dt
    if t > 40.0:
        r["timeout_step"] = step
        return _out()
    if step == 0:
        if m.get("menu") == null or not net.is_client() or m.local_net_id() <= 0 or not is_instance_valid(m.get("player")):
            return false
        var pm = m.menu
        var page = pm.match_page
        pm.open()
        pm.open_match()
        var row: Node = page.find_child("BotsTeam1", true, false)
        r["client"] = pm.match_ctl.is_client()
        r["bots_disabled"] = row.find_child("Plus", true, false).disabled and row.find_child("Minus", true, false).disabled
        r["bot_note"] = page.bot_note.text
        r["bot_counts"] = str(m.match_bot_counts())
        r["value"] = page.bot_val[1].text
        r["set_refused"] = not pm.match_ctl.set_bot_count(1, 0)
        m.hero_swap_started.connect(func(id, h, d): got.append(["started", id, h, d]))
        m.hero_swap_finished.connect(func(id, h): got.append(["finished", id, h]))
        m.hero_swap_cancelled.connect(func(id, why): got.append(["cancelled", id, why]))
        r["old_hero"] = pm.match_ctl.local_hero_id()
        for b in page.hero_btns:
            if b.get_meta("hero_id") != r.old_hero:
                target = b.get_meta("hero_id")
                b.pressed.emit()
                break
        r["hero_note"] = page.hero_note.text
        r["target"] = target
        step = 1
    elif step == 1:
        var page = m.menu.match_page
        if page.countdown.visible:
            r["countdown"] = page.countdown.text
        if got.any(func(e): return e[0] != "started"):
            r["events"] = str(got)
            r["new_hero"] = m.menu.match_ctl.local_hero_id()
            r["countdown_hidden"] = not page.countdown.visible
            return _out()
    return false

func _out() -> bool:
    print("UIPROBE " + JSON.stringify(r))
    net.close()
    quit()
    return true
