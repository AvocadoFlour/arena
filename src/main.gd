extends Node3D
## Composition root: builds map, heroes, HUD and menu. Handles command-line modes:
##   -- --demo            scripted autopilot (moves, looks, fires, dashes, slams, ults)
##   -- --smoke=SECONDS   run demo, print stats, exit 0 (pass) or 1 (fail)
##   -- --screenshot=PATH --delay=S [--menu] [--use=SLOT --use_lead=S]   save a PNG after S seconds and quit
##   -- --hero=ID --map=ID --bots=easy|normal|hard   (GameConfig)
##   -- --net_host=PORT | --net_join=IP:PORT   online (docs/INTERFACES.md §10); --autopilot bot-drives the player;
##      --net_test=S prints NETDUMP after S seconds (tools/net_test.sh)

var player: Hero
var hud: Hud
var menu: PauseMenu
var args := {}
var stats := {"player_dmg": 0.0, "bot_dmg": 0.0, "kills": 0, "deaths": 0, "ability1": 0, "ability2": 0, "ultimate": 0}
var _t0 := 0
var _game_t := 0.0   ## game time (fixed-step in movie mode)
var _shot_done := false
var _used := false
var _spawns: Dictionary = {}
var main_menu = null
var rules: MatchRules
var _bots := {0: [], 1: []}   ## team -> bot heroes (host replaces one per joining human)
var _net_status: Label
var _dump := {"kills": [], "remote_dmg": 0.0, "match_ended": null}
var _dump_open := true        ## kills are recorded until match_ended
var _dumped := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS   # screenshot/smoke timers keep running while paused
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--"):
            var kv := a.substr(2).split("=", true, 1)
            args[kv[0]] = kv[1] if kv.size() > 1 else "1"
    Net.world = self
    if args.has("smoke"):   # deterministic smoke: fixed seeds for global RNG, hero spread and bot brains
        seed(int(args.get("seed", "4242")))
    Net.disconnected.connect(_on_net_lost)
    if args.has("net_test"):
        get_tree().create_timer(float(args.net_test), true, true).timeout.connect(func(): _net_dump(); get_tree().quit(0))
    if args.has("net_join"):
        var a := NetPanel.parse_address(args.net_join)
        _join(a[0], a[1])
        return
    if args.has("net_host"):
        Net.host(int(args.net_host))
        print("NET hosting on ", args.net_host)
    if _test_mode() or args.has("menu") or GameConfig.skip_menu_once:
        GameConfig.skip_menu_once = false
        _start_match()
    else:
        _show_main_menu()

## Any test/automation flag bypasses the main menu.
func _test_mode() -> bool:
    for k in ["demo", "smoke", "screenshot", "hero", "map", "net_host", "autopilot"]:
        if args.has(k) and not args.has("mainmenu"):
            return true
    return false

func _show_main_menu() -> void:
    main_menu = MainMenu.new()
    add_child(main_menu)
    UiCatalog.selected_hero = GameConfig.hero_path(GameConfig.hero_id)
    UiCatalog.selected_map = GameConfig.map_path()
    main_menu.play_requested.connect(func(hero_path: String, map_path: String):
        GameConfig.set_hero(hero_path.get_file().get_basename())
        GameConfig.map_id = map_path.get_file().get_basename()
        main_menu.queue_free()
        main_menu = null
        _start_match())
    main_menu.add_menu_entry("Host online", _open_net_panel.bind("host"))
    main_menu.add_menu_entry("Join online", _open_net_panel.bind("join"))
    if args.has("ui_screen"):
        main_menu.show_screen(args.ui_screen)
    _t0 = Time.get_ticks_msec()

