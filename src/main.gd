extends Node3D
## Composition root: builds map, heroes, HUD and menu. Handles command-line modes:
##   -- --demo            scripted autopilot (moves, looks, fires, dashes, slams, ults)
##   -- --smoke=SECONDS   run demo, print stats, exit 0 (pass) or 1 (fail)
##   -- --screenshot=PATH --delay=S [--menu] [--use=SLOT --use_lead=S]   save a PNG after S seconds and quit
##   -- --hero=ID --map=ID --bots=easy|normal|hard   (GameConfig)

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
var _forced_check := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS   # screenshot/smoke timers keep running while paused
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--"):
            var kv := a.substr(2).split("=", true, 1)
            args[kv[0]] = kv[1] if kv.size() > 1 else "1"
    if _test_mode() or args.has("menu") or GameConfig.skip_menu_once:
        GameConfig.skip_menu_once = false
        _start_match()
    else:
        _show_main_menu()

## Any test/automation flag bypasses the main menu.
func _test_mode() -> bool:
    for k in ["demo", "smoke", "screenshot", "hero", "map"]:
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
    if args.has("ui_screen"):
        main_menu.show_screen(args.ui_screen)
    _t0 = Time.get_ticks_msec()

func _start_match() -> void:
    var demo := args.has("demo") or args.has("smoke") or args.has("screenshot")
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
    for c in get_children():
        if c != menu:
            c.process_mode = Node.PROCESS_MODE_PAUSABLE
    if args.has("menu"):
        menu.open()
    elif not demo:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _t0 = Time.get_ticks_msec()

func _on_dmg(ev: Dictionary) -> void:
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
    return b

func _restart(skip_menu: bool) -> void:
    GameConfig.skip_menu_once = skip_menu
    get_tree().paused = false
    Actions.gameplay_enabled = true
    get_tree().reload_current_scene()

func _on_kill(ev: Dictionary) -> void:
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
    if args.has("smoke") and not _forced_check and el >= float(args.smoke) * 0.6:
        _forced_check = true   # autopilot policy (src/ai) may skip situational abilities: exercise them anyway
        for slot in ["ability1", "ability2", "ultimate"]:
            if stats.get(slot, 0) == 0 and player.abilities.has(slot) and not player.dead:
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
    var ok: bool = stats.player_dmg > 0 and stats.bot_dmg > 0 and stats.kills > 0 and stats.get("match_ended", 0) == 1 and stats.ability1 > 0 and stats.ability2 > 0 and stats.ultimate > 0
    if args.has("smoke"):
        print("SMOKE ", "PASS" if ok else "FAIL")
    get_tree().quit(0 if ok or not args.has("smoke") else 1)
