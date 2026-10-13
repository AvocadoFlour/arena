extends Node3D
## AI integration (arena02, Control): 3v3 bots, one team with team_play, one without; real
## CaptureZone + ZoneBridge (bus events) and 1 %/s per owned zone scoring like MatchRules.
## Measures focus-fire concentration, grouping, tank time on point and the result.
const ROSTER := ["res://src/heroes/cob.json", "res://src/heroes/the_best.json", "res://src/heroes/twin_tails.json"]
var results: Array = []
var done := false
var frame := 0
var run_seed := -1
const GROUP_MARGIN := 1.15
var frames := 2400               ## 40 s in the gate; the bench uses more
var tp_team := 0                 ## which team gets team_play (bench alternates); -1 = both
var diff := {0: "normal", 1: "normal"}   ## difficulty per team (difficulty bench)
var map: Node3D
var zone
var teams := {0: [], 1: []}
var score := {0: 0.0, 1: 0.0}
var kills := {0: 0, 1: 0}
var conc := {0: [0.0, 0], 1: [0.0, 0]}
var group := {0: [0.0, 0], 1: [0.0, 0]}
var tank_on := {0: [0, 0], 1: [0, 0]}
var dmg := {0: 0.0, 1: 0.0}

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _ready() -> void:
    BotTeam.reset()
    map = MapLoader.build("res://src/maps/arena02.json")
    add_child(map)
    var zs: Array = CaptureZone.from_map(map)
    zone = zs[0]
    add_child(zone)
    ZoneBridge.wire(zone)
    var sp: Dictionary = map.get_meta("spawns")
    var s := run_seed if run_seed >= 0 else 4242
    for t in [0, 1]:
        for i in 3:
            var h := Hero.from_def(ROSTER[i])
            h.set_team(t)
            h.damage_scale = 0.5
            var pos: Vector3 = sp[t][i]
            h.spawn_point = pos
            add_child(h)
            h.global_position = pos
            h.yaw = 0.0 if t == 0 else PI
            var b := BotBrain.new({"bounds": float(map.get_meta("bounds")), "team_play": tp_team < 0 or t == tp_team, "difficulty": diff[t]})
            h.input_source = b
            h.extra_spread_deg = b.spread_deg
            h._rng.seed = hash([s, t, i])
            b._rng.seed = hash([s, t, i, "b"])
            teams[t].append(h)
    Events.damage_dealt.connect(_on_dmg)
    Events.killed.connect(_on_kill)

func _on_dmg(ev: Dictionary) -> void:
    if ev.source is Node and is_instance_valid(ev.source) and ev.source.get_parent() == self:
        dmg[ev.source.team] += ev.amount

func _on_kill(ev: Dictionary) -> void:
    if ev.killer is Node and is_instance_valid(ev.killer) and ev.killer.get_parent() == self:
        kills[ev.killer.team] += 1

func _physics_process(dt: float) -> void:
    if done:
        return
    frame += 1
    if zone.owner_team >= 0:
        score[zone.owner_team] += dt
    for t in [0, 1]:
        var tank: Hero = teams[t][0]
        if not tank.dead:
            tank_on[t][1] += 1
            if zone.aabb.has_point(tank.global_position + Vector3(0, 0.1, 0)):
                tank_on[t][0] += 1
        if frame % 30 == 0:
            var tg := {}
            var n := 0
            for h in teams[t]:
                var x = h.input_source.target
                if not h.dead and x != null and is_instance_valid(x):
                    tg[x] = tg.get(x, 0) + 1
                    n += 1
            if n >= 2:
                var mx := 0
                for k in tg:
                    mx = maxi(mx, tg[k])
                conc[t][0] += float(mx) / n
                conc[t][1] += 1
            var alive: Array = teams[t].filter(func(h): return not h.dead)
            if alive.size() >= 2:
                var c := Vector3.ZERO
                for h in alive:
                    c += h.global_position
                c /= alive.size()
                for h in alive:
                    group[t][0] += Vector2(h.global_position.x - c.x, h.global_position.z - c.z).length()
                    group[t][1] += 1
    if frame == frames and tp_team < 0:
        done = true
        return
    if frame == frames:
        var a := tp_team
        var b := 1 - tp_team
        _rec("focus_fire_concentration", m(conc, a) > m(conc, b), "team play %.2f vs %.2f" % [m(conc, a), m(conc, b)])
        # relative to the same-seed no-team-play side (which also clumps around fights); 21-seed bench
        # ratio max 1.11, median 0.86 -> 15 % margin. No absolute metre threshold (hero/collider changes).
        _rec("team_groups_up", m(group, a) <= m(group, b) * GROUP_MARGIN, "mean distance to team centre %.1f m (no team play %.1f m, ratio %.2f)" % [m(group, a), m(group, b), m(group, a) / maxf(0.01, m(group, b))])
        var ton := float(tank_on[a][0]) / maxf(1.0, tank_on[a][1])
        var toff := float(tank_on[b][0]) / maxf(1.0, tank_on[b][1])
        _rec("tank_holds_point", ton >= 0.5 and ton > toff, "tank alive-time on point %.0f%% vs %.0f%%" % [ton * 100, toff * 100])
        _rec("fights_happen", kills[0] + kills[1] > 0 or dmg[0] + dmg[1] > 300.0, "kills %d/%d dmg %.0f/%.0f" % [kills[a], kills[b], dmg[a], dmg[b]])
        Events.damage_dealt.disconnect(_on_dmg)
        Events.killed.disconnect(_on_kill)
        done = true

func m(d: Dictionary, t: int) -> float:
    return d[t][0] / maxf(1.0, float(d[t][1]))

func outcome_for(t: int) -> int:   ## +1 team t won (zone time; tie -> kills), -1 lost, 0 draw
    var a: float = score[t] - score[1 - t]
    if absf(a) < 0.5:
        a = kills[t] - kills[1 - t]
    return 1 if a > 0 else (-1 if a < 0 else 0)

func outcome() -> int:   ## +1 team-play team won (more zone time; tie -> kills), -1 lost, 0 draw
    var a: float = score[tp_team] - score[1 - tp_team]
    if absf(a) < 0.5:
        a = kills[tp_team] - kills[1 - tp_team]
    return 1 if a > 0 else (-1 if a < 0 else 0)