func _start_match() -> void:
    var demo := args.has("demo") or args.has("smoke") or args.has("screenshot") or args.has("autopilot")
    var map := MapLoader.build(GameConfig.map_path())
    add_child(map)
    var spawns: Dictionary = map.get_meta("spawns")
    var zones: Array = CaptureZone.from_map(map)
    for z in zones:
        add_child(z)
        ZoneBridge.wire(z)
    rules = MatchRules.new()
    rules.name = "MatchRules"
    add_child(rules)
    rules.setup(zones)
    stats["mode"] = rules.mode
    Events.capture_completed.connect(func(_ev): stats["zone_captures"] = stats.get("zone_captures", 0) + 1)
    if args.has("force_end"):
        get_tree().create_timer(float(args.force_end), false, true).timeout.connect(func(): rules.force_end("forced"))
    Events.match_ended.connect(_on_match_ended)
    _spawns = spawns
    stats["map"] = GameConfig.map_id
    player = Hero.from_def(GameConfig.hero_path(GameConfig.hero_id))
    player.display_name = "You (%s)" % player.def.get("name", GameConfig.hero_id)
    player.set_meta("net_name", "Host (%s)" % player.def.get("name", GameConfig.hero_id))
    stats["hero"] = GameConfig.hero_id
    player.set_team(0)
    player.spawn_point = spawns[0][0]
    add_child(player)
    player.global_position = player.spawn_point
    var rig := CameraRig.new()
    player.add_child(rig)
    rig.setup(player)
    if args.has("smoke"):
        player.ult.add(player.ult.cost * 0.8)   # smoke: start near-full so the ultimate is exercised on big maps
    if demo:
        player.input_source = BotBrain.new({"difficulty": "hard", "use_abilities": true, "seek_cover": false, "escort_allies": false, "turn_rate": 6.0, "fire_cone": 0.08, "spread_deg": 1.0, "reaction_time": 0.1, "bounds": float(map.get_meta("bounds"))})
    else:
        player.input_source = Actions
        player.aim_camera = rig.cam
    Net.register(player)
    _seed_for_smoke(player)
    var roster: Array = GameConfig.hero_ids()   # mixed bot roster: cycle through all heroes
    var diff: Dictionary = GameConfig.difficulty()
    stats["bots"] = []
    stats["difficulty"] = GameConfig.bot_difficulty
    var n_allies := GameConfig.allies_for(map)
    stats["allies"] = []
    var pidx: int = maxi(0, roster.find(GameConfig.hero_id))
    for i in n_allies:
        var aid: String = roster[(pidx + 1 + i) % roster.size()]   # allies: the heroes after the player's in the roster
        _spawn_bot(aid, 0, i, spawns, map, diff, "Ally %d (%s)", (i + 1))
        stats.allies.append(aid)
    for i in GameConfig.enemy_count:
        var bid: String = roster[i % roster.size()]
        _spawn_bot(bid, 1, i, spawns, map, diff, "Bot %d (%s)", i)
        stats.bots.append(bid)
    hud = Hud.new()
    add_child(hud)
    hud.setup(player)
    hud.match_end.play_again.connect(func(): _restart(true))
    hud.match_end.main_menu.connect(func(): _restart(false))
    menu = PauseMenu.new()
    add_child(menu)
    Events.damage_dealt.connect(_on_dmg)
    Events.killed.connect(_on_kill)
    Events.killed.connect(_schedule_respawn_pick)
    Events.ability_used.connect(func(h, slot, _id): if h == player: stats[slot] = stats.get(slot, 0) + 1)
    _hook_net_dump()
    for c in get_children():
        if c != menu:
            c.process_mode = Node.PROCESS_MODE_PAUSABLE
    if Net.is_host():
        _show_net_status()
    if args.has("menu"):
        menu.open()
    elif not demo:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _t0 = Time.get_ticks_msec()

