extends Node3D
## AI integration: the support bot (heal_beam hero, Twin Tails) heals allies that need it.
## A: a hurt ally 27 m away (out of beam range) -> support walks over and heals it.
## B: 3v2 skirmish on arena02 (support + Cob + The Best vs 2 enemy bots), bots spawned like
##    main.gd does (plain BotBrain, team 0 allies) -> allies receive beam healing; no ally is left
##    below 50 % HP within reach for > 4 s while the beam is ready.
const SUPPORT := "res://src/heroes/twin_tails.json"
var results: Array = []
var done := false
var frame := 0
var run_seed := -1
var map: Node3D
var phase := 1
var healer: Hero
var beam
var far_ally: Hero
var far_hp0 := 0.0
var allies: Array = []
var ally_heal := 0.0
var neglect := 0.0
var worst_neglect := 0.0
var _prev_hp := {}
var hurt_events: Array = []
var min_frac := 1.0
var responded := ""
var chan_frames := 0
var chan_ally_frames := 0
var support_frames := 0

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _hero(path: String, team: int, pos: Vector3, brain := true) -> Hero:
    var h := Hero.from_def(path)
    h.set_team(team)
    h.spawn_point = pos
    add_child(h)
    h.global_position = pos
    if run_seed >= 0:
        h._rng.seed = hash([run_seed, pos, "h"])
    if brain:
        var b := BotBrain.new({"bounds": float(map.get_meta("bounds"))})
        h.input_source = b
        h.extra_spread_deg = b.spread_deg
        if run_seed >= 0:
            b._rng.seed = hash([run_seed, pos])
    return h

func _load(path: String) -> void:
    if map:
        for c in get_children():
            c.queue_free()
    map = MapLoader.build(path)
    add_child(map)

func _ready() -> void:
    _load("res://src/maps/arena01.json")
    healer = _hero(SUPPORT, 0, Vector3(15, 0.2, 15))
    healer.input_source.escort_allies = false   # like the smoke/demo autopilot: no idle escorting, must seek the hurt ally itself
    beam = healer.abilities["ability1"]
    far_ally = _hero("res://src/heroes/cob.json", 0, Vector3(-8, 0.2, 0), false)
    far_ally.health.hp = far_ally.health.max_hp * 0.4
    far_hp0 = far_ally.health.hp

func _start_b() -> void:
    _load("res://src/maps/arena02.json")
    var sp: Dictionary = map.get_meta("spawns")
    healer = _hero(SUPPORT, 0, sp[0][0])
    beam = healer.abilities["ability1"]
    allies = [_hero("res://src/heroes/cob.json", 0, sp[0][1 % sp[0].size()]), _hero("res://src/heroes/the_best.json", 0, sp[0][2 % sp[0].size()])]
    for i in 2:
        var e := _hero(["res://src/heroes/cob.json", "res://src/heroes/the_best.json"][i], 1, sp[1][i % sp[1].size()])
        e.damage_scale = 0.3
    for a in allies:
        _prev_hp[a] = a.health.hp

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if phase == 1:
        if frame == 360:
            _rec("support_walks_to_and_heals_far_ally", far_ally.health.hp >= far_hp0 + 60.0, "hp %.0f -> %.0f (ally 27 m away, beam range 15)" % [far_hp0, far_ally.health.hp])
            phase = 2
            frame = 0
            _start_b()
        return
    for a in allies:
        var hp: float = a.health.hp
        if beam.channeling() and beam.target == a and hp > _prev_hp[a]:
            ally_heal += hp - _prev_hp[a]
        _prev_hp[a] = hp
    for a in allies:
        min_frac = minf(min_frac, a.health.hp / a.health.max_hp)
    if beam.channeling():
        chan_frames += 1
        if beam.target in allies:
            chan_ally_frames += 1
    if healer.input_source.state == "support":
        support_frames += 1
    if frame == 180 or frame == 660:   # incoming burst on an ally (seeded pick): it now "needs it"
        var rng := RandomNumberGenerator.new()
        rng.seed = hash([run_seed, frame])
        var a: Hero = allies[rng.randi() % allies.size()]
        if not a.dead:
            a.take_damage(a.health.hp * 0.55, null, a.global_position, "primary")
            _prev_hp[a] = a.health.hp
            hurt_events.append([frame, a, ally_heal])
    for ev in hurt_events:
        if ev.size() == 3 and frame == ev[0] + 420:   # 7 s later: was this ally healed by the beam?
            ev.append(ally_heal - float(ev[2]))
    var needy := false
    if not healer.dead and beam.can_activate() and healer.health.hp >= healer.health.max_hp * 0.35:
        for a in allies:
            if not a.dead and a.health.hp < a.health.max_hp * 0.5 and healer.global_position.distance_to(a.global_position) < 35.0:
                needy = true
    neglect = neglect + 1.0 / 60.0 if needy else 0.0
    worst_neglect = maxf(worst_neglect, neglect)
    if frame == 1200:
        _rec("allies_receive_beam_healing", ally_heal > 0.0, "ally heal %.0f HP in 20 s (ally min %.0f%%, beam %d f, on ally %d f, support state %d f)" % [ally_heal, min_frac * 100, chan_frames, chan_ally_frames, support_frames])
        var answered := 0
        for ev in hurt_events:
            if ev.size() == 4 and ev[3] > 0.0:
                answered += 1
        responded = "%d/%d" % [answered, hurt_events.size()]
        _rec("support_answers_each_hurt_ally", answered == hurt_events.size() and hurt_events.size() > 0, "healed within 7 s: %s" % responded)
        _rec("no_hurt_ally_neglected", worst_neglect <= 4.0, "longest ready-but-not-healing %.1f s" % worst_neglect)
        done = true
