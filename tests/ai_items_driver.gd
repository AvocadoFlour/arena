extends Node3D
## AI integration: health packs and jump pads (maps MapObjects, INTERFACES §6.x).
## 1 arena01: a hurt bot (no enemies) walks to the nearest pack and is healed.
## 2 arena01: the nearest pack is down for 14 s -> the bot goes to the other pack (respawn timer respected).
## 3 arena01: two hurt teammates side by side do not both go for the same pack (claims).
## 4/5 arena02: only the upper-level pack is up; a hurt bot next to the jump pad reaches it faster with pad
##    links (4) than without (5, use_pads off, fresh map).
## 6/7 arena02: low-HP bot beside the pad with an enemy shooter: escapes over the pad (6) and takes less
##    damage over 4 s than the same seed with pads off (7). Single runs are noisy; tests/ai_items_run.gd
##    compares over seeds.
const BOT := "res://src/heroes/tomo.json"
const SHOOTER := "res://src/heroes/twin_tails.json"
var results: Array = []
var done := false
var frame := 0
var run_seed := -1
var phase := 1
var map: Node3D
var objs
var bots: Array = []
var enemy: Hero
var heal_frames := {}       ## phase -> frames until the first pack heal (-1 none)
var first_pack := {}        ## phase -> [pack id per bot]
var launched := {}          ## phase -> pad launches of our bots
var taken := {6: 0.0, 7: 0.0}
var upper := {6: false, 7: false}

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _seed() -> int:
    return run_seed if run_seed >= 0 else 4242

func _hero(path: String, team: int, pos: Vector3, yaw: float) -> Hero:
    var h := Hero.from_def(path)
    h.set_team(team)
    add_child(h)
    h.global_position = pos
    h.spawn_point = pos
    h.yaw = yaw
    h._rng.seed = hash([_seed(), path, team, pos])
    return h

func _bot(pos: Vector3, frac: float, p := {}) -> Hero:
    var h := _hero(BOT, 0, pos, 0.0)
    var cfg := {"difficulty": "normal", "use_abilities": false, "escort_allies": false, "team_play": false, "bounds": 30.0}
    cfg.merge(p, true)
    var b := BotBrain.new(cfg)
    b._rng.seed = hash([_seed(), phase, bots.size()])
    h.input_source = b
    h.health.hp = h.health.max_hp * frac
    bots.append(h)
    return h

func _load(m: String) -> void:
    for c in get_children():
        c.queue_free()
    bots.clear()
    enemy = null
    BotItems.reset()
    map = MapLoader.build("res://src/maps/%s.json" % m)
    add_child(map)
    objs = BotItems.objects(map)
    objs.authority_override = 1
    objs.pad_launched.connect(func(ev): if ev.hero in bots: launched[phase] = launched.get(phase, 0) + 1)
    objs.pickup_taken.connect(func(ev): if ev.hero in bots and heal_frames.get(phase, -1) < 0: heal_frames[phase] = frame)

func _down(ids: Array, left: float) -> void:
    for i in ids:
        objs.pickups[i].active = false
        objs.pickups[i].left = left
        objs.pickups[i].node.visible = false

func _start() -> void:
    frame = 0
    heal_frames[phase] = -1
    match phase:
        1:
            _load("arena01")
            _bot(Vector3(-11, 0.2, 0), 0.4)
        2:
            _load("arena01")
            _down([0], 14.0)
            _bot(Vector3(-11, 0.2, 0), 0.4)
        3:
            _load("arena01")
            _bot(Vector3(-11, 0.2, 1.5), 0.4)
            _bot(Vector3(-11, 0.2, -1.5), 0.4)
        4, 5:
            _load("arena02")
            _down([1, 2, 3], 120.0)
            _bot(Vector3(-20, 0.2, -14), 0.4, {"use_pads": phase == 4})
        6, 7:
            _load("arena02")
            _down([0, 1, 2, 3], 120.0)   # no packs: this is about the escape
            _bot(Vector3(-21, 0.2, -14), 0.3, {"use_pads": phase == 6, "use_packs": false})
            enemy = _hero(SHOOTER, 1, Vector3(-12, 0.2, -22), 0.0)
            var eb := BotBrain.new({"difficulty": "normal", "use_abilities": false, "escort_allies": false, "team_play": false, "seek_cover": false, "use_packs": false, "bounds": 30.0})
            eb._rng.seed = hash([_seed(), phase, "e"])
            enemy.input_source = eb
            enemy.extra_spread_deg = eb.spread_deg
            enemy.damage_scale = 0.4

func _ready() -> void:
    Events.damage_dealt.connect(_on_dmg)
    _start()

func _on_dmg(ev: Dictionary) -> void:
    if phase in [6, 7] and frame <= 240 and bots.size() > 0 and ev.target == bots[0]:
        taken[phase] += ev.amount

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if not first_pack.has(phase) and frame <= 60:
        var ids: Array = []
        for b in bots:
            var br: BotBrain = b.input_source
            ids.append(int(br._pack.id) if br._pack != null else -1)
        if not ids.has(-1) or frame == 60:
            first_pack[phase] = ids
    if phase in [6, 7] and bots.size() > 0 and bots[0].global_position.y > 3.0 and frame <= 240:
        upper[phase] = true
    if OS.get_environment("AI_DEBUG") != "" and frame % 20 == 0 and phase in [4, 5, 6] and bots.size() > 0:
        var br: BotBrain = bots[0].input_source
        print("ph%d f%d pos %s vel %s state %s path %s" % [phase, frame, bots[0].global_position.snapped(Vector3(0.1, 0.1, 0.1)), bots[0].velocity.snapped(Vector3(0.1, 0.1, 0.1)), br.state, br._path.slice(br._path_i, br._path_i + 3)])
    var limit: int = {1: 600, 2: 900, 3: 900, 4: 900, 5: 900, 6: 240, 7: 240}[phase]
    if frame < limit and not (phase in [1, 2, 4, 5] and heal_frames[phase] >= 0):
        return
    match phase:
        1:
            _rec("hurt_bot_takes_nearest_pack", heal_frames[1] > 0 and first_pack.get(1) == [0], "healed at frame %d, first pack %s" % [heal_frames[1], first_pack.get(1)])
        2:
            _rec("respects_respawn_timer", heal_frames[2] > 0 and first_pack[2] == [1], "near pack down 14 s: first pack %s, healed at frame %d" % [first_pack[2], heal_frames[2]])
        3:
            var ids: Array = first_pack[3]
            _rec("teammates_split_packs", ids.size() == 2 and ids[0] != ids[1], "packs %s" % [ids])
        5:
            var a: int = heal_frames[4]
            var b: int = heal_frames[5]
            _rec("pad_route_to_upper_pack", a > 0 and launched.get(4, 0) >= 1 and (b < 0 or a < b), "with pads healed at frame %d (launches %d), without %d" % [a, launched.get(4, 0), b])
        7:
            _rec("low_hp_escape_over_pad", upper[6] and launched.get(6, 0) >= 1 and launched.get(7, 0) == 0, "reached the ledge %s (launches %d), control launches %d; damage taken %.0f vs control %.0f" % [upper[6], launched.get(6, 0), launched.get(7, 0), taken[6], taken[7]])
    if phase >= 7:
        Events.damage_dealt.disconnect(_on_dmg)
        done = true
        return
    phase += 1
    _start()