func _on_dmg(ev: Dictionary) -> void:
    if is_instance_valid(ev.target) and ev.target.team == 0 and is_instance_valid(ev.source) and ev.source is Hero and ev.source.team == 1:
        stats["team_dmg_taken"] = stats.get("team_dmg_taken", 0.0) + float(ev.amount)   # enemy pressure on the whole team
    if ev.source == player:
        stats.player_dmg += ev.amount
        stats["hits_" + ev.kind] = stats.get("hits_" + ev.kind, 0) + 1
    elif ev.target == player:
        stats.bot_dmg += ev.amount

## Respawn hook (maps request 3): just before a hero respawns, choose the spawn no enemy can see.
func _schedule_respawn_pick(ev: Dictionary) -> void:
    var h = ev.victim
    get_tree().create_timer(maxf(0.0, Hero.RESPAWN_TIME - 0.1), false, true).timeout.connect(func():
        if is_instance_valid(h) and h.dead:
            h.spawn_point = SpawnPicker.pick_for(h, _spawns.get(h.team, [h.spawn_point])))

func _on_match_ended(ev: Dictionary) -> void:
    stats["match_ended"] = stats.get("match_ended", 0) + 1
    stats["winner_team"] = ev.winner_team
    print("MATCH ENDED ", JSON.stringify(ev))
    if not _test_mode():
        if not Net.is_client():
            get_tree().paused = true   # UI bot's match-end screen listens to Events.match_ended
        Actions.gameplay_enabled = false
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Spawns one bot hero. Team 0 = ally of the player, team 1 = enemy. spawn_slot indexes the team's spawns.
func _spawn_bot(id: String, team: int, i: int, spawns: Dictionary, map: Node3D, diff: Dictionary, label: String, spawn_slot: int) -> Hero:
    var b := Hero.from_def(GameConfig.hero_path(id))
    b.display_name = label % [i + 1, b.def.get("name", id)]
    b.set_team(team)
    b.damage_scale = diff.damage_scale
    var brain := BotBrain.new({"bounds": float(map.get_meta("bounds")), "difficulty": GameConfig.bot_difficulty})
    b.input_source = brain
    b.extra_spread_deg = brain.spread_deg
    var arr: Array = spawns[team]
    b.spawn_point = arr[spawn_slot % arr.size()]
    add_child(b)
    b.global_position = b.spawn_point
    b.yaw = PI if team == 1 else 0.0
    Net.register(b)
    _seed_for_smoke(b)
    _bots[team].append(b)
    return b

func _seed_for_smoke(h: Hero) -> void:
    if not args.has("smoke"):
        return
    var base := int(args.get("seed", "4242"))
    h._rng.seed = hash([base, h.net_id])
    if h.input_source is BotBrain:
        h.input_source._rng.seed = hash([base, h.net_id, "brain"])

func _restart(skip_menu: bool) -> void:
    if Net.is_online():   # online sessions end on restart; back to the menu
        Net.close()
        skip_menu = false
    GameConfig.skip_menu_once = skip_menu
    get_tree().paused = false
    Actions.gameplay_enabled = true
    get_tree().reload_current_scene()

func _on_kill(ev: Dictionary) -> void:
    if args.has("shot_after_kill") and is_instance_valid(ev.killer) and not args.has("_kill_seen"):
        args["_kill_seen"] = "1"   # test hook: take the screenshot shortly after the first kill (kill feed capture)
        args["delay"] = str(_game_t + float(args.shot_after_kill))
    stats["any_kills"] = stats.get("any_kills", 0) + 1
    if ev.killer == player:
        stats.kills += 1
    if ev.victim == player:
        stats.deaths += 1

