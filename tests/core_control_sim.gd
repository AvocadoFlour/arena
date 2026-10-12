extends Node3D
## Lead integration: arena02 capture zone wired through Events -> MatchRules -> match_ended.
var results: Array = []
var done := false
var frame := 0
var zone
var rules: MatchRules
var hero: Hero
var got := {"changed": 0, "captured": [], "ended": []}

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _ready() -> void:
    var map := MapLoader.build("res://src/maps/arena02.json")
    add_child(map)
    var zones: Array = CaptureZone.from_map(map)
    _rec("arena02_has_zone", zones.size() == 1, "n=%d" % zones.size())
    for z in zones:
        add_child(z)
        z.state_changed.connect(Events.zone_changed.emit)
        z.captured.connect(Events.zone_captured.emit)
        z.contested_changed.connect(Events.zone_contested.emit)
    zone = zones[0]
    rules = MatchRules.new()
    add_child(rules)
    rules.setup(zones)
    Events.zone_changed.connect(func(_ev): got.changed += 1)
    Events.zone_captured.connect(func(ev): got.captured.append(ev))
    Events.match_ended.connect(func(ev): got.ended.append(ev))
    hero = Hero.from_def("res://src/heroes/kestrel.json")
    hero.set_team(0)
    add_child(hero)
    hero.global_position = zone.aabb.get_center() + Vector3(0, 1.0, 0)

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if frame == 700:
        _rec("zone_changed_forwarded", got.changed > 0, "events=%d" % got.changed)
        _rec("zone_captured_by_team0", got.captured.size() == 1 and got.captured[0].team == 0 and zone.owner_team == 0, "%s" % [got.captured])
        _rec("control_score_accrues", rules.scores[0] > 0.5 and rules.scores[1] == 0.0, "scores=%s" % [rules.scores])
        rules.scores[0] = 99.9
    if frame == 760:
        _rec("match_ended_winner_team0", got.ended.size() == 1 and got.ended[0].winner == 0, "%s" % [got.ended])
        done = true
