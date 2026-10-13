extends Node3D
## AI integration (arena01): low-health ranged bot vs an enemy shooter. Phase A with cover seeking:
## reaches cover, is out of the enemy's sight while hiding, peeks (lands hits), ducks back.
## Phase B (control, same seed, seek_cover off): takes more damage over the same 15 s.
const BOT := "res://src/heroes/cob.json"            # ranged hitscan, 550 HP: survives the 15 s duel
const ENEMY := "res://src/heroes/twin_tails.json"
const FRAMES := 900
var results: Array = []
var done := false
var frame := 0
var run_seed := -1
var phase := 1
var map: Node3D
var bot: Hero
var brain: BotBrain
var enemy: Hero
var hp0 := 0.0
var taken := {1: 0.0, 2: 0.0}
var dealt := 0.0
var peek_dealt := 0.0
var hide_frames := 0
var hide_seen := 0
var reached_hide := -1
var back_in_cover := false
var deaths := 0
var phases_seen := {}

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _setup(cover: bool) -> void:
    for c in get_children():
        c.queue_free()
    map = MapLoader.build("res://src/maps/arena01.json")
    add_child(map)
    var s := run_seed if run_seed >= 0 else 4242
    bot = Hero.from_def(BOT)
    bot.set_team(0)
    add_child(bot)
    bot.global_position = Vector3(-10, 0.2, 2)
    bot.spawn_point = bot.global_position
    bot.yaw = PI
    # low_hp_frac 1.01: treated as "low" from full HP, so it survives a 15 s duel at a realistic damage scale
    brain = BotBrain.new({"difficulty": "hard", "use_abilities": false, "escort_allies": false, "seek_cover": cover, "bounds": 17.0, "low_hp_frac": 1.01})
    bot.input_source = brain
    bot.extra_spread_deg = brain.spread_deg
    hp0 = bot.health.hp
    enemy = Hero.from_def(ENEMY)
    enemy.set_team(1)
    add_child(enemy)
    enemy.global_position = Vector3(-8, 0.2, -12)
    enemy.spawn_point = enemy.global_position
    enemy.damage_scale = 0.5
    var eb := BotBrain.new({"difficulty": "hard", "use_abilities": false, "escort_allies": false, "seek_cover": false, "bounds": 17.0})
    enemy.input_source = eb
    enemy.extra_spread_deg = eb.spread_deg
    bot._rng.seed = hash([s, "bot"])
    enemy._rng.seed = hash([s, "enemy"])
    brain._rng.seed = hash([s, "brain"])
    eb._rng.seed = hash([s, "eb"])

func _ready() -> void:
    Events.damage_dealt.connect(_on_dmg)
    _setup(true)

func _on_dmg(ev: Dictionary) -> void:
    if not is_instance_valid(bot) or (ev.target != bot and ev.source != bot):
        return
    if ev.target == bot:
        taken[phase] += ev.amount
        if ev.get("killed", false):
            deaths += 1
    elif phase == 1:
        dealt += ev.amount
        if brain._cphase == "peek":
            peek_dealt += ev.amount

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if phase == 1:
        phases_seen[brain._cphase] = true
        if brain.state == "cover" and brain._cphase == "hide":
            if reached_hide < 0:
                reached_hide = frame
            if brain.peeks > 0:
                back_in_cover = true
            if Vector2(bot.global_position.x - brain._cover.x, bot.global_position.z - brain._cover.z).length() < 0.6:
                hide_frames += 1
                if brain._visible(enemy, bot):
                    hide_seen += 1
        if frame == FRAMES:
            _rec("reaches_cover", reached_hide > 0, "hide from frame %d" % reached_hide)
            var frac := float(hide_seen) / maxf(1.0, float(hide_frames))
            _rec("hidden_while_in_cover", hide_frames > 30 and frac < 0.15, "in-cover frames %d, enemy LOS %.0f%%" % [hide_frames, frac * 100.0])
            _rec("peeks_and_lands_hits", brain.peeks >= 2 and peek_dealt > 0.0, "peeks=%d peek_dmg=%.0f total_dmg=%.0f" % [brain.peeks, peek_dealt, dealt])
            _rec("ducks_back_after_peek", back_in_cover, "")
            phase = 2
            frame = 0
            _setup(false)
    elif frame == FRAMES:
        _rec("less_damage_with_cover", taken[1] < taken[2] * 0.75, "taken with cover %.0f vs without %.0f" % [taken[1], taken[2]])
        Events.damage_dealt.disconnect(_on_dmg)
        done = true