func _unhandled_input(event: InputEvent) -> void:
    if menu == null:
        return
    if args.has("demo") or args.has("smoke") or args.has("screenshot"):
        return
    if event.is_action_pressed("pause"):
        if menu.visible:
            menu.close()
        else:
            menu.open()
            if Net.is_online():
                get_tree().paused = false   # the world never pauses online
    elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu.visible:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(dt: float) -> void:
    _game_t += dt
    var el := _game_t
    if player == null:
        if args.has("screenshot") and not _shot_done and el >= float(args.get("delay", "3")):
            _shot_done = true
            get_viewport().get_texture().get_image().save_png(args.screenshot)
            print("SCREENSHOT ", args.screenshot)
            get_tree().quit(0)
        return
    if args.has("use") and not _used and el >= float(args.get("delay", "6")) - float(args.get("use_lead", "0.3")):
        _used = true   # test hook: force an ability right before the screenshot
        if args.has("stage_ally"):   # test hook: hurt ally placed in front of the player (heal-beam screenshot)
            for h in get_tree().get_nodes_in_group("heroes"):
                if h != player and h.team == player.team:
                    var f: Vector3 = player.look_dir()
                    h.global_position = player.global_position + Vector3(f.x, 0, f.z).normalized() * 5.0 + Vector3(0, 0.3, 0)
                    h.health.hp = h.health.max_hp * 0.4
                    break
        if player.abilities.has(args.use):
            player.abilities[args.use].cooldown.remaining = 0.0
        player._use(args.use)
    if args.has("screenshot") and not _shot_done and el >= float(args.get("delay", "6")):
        _shot_done = true
        get_viewport().get_texture().get_image().save_png(args.screenshot)
        print("SCREENSHOT ", args.screenshot, " ", get_viewport().get_visible_rect().size)
        _finish()
    if args.has("smoke") and el >= float(args.smoke) * 0.6 and not player.dead:
        # autopilot policy (src/ai) may skip situational abilities: exercise each unused slot once (retries while dead)
        for slot in ["ability1", "ability2", "ultimate"]:
            if stats.get(slot, 0) == 0 and player.abilities.has(slot) and not stats.get("forced", []).has(slot):
                player.abilities[slot].cooldown.remaining = 0.0
                if slot == "ultimate":
                    player.ult.add(player.ult.cost)
                player._use(slot)
                stats["forced"] = stats.get("forced", []) + [slot]
    if args.has("smoke") and el >= float(args.smoke):
        _finish()
    if args.has("demo") and args.demo != "1" and el >= float(args.demo):
        _finish()

func _finish() -> void:
    var s: Array = hud.fps_samples.slice(30)
    var avg := 0.0
    for x in s:
        avg += x
    avg = avg / max(1, s.size())
    stats["fps_avg"] = snappedf(avg, 0.1)
    stats["fps_min"] = s.min() if s.size() > 0 else 0
    print("STATS ", JSON.stringify(stats))
    # kills are reported but not required: a 35 s window on big maps can legitimately end 0 kills
    # team maps: allies soak fire, so enemy pressure is measured on the whole team (team_dmg_taken), not the player
    var taken: float = stats.get("team_dmg_taken", 0.0) if stats.get("allies", []).size() > 0 else stats.bot_dmg
    var ok: bool = stats.player_dmg > 0 and taken > 0 and stats.get("match_ended", 0) == 1 and stats.ability1 > 0 and stats.ability2 > 0 and stats.ultimate > 0
    if args.has("smoke"):
        print("SMOKE ", "PASS" if ok else "FAIL")
    get_tree().quit(0 if ok or not args.has("smoke") else 1)

# ---------------------------------------------------------------- online (docs/INTERFACES.md §10)
func _open_net_panel(kind: String) -> void:
    var scr := "net_" + kind
    if main_menu.screens.has(scr):   # rebuilt each time so the hero/map labels are current
        main_menu.screens[scr].queue_free()
        main_menu.screens.erase(scr)
    var panel := NetPanel.new(kind)
    main_menu.add_screen(scr, panel)
    main_menu.show_screen(scr)
    panel.closed.connect(func(): main_menu.show_screen("main"))
    panel.host_requested.connect(func(port: int):
        var err := Net.host(port)
        if err != OK:
            panel.set_status("Could not open UDP port %d (error %d). Is another copy running?" % [port, err])
            return
        GameConfig.set_hero(UiCatalog.selected_hero.get_file().get_basename())
        GameConfig.map_id = UiCatalog.selected_map.get_file().get_basename()
        main_menu.queue_free()
        main_menu = null
        _start_match())
    panel.join_requested.connect(func(addr: String, port: int):
        GameConfig.set_hero(UiCatalog.selected_hero.get_file().get_basename())
        if _join(addr, port) != OK:
            panel.set_status("Invalid address.")
            return
        )

