class_name BotTeam
extends RefCounted
## Shared team knowledge for bots (host only, src/ai). Per world + team:
##  - enemies seen by any teammate recently -> one shared focus target (lowest HP fraction)
##  - capture zone owners from the Events bus (Events.capture_progress; INTERFACES §4)
## No core hooks needed: zones come from the map root's `zones` meta, owners from the bus.

const SEEN_FRAMES := 30          ## a sighting counts for 0.5 s
static var _boards := {}         ## "world:team" -> {enemy instance id: [enemy, frame]}
static var _owners := {}         ## zone_id -> owner team (-1 neutral)
static var _listener = null

class _Listener:
    func on_progress(ev: Dictionary) -> void:
        BotTeam._owners[String(ev.get("zone_id", ""))] = int(ev.get("owner", -1))
    func on_completed(ev: Dictionary) -> void:
        BotTeam._owners[String(ev.get("zone_id", ""))] = int(ev.get("team", -1))

static func _listen() -> void:
    if _listener != null:
        return
    var ev = Engine.get_main_loop().root.get_node_or_null("Events") if Engine.get_main_loop() else null
    if ev == null:
        return
    _listener = _Listener.new()
    ev.capture_progress.connect(_listener.on_progress)
    ev.capture_completed.connect(_listener.on_completed)

static func _key(h) -> String:
    return "%d:%d" % [h.get_world_3d().get_instance_id(), h.team]

## A bot reports the enemies it can currently see.
static func report(h, visible: Array) -> void:
    _listen()
    var k := _key(h)
    if not _boards.has(k):
        _boards[k] = {}
    var b: Dictionary = _boards[k]
    var fr := Engine.get_physics_frames()
    for e in visible:
        b[e.get_instance_id()] = [e, fr]

## Shared focus target: among enemies any teammate saw in the last SEEN_FRAMES, the one with the
## lowest HP fraction (ties -> nearest to `h`). Null when the team sees nobody.
static func focus(h):
    var b: Dictionary = _boards.get(_key(h), {})
    var fr := Engine.get_physics_frames()
    var best = null
    var best_s := INF
    for id in b.keys():
        var e = b[id][0]
        if not is_instance_valid(e) or e.dead or fr - int(b[id][1]) > SEEN_FRAMES:
            b.erase(id)
            continue
        var s: float = e.health.hp / e.health.max_hp + h.global_position.distance_to(e.global_position) / 1000.0
        if s < best_s:
            best_s = s
            best = e
    return best

static func pick_focus(candidates: Array):   ## pure helper (unit-tested): [{frac, dist}] -> index
    var bi := -1
    var bs := INF
    for i in candidates.size():
        var s: float = float(candidates[i].frac) + float(candidates[i].dist) / 1000.0
        if s < bs:
            bs = s
            bi = i
    return bi

static func zone_owner(zone_id: String) -> int:
    _listen()
    return int(_owners.get(zone_id, -1))

## Living teammates (not self) in the same world.
static func mates(h) -> Array:
    var out: Array = []
    for o in h.get_tree().get_nodes_in_group("heroes"):
        if o != h and not o.dead and o.team == h.team and o.get_world_3d() == h.get_world_3d():
            out.append(o)
    return out

static func is_tank(h) -> bool:
    return String(h.def.get("role", "")) == "tank"

static func reset() -> void:   ## tests
    _boards.clear()
    _owners.clear()
