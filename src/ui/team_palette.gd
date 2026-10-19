class_name TeamPalette
extends RefCounted
## Team colours by relation to the local player, one place for all of them: overhead health bars + names,
## kill feed names + badge rings, score table panels/rows/badges, capture bars.
## self = the local player's own hero, ally = same authoritative team (`hero.team`) in team modes,
## enemy = everyone else; in FFA everyone but the local player is an enemy.
const SELF := Color("#3ea0ff")    ## blue
const ALLY := Color("#3ee07a")    ## green
const ENEMY := Color("#ff4848")   ## red
const OUTLINE := Color(0, 0, 0, 0.9)   ## name text outline (readable on sky, walls and floor)
const OUTLINE_SIZE := 12
const SELF_SCALE := 0.6   ## the local player's own bar is drawn smaller: it is right in front of the third-person camera
const NEUTRAL := Color(0.8, 0.8, 0.8)   ## no hero (World / environment) or neutral zone
const COLORS := {"self": SELF, "ally": ALLY, "enemy": ENEMY}

static func color(rel: String) -> Color:
    return COLORS.get(rel, ENEMY)

## "self" | "ally" | "enemy". `mode` "ffa" makes every other hero an enemy; any other mode compares teams.
static func relation(h, me, mode: String) -> String:
    if h == null or not is_instance_valid(h):
        return "enemy"
    if me != null and is_instance_valid(me) and h == me:
        return "self"
    if mode == "ffa" or me == null or not is_instance_valid(me):
        return "enemy"
    return "ally" if int(h.team) == int(me.team) else "enemy"

## Relation of a whole team (score table panel, capture zone owner) to the local player: "ally" for the local
## player's own team in team modes, else "enemy" (FFA: every team is an enemy; no local player: enemy).
static func team_relation(team: int, me, mode: String) -> String:
    if mode == "ffa" or me == null or not is_instance_valid(me):
        return "enemy"
    return "ally" if team == int(me.team) else "enemy"

## Match mode for a UI node anywhere under the composition root: the nearest ancestor that is the root
## (has `match_mode()`, `rules` or capture-zone children) decides via mode_of(); none found: "ffa".
static func mode_near(n: Node) -> String:
    var a: Node = n
    while a != null:
        if a.has_method("match_mode") or a.get("rules") != null:
            return mode_of(a)
        for c in a.get_children():
            if c is CaptureZone:
                return "control"
        a = a.get_parent()
    return "ffa"

## Match mode seen from any peer: core's `match_mode()` on the composition root when it exists (requested in
## docs/requests/ui.md); else the host/offline `MatchRules.mode`; else (online client: no MatchRules there) "control"
## when the map built capture zones, otherwise "ffa" (INTERFACES §9: control iff the map has zones).
static func mode_of(root: Node) -> String:
    if root == null or not is_instance_valid(root):
        return "ffa"
    if root.has_method("match_mode"):
        return String(root.match_mode())
    var rules = root.get("rules")
    if rules != null and is_instance_valid(rules) and "mode" in rules:
        return String(rules.mode)
    for c in root.get_children():
        if c is CaptureZone:
            return "control"
    return "ffa"