func _join(addr: String, port: int) -> int:
    var err := Net.join(addr, port)
    if err == OK:
        Net.welcomed.connect(_start_client, CONNECT_ONE_SHOT)
        print("NET joining ", addr, ":", port)
    return err

func _on_net_lost(reason: String) -> void:
    if args.has("net_test"):
        _net_dump()
        get_tree().quit(0)
        return
    print("NET lost: ", reason)
    if player == null and main_menu != null:
        return   # still in the menu: the panel shows the failure
    _restart(false)

func _show_net_status() -> void:
    var cl := CanvasLayer.new()
    cl.layer = 15
    _net_status = MenuStyle.label("", 16)
    _net_status.position = Vector2(12, 8)
    cl.add_child(_net_status)
    add_child(cl)
    var upd := func(_x = null):
        _net_status.text = "Hosting  %s:%d   players %d/%d" % [Net.public_ip if Net.public_ip != "" else "<your public IP>", Net.port, 1 + Net.peers.size(), Net.MAX_HUMANS]
    Net.public_ip_ready.connect(upd)
    Net.peer_count_changed.connect(upd)
    upd.call()
    if Net.public_ip == "" and not args.has("net_test"):
        Net.fetch_public_ip()

## HOST: a remote human said hello. Puts them on the team with fewer humans, replacing one of its bots.
func net_spawn_human(pid: int, hero_id: String, pname: String) -> Hero:
    var humans := {0: 0, 1: 0}
    for h in Net.heroes():
        if h == player or h.has_meta("peer"):
            humans[h.team] += 1
    var team := 0 if humans[0] < humans[1] else 1
    var spawn: Vector3 = _spawns[team][humans[team] % _spawns[team].size()]
    _bots[team] = _bots[team].filter(func(b): return is_instance_valid(b))
    if not _bots[team].is_empty():
        var bot: Hero = _bots[team].pop_back()
        spawn = bot.spawn_point
        Net.despawn(bot)
    if not GameConfig.hero_ids().has(hero_id):
        hero_id = GameConfig.DEFAULT_HERO
    var h := Hero.from_def(GameConfig.hero_path(hero_id))
    h.display_name = "%s (%s)" % [pname, h.def.get("name", hero_id)]
    h.set_meta("net_name", h.display_name)
    h.set_meta("peer", pid)
    h.set_team(team)
    h.spawn_point = spawn
    h.input_source = RemoteInput.new()
    h.process_mode = Node.PROCESS_MODE_PAUSABLE
    add_child(h)
    h.global_position = spawn
    h.yaw = PI if team == 1 else 0.0
    Net.register(h)
    print("NET human joined: ", h.display_name, " team ", team, " id ", h.net_id)
    return h

func net_peer_left(_pid: int) -> void:
    pass   # the slot stays empty until the next match (bots are not re-filled mid-match)

