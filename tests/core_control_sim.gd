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
        ZoneBridge.wire(z)
    zone = zones[0]
    rules = MatchRules.new()
    add_child(rules)
    rules.setup(zones)
    Events.capture_progress.connect(func(ev): got.changed += 1; got["last"] = ev)
    Events.capture_completed.connect(func(ev): got.captured.append(ev))
    Events.match_ended.connect(func(ev): got.ended.append(ev))
    hero = Hero.from_def("res://src/heroes/twin_tails.json")
    hero.set_team(0)
    add_child(hero)
    hero.global_position = zone.aabb.get_center() + Vector3(0, 1.0, 0)

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if frame == 700:
        _rec("capture_progress_throttled_10hz", got.changed > 10 and got.changed <= 120, "events=%d in ~11.7 s" % got.changed)
        _rec("capture_progress_shape", got.has("last") and got.last.has_all(["zone_id", "team", "progress", "contested"]) and got.last.zone_id == "A", "%s" % [got.get("last")])
        _rec("capture_completed_team0", got.captured.size() == 1 and got.captured[0].team == 0 and got.captured[0].zone_id == "A" and zone.owner_team == 0, "%s" % [got.captured])
        _rec("control_score_accrues", rules.scores[0] > 0.5 and rules.scores[1] == 0.0, "scores=%s" % [rules.scores])
        rules.scores[0] = 99.9
    if frame == 760:
        _rec("match_ended_winner_team0", got.ended.size() == 1 and got.ended[0].winner_team == 0 and got.ended[0].reason == "score", "%s" % [got.ended])
        done = true
