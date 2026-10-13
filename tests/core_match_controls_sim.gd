extends Node3D
## In-match controls (INTERFACES §8): live bot counts, hero swap after HERO_SWAP_DELAY (death keeps it pending),
## team change, rejects. Offline, on the real composition root (main.tscn).
var results: Array = []
var done := false
var m
var t := 0.0
var step := 0
var ev := []
var old_hero := ""
var new_hero := ""
var my_id := -1
var orig_hero := ""
var counts0 := {}
var t_mark := 0.0

func _rec(n: String, ok: bool, info := "") -> void:
    results.append([n, ok, info])

func _ready() -> void:
    orig_hero = GameConfig.hero_id
    GameConfig.skip_menu_once = true
    m = load("res://src/main.tscn").instantiate()
    add_child(m)
    for s in ["hero_swap_started", "hero_swap_finished", "hero_swap_cancelled", "bot_counts_changed", "team_changed", "bot_difficulty_changed"]:
        var sname: String = s
        m.connect(s, func(a = null, b = null, c = null): ev.append([sname, a, b, c]))

func _names() -> Array:
    return ev.map(func(e): return e[0])

func _physics_process(dt: float) -> void:
    if done:
        return
    t += dt
    match step:
        0:
            if t < 0.3:
                return
            my_id = m.local_net_id()
            _rec("local_net_id", my_id == m.player.net_id and my_id > 0, str(my_id))
            _rec("local_team", m.local_team() == 0)
            counts0 = m.match_bot_counts()
            var c1: int = counts0[1]
            _rec("bots_add", m.set_bot_count(1, c1 + 1) and m.match_bot_counts()[1] == c1 + 1, str(m.match_bot_counts()))
            _rec("bots_remove", m.set_bot_count(1, 0) and m.match_bot_counts()[1] == 0)
            _rec("bots_clamp", m.set_bot_count(1, 9) and m.match_bot_counts()[1] == 5)
            _rec("bots_bad_team", not m.set_bot_count(4, 1))
            m.set_bot_count(1, c1)
            _rec("bots_signal", _names().has("bot_counts_changed"))
            var live := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.team == 1 and not h.is_queued_for_deletion()).size()
            _rec("bots_live_heroes", live == c1, "team1 heroes %d" % live)
            var dsig := ev.size()
            _rec("diff_bad_level", not m.set_bot_difficulty(1, "insane") and not m.set_bot_difficulty(3, "hard"))
            _rec("diff_set", m.set_bot_difficulty(1, "hard") and m.match_bot_difficulty()[1] == "hard" and GameConfig.bot_difficulty == "hard")
            _rec("diff_signal", ev.size() > dsig and ev[-1][0] == "bot_difficulty_changed" and ev[-1][1] == 1 and ev[-1][2] == "hard", str(ev.slice(dsig)))
            var t1 := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.team == 1 and not h.is_queued_for_deletion())
            _rec("diff_live_bots", t1.size() > 0 and t1.all(func(h): return is_equal_approx(h.damage_scale, GameConfig.DIFFICULTY.hard.damage_scale)), "%d bots" % t1.size())
            m.set_bot_count(1, c1 + 1)
            var nb = m._bots[1][-1]
            _rec("diff_new_bot", is_equal_approx(nb.damage_scale, GameConfig.DIFFICULTY.hard.damage_scale))
            m.set_bot_count(1, c1)
            m.set_bot_difficulty(1, "normal")
            old_hero = String(m.player.def.id)
            for id in GameConfig.hero_ids():
                if id != old_hero:
                    new_hero = id
                    break
            ev.clear()
            _rec("swap_same_rejected", not m.request_hero_change(old_hero) and _names().has("hero_swap_cancelled"))
            _rec("swap_unknown_rejected", not m.request_hero_change("nope"))
            ev.clear()
            _rec("swap_accepted", m.request_hero_change(new_hero))
            _rec("swap_started_signal", ev.size() == 1 and ev[0][0] == "hero_swap_started" and ev[0][1] == my_id and ev[0][2] == new_hero and is_equal_approx(float(ev[0][3]), m.HERO_SWAP_DELAY), str(ev))
            _rec("swap_double_rejected", not m.request_hero_change(old_hero))
            t_mark = t
            step = 5
        5:
            if t - t_mark < 1.5:
                return
            m.player.take_damage(99999.0, null, m.player.global_position, "test")   # dies mid-delay: respawn at +4.5 s
            step = 1
        1:
            if t - t_mark < m.HERO_SWAP_DELAY + 0.3:
                return
            _rec("death_keeps_pending", String(m.player.def.id) == old_hero and m.player.dead and not _names().has("hero_swap_finished"), "dead=%s" % m.player.dead)
            step = 2
        2:
            if not _names().has("hero_swap_finished"):
                if t - t_mark > 15.0:
                    _rec("swap_finished", false, "timeout")
                    _end()
                return
            var p = m.player
            _rec("swap_finished", String(p.def.id) == new_hero and p.net_id == my_id and not p.dead and p.health.hp == p.health.max_hp, "%s id %d" % [p.def.id, p.net_id])
            _rec("swap_hud_rebound", m.hud.player == p and m.hud.kill_feed.player == p)
            _rec("swap_config_kept", GameConfig.hero_id == new_hero)
            _rec("swap_single_hero", get_tree().get_nodes_in_group("heroes").filter(func(h): return h.net_id == my_id).size() == 1)
            ev.clear()
            counts0 = m.match_bot_counts()
            _rec("team_accepted", m.request_team_change(1))
            t_mark = t
            step = 3
        3:
            if not _names().has("team_changed"):
                if t - t_mark > 8.0:
                    _rec("team_changed", false, "timeout " + str(_names()))
                    _end()
                return
            _rec("team_changed", m.player.team == 1 and m.local_team() == 1 and m.player.net_id == my_id)
            var c: Dictionary = m.match_bot_counts()
            var moved := 1 if int(counts0[1]) > 0 else 0
            _rec("team_bot_moved", c[0] == counts0[0] + moved and c[1] == counts0[1] - moved, "%s vs %s" % [c, counts0])
            _end()

func _end() -> void:
    GameConfig.set_hero(orig_hero)
    Net.world = null
    get_tree().paused = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    done = true
