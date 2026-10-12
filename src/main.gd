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

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS   # screenshot/smoke timers keep running while paused
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--"):
            var kv := a.substr(2).split("=", true, 1)
            args[kv[0]] = kv[1] if kv.size() > 1 else "1"
    var demo := args.has("demo") or args.has("smoke") or args.has("screenshot")
    var map := MapLoader.build(GameConfig.map_path())
    add_child(map)
    var spawns: Dictionary = map.get_meta("spawns")
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
        player.input_source = BotBrain.new({"use_abilities": true, "turn_rate": 6.0, "fire_cone": 0.08, "bounds": float(map.get_meta("bounds"))})
    else:
        player.input_source = Actions
        player.aim_camera = rig.cam
    var roster: Array = GameConfig.hero_ids()   # mixed bot roster: cycle through all heroes
    var diff: Dictionary = GameConfig.difficulty()
    stats["bots"] = []
    for i in GameConfig.bot_count:
        var bid: String = roster[i % roster.size()]
        var b := Hero.from_def(GameConfig.hero_path(bid))
        b.display_name = "Bot %d (%s)" % [i + 1, b.def.get("name", bid)]
        stats.bots.append(bid)
        b.set_team(1)
        b.damage_scale = diff.damage_scale
        var brain := BotBrain.new({"bounds": float(map.get_meta("bounds")), "spread_deg": diff.spread_deg, "turn_rate": diff.turn_rate})
        b.input_source = brain
        b.extra_spread_deg = brain.spread_deg
        b.spawn_point = spawns[1][i % spawns[1].size()]
        add_child(b)
        b.global_position = b.spawn_point
        b.yaw = PI
    hud = Hud.new()
    add_child(hud)
    hud.setup(player)
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

func _on_kill(ev: Dictionary) -> void:
    if ev.killer == player:
        stats.kills += 1
    if ev.victim == player:
        stats.deaths += 1

func _unhandled_input(event: InputEvent) -> void:
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
    if args.has("use") and not _used and el >= float(args.get("delay", "6")) - float(args.get("use_lead", "0.3")):
        _used = true   # test hook: force an ability right before the screenshot
        player._use(args.use)
    if args.has("screenshot") and not _shot_done and el >= float(args.get("delay", "6")):
        _shot_done = true
        get_viewport().get_texture().get_image().save_png(args.screenshot)
        print("SCREENSHOT ", args.screenshot, " ", get_viewport().get_visible_rect().size)
        _finish()
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
    var ok: bool = stats.player_dmg > 0 and stats.bot_dmg > 0 and stats.kills > 0 and stats.ability1 > 0 and stats.ability2 > 0 and stats.ultimate > 0
    if args.has("smoke"):
        print("SMOKE ", "PASS" if ok else "FAIL")
    get_tree().quit(0 if ok or not args.has("smoke") else 1)
