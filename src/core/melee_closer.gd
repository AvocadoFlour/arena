class_name MeleeCloser
extends RefCounted
## TEMPORARY core shim (v0.3) until the AI bot adds melee awareness to BotBrain:
## BotBrain keeps ~10 m stand-off distance, so melee heroes (primary.type == "melee") never hit.
## Wraps a BotBrain input source; when the brain has a target beyond melee range it drives forward.
var brain
var _range := 3.0

func _init(b, hero) -> void:
    brain = b
    _range = float(hero.def.get("primary", {}).get("range", 3.0))

static func wrap(b, hero):
    if String(hero.def.get("primary", {}).get("type", "")) == "melee":
        return MeleeCloser.new(b, hero)
    return b

func poll(h) -> InputFrame:
    var f: InputFrame = brain.poll(h)
    var t = brain.target
    if t != null and is_instance_valid(t) and not t.dead:
        var d: float = h.global_position.distance_to(t.global_position)
        if d > _range * 0.8:
            f.move = Vector2(f.move.x * 0.3, 1.0).limit_length(1.0)
        f.fire = f.fire or d <= _range
    return f

## Pass-throughs used by spawner/tests.
var spread_deg: float:
    get: return brain.spread_deg
var target:
    get: return brain.target
