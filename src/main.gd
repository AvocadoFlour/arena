extends Node3D
## Composition root: builds map, heroes, HUD and menu. Handles command-line modes:
##   -- --demo            scripted autopilot (moves, looks, fires, dashes, slams, ults)
##   -- --smoke=SECONDS   run demo, print stats, exit 0 (pass) or 1 (fail)
##   -- --screenshot=PATH --delay=S [--menu]   save a PNG after S seconds and quit

const HERO := "res://src/heroes/kestrel.json"
const MAP := "res://src/maps/arena01.json"
var player: Hero
var hud: Hud
var menu: PauseMenu
var args := {}
var stats := {"player_dmg": 0.0, "bot_dmg": 0.0, "kills": 0, "deaths": 0, "dash": 0, "slam": 0, "nova": 0, "slam_hits": 0, "ult_hits": 0}
var _t0 := 0
var _shot_done := false

func _ready() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--"):
            var kv := a.substr(2).split("=", true, 1)
            args[kv[0]] = kv[1] if kv.size() > 1 else "1"
    var demo := args.has("demo") or args.has("smoke") or args.has("screenshot")
    var map := MapLoader.build(MAP)
    add_child(map)
    var spawns: Dictionary = map.get_meta("spawns")
    player = Hero.from_def(HERO)
    player.display_name = "You (Kestrel)"
    player.set_team(0)
    player.spawn_point = spawns[0][0]
    add_child(player)
    player.global_position = player.spawn_point
    var rig := CameraRig.new()
    player.add_child(rig)
    rig.setup(player)
    if demo:
        player.input_source = BotBrain.new({"use_abilities": true, "turn_rate": 6.0, "fire_cone": 0.08})
    else:
        player.input_source = Actions
        player.aim_camera = rig.cam
    for i in 3:
        var b := Hero.from_def(HERO)
        b.display_name = "Bot %d" % (i + 1)
        b.set_team(1)
        b.damage_scale = 0.3
        var brain := BotBrain.new({"bounds": float(map.get_meta("bounds"))})
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
    Events.ability_used.connect(func(h, _s, id): if h == player: stats[id] = stats.get(id, 0) + 1)
    if args.has("menu"):
        menu.visible = true
    elif not demo:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _t0 = Time.get_ticks_msec()

func _on_dmg(ev: Dictionary) -> void:
    if ev.source == player:
        stats.player_dmg += ev.amount
        if ev.kind == "slam":
            stats.slam_hits += 1
        if ev.kind == "ultimate":
            stats.ult_hits += 1
    elif ev.target == player:
        stats.bot_dmg += ev.amount

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

func _process(_dt: float) -> void:
    var el := (Time.get_ticks_msec() - _t0) / 1000.0
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
    var ok: bool = stats.player_dmg > 0 and stats.bot_dmg > 0 and stats.kills > 0
    if args.has("smoke"):
        print("SMOKE ", "PASS" if ok else "FAIL")
    get_tree().quit(0 if ok or not args.has("smoke") else 1)
