class_name CaptureZone
extends Node
## Capture-point logic, driven by a map JSON zone entry (INTERFACES.md §6 "zones").
## Pure state machine in `step(dt, counts)`; `_physics_process` feeds it live hero counts
## (group "heroes", alive, inside the zone AABB). Gameplay state only changes in physics ticks.
##
## Zone JSON keys (all optional except id/pos/size):
##   capture_time  s for ONE player to capture from neutral (default 8)
##   player_scale  rate multiplier by player count, last entry = cap (default [1, 1.5, 2])
##   decay_rate    progress lost per s when the zone is empty (default 0.1)
##   revert_rate   multiplier when undoing an enemy's partial progress (default 1)
## Rules: contested (>= 2 teams present) -> progress pauses. One team present: first undoes
## another team's partial progress, then captures. Owner on its own zone also undoes enemy progress.
## Empty -> progress decays towards 0. Reaching 1.0 sets owner; progress resets to 0.
##
## Signals (Dictionary payloads like Events):
##   state_changed({zone, owner, capturing_team, progress, contested})  on any change
##   captured({zone, team, previous})                                    on ownership change
##   contested_changed({zone, contested})

signal state_changed(ev: Dictionary)
signal captured(ev: Dictionary)
signal contested_changed(ev: Dictionary)

const NEUTRAL := -1

var zone_id := ""
var aabb := AABB()
var capture_time := 8.0
var player_scale: Array = [1.0, 1.5, 2.0]
var decay_rate := 0.1
var revert_rate := 1.0

var owner_team := NEUTRAL
var capturing_team := NEUTRAL
var progress := 0.0
var contested := false

static func from_def(z: Dictionary) -> CaptureZone:
    var c := CaptureZone.new()
    c.zone_id = String(z.get("id", ""))
    var pos = z.pos
    var size = z.size
    if pos is Array:
        pos = Vector3(pos[0], pos[1], pos[2])
    if size is Array:
        size = Vector3(size[0], size[1], size[2])
    c.aabb = AABB(pos - size * 0.5, size)
    c.name = "Zone_" + c.zone_id
    c.capture_time = maxf(0.01, float(z.get("capture_time", 8.0)))
    c.player_scale = z.get("player_scale", [1.0, 1.5, 2.0])
    c.decay_rate = float(z.get("decay_rate", 0.1))
    c.revert_rate = float(z.get("revert_rate", 1.0))
    return c

## Builds a CaptureZone for every capture zone in MapLoader's `zones` meta.
static func from_map(map: Node3D) -> Array:
    var out: Array = []
    for z in map.get_meta("zones", []):
        if z.get("kind", "capture") == "capture":
            out.append(from_def(z))
    return out

func rate_for(n: int) -> float:
    if n <= 0 or player_scale.is_empty():
        return 0.0
    return float(player_scale[mini(n, player_scale.size()) - 1]) / capture_time

## counts: Dictionary team(int) -> alive players inside.
func step(dt: float, counts: Dictionary) -> void:
    var before := [owner_team, capturing_team, snappedf(progress, 0.0001), contested]
    var present: Array = []
    for t in counts:
        if counts[t] > 0:
            present.append(t)
    var now_contested := present.size() >= 2
    if now_contested != contested:
        contested = now_contested
        contested_changed.emit({"zone": zone_id, "contested": contested})
    if contested:
        pass
    elif present.is_empty():
        progress = maxf(0.0, progress - decay_rate * dt)
    else:
        var t: int = present[0]
        var r := rate_for(counts[t]) * dt
        if capturing_team != NEUTRAL and capturing_team != t and progress > 0.0:
            progress = maxf(0.0, progress - r * revert_rate)
        elif t != owner_team:
            capturing_team = t
            progress += r
            if progress >= 1.0:
                var prev := owner_team
                owner_team = t
                progress = 0.0
                capturing_team = NEUTRAL
                captured.emit({"zone": zone_id, "team": t, "previous": prev})
    if progress <= 0.0 and not contested:
        progress = 0.0
        capturing_team = NEUTRAL
    if before != [owner_team, capturing_team, snappedf(progress, 0.0001), contested]:
        state_changed.emit(state())

func state() -> Dictionary:
    return {"zone": zone_id, "owner": owner_team, "capturing_team": capturing_team,
        "progress": progress, "contested": contested}

## Counts alive heroes (objects with team, dead, global_position) inside the zone.
func count(heroes: Array) -> Dictionary:
    var c := {}
    for h in heroes:
        if h.dead:
            continue
        if aabb.has_point(h.global_position + Vector3(0, 0.1, 0)):
            c[h.team] = c.get(h.team, 0) + 1
    return c

func _physics_process(dt: float) -> void:
    step(dt, count(get_tree().get_nodes_in_group("heroes")))
