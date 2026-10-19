extends Node3D
## Replicated on-hit speed bonus ("primary.on_hit_speed", Niđo's Momentum) - net-prop hook (INTERFACES §10), no
## core change. kind = "momentum:<hero net id>". The host's hero owns the node while the bonus runs and sets
## rotation.y = fraction left x FRAC_SCALE every tick (prop snapshots carry position + yaw), position = the hero.
## Clients get it from build_prop(); while it is in the tree it publishes the fraction in a static table read by
## Hero.momentum_frac() (owner prediction + speed trail). Leaving the tree (bonus over / death) clears it. Invisible.
const PATH := "res://src/abilities/momentum_link.gd"
const FRAC_SCALE := 3.0   ## yaw = fraction (0..1) x 3 rad: stays inside -PI..PI
static var _frac := {}    ## hero net id -> fraction left (clients)
var hero_id := -1

static func kind_for(h) -> String:
    return "momentum:%d" % int(h.net_id)

static func build_prop(kind: String, _size: Vector3, _color: Color) -> Node3D:
    var n = load(PATH).new()
    n.name = "MomentumLink"
    var parts := kind.split(":")
    if parts.size() == 2 and parts[0] == "momentum":
        n.hero_id = int(parts[1])
    return n

static func encode(frac: float) -> float:
    return clampf(frac, 0.0, 1.0) * FRAC_SCALE

static func decode(yaw: float) -> float:
    return clampf(yaw / FRAC_SCALE, 0.0, 1.0)

## Fraction left for a hero net id on a client (0 = none).
static func frac_of(net_id: int) -> float:
    return float(_frac.get(net_id, 0.0))

func _process(_dt: float) -> void:
    if hero_id >= 0:
        _frac[hero_id] = decode(rotation.y)

func _exit_tree() -> void:
    if hero_id >= 0:
        _frac.erase(hero_id)
