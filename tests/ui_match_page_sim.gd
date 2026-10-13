extends Node3D
## Esc overlay Match page end to end on the real composition root (main.tscn, offline) and the real
## INTERFACES §8.1 hooks: bot steppers spawn/despawn hero nodes, hero switch shows the countdown and respawns
## the player as the new hero, team switch moves the player. Drives the UI by pressing its buttons.
var results: Array = []
var done := false
var m
var pm: PauseMenu
var page: MatchPage
var t := 0.0
var t_mark := 0.0
var step := 0
var orig_hero := ""
var old_hero := ""
var new_hero := ""
var my_id := -1
var saw_count := false

func _rec(n: String, ok: bool, info := "") -> void:
    results.append([n, ok, info])

func _ready() -> void:
    orig_hero = GameConfig.hero_id
    GameConfig.skip_menu_once = true
    m = load("res://src/main.tscn").instantiate()
    add_child(m)

func _team_heroes(team: int) -> int:
    return get_tree().get_nodes_in_group("heroes").filter(func(h): return is_instance_valid(h) and h.team == team and not h.is_queued_for_deletion()).size()

func _row_btn(team: int, n: String) -> Button:
    return page.find_child("BotsTeam%d" % team, true, false).find_child(n, true, false)

func _physics_process(dt: float) -> void:
    if done:
        return
    t += dt
    match step:
        0:
            if t < 0.3:
                return
            pm = m.menu
            page = pm.match_page
            my_id = m.local_net_id()
            _rec("adapter_on_root", pm.match_ctl.src == m and pm.match_ctl.bots_available() and pm.match_ctl.hero_available() and pm.match_ctl.team_available())
            pm.open()
            (pm.panel.find_child("Match", true, false) as Button).pressed.emit()
            _rec("page_open", pm.match_open() and page.bot_note.text == "" and page.hero_note.text == "" and page.team_note.text == "", "%s|%s|%s" % [page.bot_note.text, page.hero_note.text, page.team_note.text])
            var c: Dictionary = m.match_bot_counts()
            var before := _team_heroes(1)
            _rec("value_shows_count", page.bot_val[1].text == str(c[1]))
            _row_btn(1, "Plus").pressed.emit()
            _rec("plus_spawns_bot", m.match_bot_counts()[1] == c[1] + 1 and _team_heroes(1) == before + 1 and page.bot_val[1].text == str(c[1] + 1), "%d -> %d" % [before, _team_heroes(1)])
            _row_btn(1, "Minus").pressed.emit()
            _row_btn(1, "Minus").pressed.emit()
            _rec("minus_despawns_bot", m.match_bot_counts()[1] == c[1] - 1 and _team_heroes(1) == before - 1, "%d" % _team_heroes(1))
            for i in 8:
                _row_btn(0, "Plus").pressed.emit()
            _rec("clamped_5", m.match_bot_counts()[0] == 5 and _row_btn(0, "Plus").disabled and _team_heroes(0) == 6, "%d" % _team_heroes(0))
            for i in 8:
                _row_btn(0, "Minus").pressed.emit()
            _rec("down_to_0", m.match_bot_counts()[0] == 0 and _row_btn(0, "Minus").disabled and _team_heroes(0) == 1)
            _row_btn(1, "Plus").pressed.emit()
            old_hero = String(m.player.def.id)
            var cur_btn: Button = page.find_child("Hero_" + old_hero, true, false)
            _rec("current_hero_marked", cur_btn != null and cur_btn.disabled and cur_btn.text.contains("current"))
            for b in page.hero_btns:
                if b.get_meta("hero_id") != old_hero:
                    new_hero = b.get_meta("hero_id")
                    b.pressed.emit()
                    break
            _rec("countdown_shown", page.countdown.visible and page.countdown.text.ends_with("3"), page.countdown.text)
            pm.close()   # unpause; countdown must stay up
            _rec("countdown_after_close", page.countdown.is_visible_in_tree())
            t_mark = t
            step = 1
        1:
            if page.countdown.visible and page.countdown.text.ends_with("1"):
                saw_count = true
            if String(m.player.def.id) != new_hero:
                if t - t_mark > 8.0:
                    _rec("respawned_as_new", false, "timeout")
                    _end()
                return
            _rec("counted_down", saw_count)
            _rec("respawned_as_new", m.player.net_id == my_id and not page.countdown.visible, "%s" % m.player.def.id)
            _rec("swap_took_delay", t - t_mark >= m.HERO_SWAP_DELAY - 0.1, "%.2f" % (t - t_mark))
            page.refresh()
            _rec("new_current_marked", (page.find_child("Hero_" + new_hero, true, false) as Button).disabled and not (page.find_child("Hero_" + old_hero, true, false) as Button).disabled)
            pm.open()
            pm.open_match()
            _rec("team_btn_current", page.team_btns[0].disabled and not page.team_btns[1].disabled)
            page.team_btns[1].pressed.emit()
            _rec("team_request_ok", page.team_note.text == "" and page.countdown.visible, page.team_note.text)
            pm.close()
            t_mark = t
            step = 2
        2:
            if m.player.team != 1:
                if t - t_mark > 8.0:
                    _rec("team_switched", false, "timeout")
                    _end()
                return
            _rec("team_switched", m.player.net_id == my_id and m.local_team() == 1 and not page.countdown.visible)
            _rec("team_page_updated", page.team_btns[1].disabled and page.team_btns[1].text.contains("current") and not page.team_btns[0].disabled)
            _end()

func _end() -> void:
    GameConfig.set_hero(orig_hero)
    Net.world = null
    get_tree().paused = false
    Actions.gameplay_enabled = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    done = true
