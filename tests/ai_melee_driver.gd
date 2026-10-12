extends Node3D
## AI integration: a melee hero driven by a plain BotBrain (no core MeleeCloser wrapper) closes
## to weapon range and lands melee hits; a ranged bot keeps its stand-off distance.
const MAP := "res://src/maps/arena01.json"
var results: Array = []
var done := false
var frame := 0
var melee: Hero
var dummy: Hero
var ranged: Hero
var dummy2: Hero
var melee_hits := 0
var min_gap := INF
var min_gap2 := INF

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _hero(path: String, team: int, pos: Vector3) -> Hero:
    var h := Hero.from_def(path)
    h.set_team(team)
    h.spawn_point = pos
    add_child(h)
    h.global_position = pos
    return h

func _ready() -> void:
    add_child(MapLoader.build(MAP))
    melee = _hero("res://src/heroes/the_best.json", 0, Vector3(-12, 0.2, -12))
    var mb := BotBrain.new({"difficulty": "hard", "use_abilities": false, "seek_cover": false, "escort_allies": false})
    melee.input_source = mb
    _rec("brain_not_wrapped", melee.input_source is BotBrain, "input_source is a plain BotBrain")
    dummy = _hero("res://src/heroes/cob.json", 1, Vector3(-12, 0.2, 0))   # no input source: stands still
    ranged = _hero("res://src/heroes/twin_tails.json", 0, Vector3(-3, 0.2, -16))
    ranged.input_source = BotBrain.new({"difficulty": "hard", "use_abilities": false, "seek_cover": false, "escort_allies": false})
    dummy2 = _hero("res://src/heroes/cob.json", 1, Vector3(-3, 0.2, -3))
    Events.damage_dealt.connect(_on_dmg)

func _on_dmg(ev: Dictionary) -> void:
    if ev.source == melee and ev.kind == "primary":
        melee_hits += 1

func _flat(a: Node3D, b: Node3D) -> float:
    return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    min_gap = minf(min_gap, _flat(melee, dummy))
    min_gap2 = minf(min_gap2, _flat(ranged, dummy2))
    if frame == 360:
        var rng := BotBrain.melee_range(melee)
        _rec("melee_closes_to_weapon_range", min_gap <= rng, "min gap %.2f m, range %.2f" % [min_gap, rng])
        _rec("melee_lands_hits_without_shim", melee_hits >= 3, "hits=%d" % melee_hits)
        var g := _flat(ranged, dummy2)
        var t = ranged.input_source.target
        _rec("ranged_keeps_standoff", g > 6.0, "gap %.2f m, min %.2f, target=%s" % [g, min_gap2, t == dummy2])
        Events.damage_dealt.disconnect(_on_dmg)
        done = true
