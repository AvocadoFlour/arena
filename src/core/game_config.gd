extends Node
## Match configuration (autoload "GameConfig"). Contract: INTERFACES.md section 8.
## Set by command line now (-- --hero=ID --map=ID --bots=easy|normal|hard), by a hero-select UI later.

const HERO_DIR := "res://src/heroes"
const MAP_DIR := "res://src/maps"
const DIFFICULTY := {
    "easy":   {"spread_deg": 9.0, "turn_rate": 3.0, "damage_scale": 0.2},
    "normal": {"spread_deg": 6.0, "turn_rate": 4.0, "damage_scale": 0.3},
    "hard":   {"spread_deg": 3.5, "turn_rate": 6.0, "damage_scale": 0.45},
}
signal changed

var hero_id := "kestrel"
var map_id := "arena01"
var bot_difficulty := "normal"
var bot_count := 3

func _ready() -> void:
    for a in OS.get_cmdline_user_args():
        var kv := a.trim_prefix("--").split("=", true, 1)
        if kv.size() < 2:
            continue
        match kv[0]:
            "hero": set_hero(kv[1])
            "map": map_id = kv[1]
            "bots": bot_difficulty = kv[1] if DIFFICULTY.has(kv[1]) else "normal"

## Sorted ids of every hero definition (src/heroes/*.json).
func hero_ids() -> Array:
    var out: Array = []
    for f in DirAccess.get_files_at(HERO_DIR):
        if f.ends_with(".json"):
            out.append(f.get_basename())
    out.sort()
    return out

func hero_path(id: String) -> String:
    return "%s/%s.json" % [HERO_DIR, id]

func map_path() -> String:
    return "%s/%s.json" % [MAP_DIR, map_id]

## Returns false (and keeps the old value) for unknown ids.
func set_hero(id: String) -> bool:
    if not hero_ids().has(id):
        push_warning("unknown hero id " + id)
        return false
    hero_id = id
    changed.emit()
    return true

func difficulty() -> Dictionary:
    return DIFFICULTY.get(bot_difficulty, DIFFICULTY.normal)
