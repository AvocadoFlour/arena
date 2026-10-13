extends Node
## Match configuration (autoload "GameConfig"). Contract: INTERFACES.md section 8.
## Set by command line now (-- --hero=ID --map=ID --difficulty=easy|normal|hard; --bots= is an alias), by a hero-select UI later.

const HERO_DIR := "res://src/heroes"
const MAP_DIR := "res://src/maps"
## Aim/reaction presets live in BotBrain.DIFFICULTY (ai-owned); core only scales bot damage.
const DIFFICULTY := {
    "easy":   {"damage_scale": 0.2},
    "normal": {"damage_scale": 0.3},
    "hard":   {"damage_scale": 0.45},
}
signal changed

const DEFAULT_HERO := "twin_tails"
var hero_id := DEFAULT_HERO
var map_id := "arena01"
var bot_difficulty := "normal"
var enemy_count := 3        ## bots on team 1
var ally_count := -1        ## bots on the player's team 0; -1 = map default (see allies_for)
var bot_count: int:         ## alias of enemy_count (v0.2 name)
    get: return enemy_count
    set(v): enemy_count = v
var low_quality := false     ## -- --low_quality (CLI/perf runs); the player setting is Settings.low_quality
var skip_menu_once := false   ## set by "Play again": next main.tscn load starts the match directly

func _ready() -> void:
    for a in OS.get_cmdline_user_args():
        var kv := a.trim_prefix("--").split("=", true, 1)
        if kv[0] == "low_quality":
            low_quality = kv.size() < 2 or kv[1] != "0"
        if kv.size() < 2:
            continue
        match kv[0]:
            "hero": set_hero(kv[1])
            "map": map_id = kv[1]
            "allies": ally_count = maxi(0, int(kv[1]))
            "enemies": enemy_count = maxi(0, int(kv[1]))
            "bots", "difficulty": bot_difficulty = kv[1] if DIFFICULTY.has(kv[1]) else "normal"

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

## Ally bots for a built map: only maps with team spawn_rooms (team modes, e.g. arena02 Control) get allies;
## default there is 2 (3v3 with the player). FFA maps without spawn_rooms (arena01) always get 0.
func allies_for(map: Node3D) -> int:
    var rooms: Dictionary = map.get_meta("spawn_rooms", {})
    if not rooms.has(0):
        return 0
    return 2 if ally_count < 0 else ally_count
