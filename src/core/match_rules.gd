class_name MatchRules
extends Node
## Match mode + win condition (INTERFACES.md section 9).
##   "control": every capture zone owned by a team gives that team `rate_per_zone` % per second;
##              first team to 100 % wins -> Events.match_ended. Used when the map has capture zones.
##   "ffa":     deathmatch vs bots, no win condition yet (arena01).

const RATE_PER_ZONE := 1.0   ## percent per second per owned zone
const TARGET := 100.0

var mode := "ffa"
var zones: Array = []         ## CaptureZone nodes (owner_team, -1 = neutral)
var scores := {0: 0.0, 1: 0.0}
var ended := false
var winner := -1
var elapsed := 0.0
var _last_emit := -1.0

func setup(zone_nodes: Array) -> void:
    zones = zone_nodes
    mode = "control" if not zones.is_empty() else "ffa"

## Pure step (unit-tested): owners = owner_team of each zone this tick.
func step(dt: float, owners: Array) -> void:
    if ended or mode != "control":
        return
    elapsed += dt
    for o in owners:
        if o is int and o >= 0:
            scores[o] = minf(TARGET, float(scores.get(o, 0.0)) + RATE_PER_ZONE * dt)
    for t in scores:
        if scores[t] >= TARGET:
            ended = true
            winner = t
            break
    if Engine.get_main_loop() and (ended or floorf(elapsed) != _last_emit):
        _last_emit = floorf(elapsed)
        _emit("match_score", {"mode": mode, "scores": scores.duplicate(), "target": TARGET})
    if ended:
        _emit("match_ended", {"winner": winner, "mode": mode, "scores": scores.duplicate(), "time": elapsed})

func _emit(sig: String, ev: Dictionary) -> void:
    var bus = Engine.get_main_loop().root.get_node_or_null("Events") if Engine.get_main_loop() is SceneTree else null
    if bus:
        bus.emit_signal(sig, ev)

func _physics_process(dt: float) -> void:
    var owners: Array = []
    for z in zones:
        if is_instance_valid(z):
            owners.append(z.owner_team)
    step(dt, owners)
