class_name UiCatalog
extends RefCounted
## Discovers heroes/maps from their data folders (INTERFACES.md §2 hero JSON, §6 map JSON).
## No hardcoded lists: any new src/heroes/*.json or src/maps/*.json shows up automatically.
const HERO_DIR := "res://src/heroes"
const MAP_DIR := "res://src/maps"

## Selection made in the menus (read by the composition root when wiring Play).
static var selected_hero := ""
static var selected_map := ""

static func _json_files(dir: String) -> PackedStringArray:
    var out := PackedStringArray()
    for f in DirAccess.get_files_at(dir):
        var n := f.trim_suffix(".remap")
        if n.ends_with(".json") and not out.has(dir + "/" + n):
            out.append(dir + "/" + n)
    out.sort()
    return out

static func _load(path: String):
    var j := JSON.new()   # instance parse: malformed files fail quietly instead of logging ERROR
    if j.parse(FileAccess.get_file_as_string(path)) != OK:
        return null
    return j.data if j.data is Dictionary else null

## -> Array of {id, name, role, max_hp, path}; skips malformed files.
static func list_heroes(dir := HERO_DIR) -> Array:
    var out := []
    for p in _json_files(dir):
        var d = _load(p)
        if d == null or not d.has("id"):
            continue
        out.append({"id": d.id, "name": d.get("name", d.id), "role": d.get("role", ""),
            "max_hp": d.get("max_hp", 0), "path": p})
    return out

## -> Array of {name, path}; skips malformed files.
static func list_maps(dir := MAP_DIR) -> Array:
    var out := []
    for p in _json_files(dir):
        var d = _load(p)
        if d == null or not d.has("blocks"):
            continue
        out.append({"name": d.get("name", p.get_file().get_basename()), "path": p})
    return out
