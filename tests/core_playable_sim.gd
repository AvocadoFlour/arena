extends Node3D
## Lead gate: EVERY src/heroes/*.json and src/maps/*.json must be playable (UI lists all of them).
## Heroes: valid def, 3 ability slots with registered types, weapon, spawns and stands on arena01.
## Maps: builds, has team 0 and 1 spawns, every hero spawned at a team spawn lands (no fall-through).
var results: Array = []
var done := false
var frame := 0
var queue: Array = []
var map: Node3D
var spawned: Array = []

func _rec(n: String, ok: bool, info: String) -> void:
    results.append([n, ok, info])

func _ready() -> void:
    for f in DirAccess.get_files_at("res://src/heroes"):
        if f.ends_with(".json"):
            var p := "res://src/heroes/" + f
            var d = JSON.parse_string(FileAccess.get_file_as_string(p))
            var ok: bool = d is Dictionary and d.has("id") and d.get("id") == f.get_basename()
            var info := ""
            if ok:
                for slot in ["ability1", "ability2", "ultimate"]:
                    var a = d.get("abilities", {}).get(slot)
                    if a == null or not AbilityRegistry.TYPES.has(String(a.get("type", ""))):
                        ok = false
                        info += "bad %s; " % slot
                ok = ok and d.has("primary") and float(d.get("max_hp", 0)) > 0
            _rec("hero_def_valid_" + f.get_basename(), ok, info)
    for f in DirAccess.get_files_at("res://src/maps"):
        if f.ends_with(".json"):
            queue.append("res://src/maps/" + f)
    _next_map()

func _next_map() -> void:
    for c in get_children():
        c.queue_free()
    spawned = []
    frame = 0
    if queue.is_empty():
        done = true
        return
    var p: String = queue.pop_front()
    map = MapLoader.build(p)
    map.name = "Map_" + p.get_file().get_basename()
    add_child(map)
    var sp: Dictionary = map.get_meta("spawns")
    _rec("map_has_spawns_" + p.get_file().get_basename(), sp.has(0) and sp.has(1) and sp[0].size() > 0 and sp[1].size() > 0, "teams=%s" % [sp.keys()])
    var i := 0
    for f in DirAccess.get_files_at("res://src/heroes"):
        if not f.ends_with(".json"):
            continue
        var h := Hero.from_def("res://src/heroes/" + f)
        var team := i % 2
        h.set_team(team)
        h.input_source = null
        add_child(h)
        var arr: Array = sp.get(team, [Vector3.ZERO])
        h.global_position = arr[(i / 2) % arr.size()]
        spawned.append([p.get_file().get_basename(), f.get_basename(), h])
        i += 1

func _physics_process(_dt: float) -> void:
    if done:
        return
    frame += 1
    if frame == 90:
        for s in spawned:
            var h: Hero = s[2]
            _rec("playable_%s_%s" % [s[0], s[1]], h.is_on_floor() and h.global_position.y > -1.0 and not h.dead, "pos=%s" % h.global_position)
        _next_map()