## CLIENT: the host accepted us. Builds a passive world: map + heroes driven by snapshots.
func _start_client(info: Dictionary) -> void:
    if main_menu:
        main_menu.queue_free()
        main_menu = null
    var map := MapLoader.build(GameConfig.map_path())
    add_child(map)
    _spawns = map.get_meta("spawns")
    stats["map"] = GameConfig.map_id
    for z in CaptureZone.from_map(map):   # visual only: not wired to the bus; capture events come from the host
        add_child(z)
    for hi in info.heroes:
        _client_spawn(hi, map)
    Net.hero_spawned.connect(func(hi): _client_spawn(hi, map))
    if player == null:
        push_error("NET welcome without our hero")
        return
    hud = Hud.new()
    add_child(hud)
    hud.setup(player)
    hud.match_end.play_again.connect(func(): _restart(false))
    hud.match_end.main_menu.connect(func(): _restart(false))
    menu = PauseMenu.new()
    add_child(menu)
    Events.match_ended.connect(_on_match_ended)
    Events.damage_dealt.connect(_on_dmg)
    Events.killed.connect(_on_kill)
    _hook_net_dump()
    if not args.has("autopilot"):
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _t0 = Time.get_ticks_msec()

func _client_spawn(hi: Dictionary, map: Node3D) -> void:
    var id := int(hi.id)
    if Net.entities.has(id):
        return
    var h := Hero.from_def(GameConfig.hero_path(String(hi.hero_id)))
    h.display_name = String(hi.name)
    h.set_team(int(hi.team))
    add_child(h)
    h.global_position = hi.pos
    h.yaw = float(hi.yaw)
    h.rotation.y = h.yaw
    Net.register_as(h, id)
    if id == Net.my_net_id:
        player = h
        h.display_name = "You (%s)" % h.def.get("name", hi.hero_id)
        h.net_role = "predicted"
        var rig := CameraRig.new()
        h.add_child(rig)
        rig.setup(h)
        var src = Actions
        if args.has("autopilot"):
            src = BotBrain.new({"difficulty": "hard", "use_abilities": true, "seek_cover": false, "escort_allies": false, "bounds": float(map.get_meta("bounds"))})
        else:
            h.aim_camera = rig.cam
        h.input_source = ClientInput.new(src)
        stats["hero"] = String(hi.hero_id)
    else:
        h.net_role = "puppet"

# ---------------------------------------------------------------- net test dump (tools/net_test.sh)
func _hook_net_dump() -> void:
    if not args.has("net_test"):
        return
    var idof := func(n): return int(n.net_id) if is_instance_valid(n) and n is Hero else -1
    Events.killed.connect(func(ev):
        if _dump_open and (Net.is_client() or not Net.peers.is_empty()):
            _dump.kills.append([idof.call(ev.killer), idof.call(ev.victim), String(ev.kind), String(ev.get("ability_id", "?"))]))
    Events.damage_dealt.connect(func(ev):
        if is_instance_valid(ev.source) and ev.source is Hero and ev.source.has_meta("peer"):
            _dump.remote_dmg += float(ev.amount))
    Events.match_ended.connect(func(ev):
        _dump_open = false
        _dump.match_ended = {"winner_team": ev.winner_team, "reason": ev.reason, "mode": ev.get("mode", "")})

func _net_dump() -> void:
    if _dumped:
        return
    _dumped = true
    var d := _dump.duplicate()
    d["role"] = "client" if Net.is_client() else "host"
    if Net.is_client():
        d["server_tick"] = Net.server_tick
        d["hp"] = Net.last_snap_hp
        d["me"] = Net.my_net_id
        d["reconciles"] = Net.reconciles
        d["max_correction"] = snappedf(Net.max_correction, 0.001)
        d["teleports"] = Net.teleports
        d["max_teleport"] = snappedf(Net.max_teleport, 0.01)
        d["big_corrections"] = Net.big_corrections
        d["deaths"] = stats.deaths
        d["sent"] = player.input_source.sent if player and player.input_source is ClientInput else 0
    else:
        var log := {}
        for e in Net.snap_log:
            log[str(e[0])] = e[1]
        d["snap_hp"] = log
        d["peers"] = Net.peers.size()
        var recv := 0
        for pid in Net.peers:
            if is_instance_valid(Net.peers[pid].hero):
                recv += Net.peers[pid].hero.input_source.received
        d["inputs_received"] = recv
    print("NETDUMP ", JSON.stringify(d))
