class_name AbilityInfo
extends RefCounted
## Ability descriptions for the UI (hero select, Match page hero switch, HUD tooltips).
## Source: the heroes-owned `HeroAbilities` (src/heroes/hero_abilities.gd: describe(hero_id, slot),
## describe_all(hero_id), describe_def(def, slot) -> {name, slot, type, text, stats}) when that script exists;
## otherwise a fallback built from the hero JSON (name, type, cooldown, ult cost, primary numbers and any
## "description"). The class is loaded by path, never by class_name, so this file compiles with or without it.
## Every entry is normalised to {name, slot, type, text, stats: Dictionary, description, source}.
## `description` is the def's own optional "description" text; `source` is "api" or "json".

## ability3 (right mouse) sits between ability2 and ultimate; heroes without it simply have no entry.
const SLOTS := ["primary", "ability1", "ability2", "ability3", "ultimate", "passive"]
const SLOT_LABELS := {"primary": "Primary", "ability1": "Ability 1", "ability2": "Ability 2", "ability3": "Ability 3", "ultimate": "Ultimate", "passive": "Passive"}
## Slot -> input action whose live binding is shown (Hud.key_label). Passive has no key.
const SLOT_ACTIONS := {"primary": "fire", "ability1": "ability1", "ability2": "ability2", "ability3": "ability3", "ultimate": "ultimate"}
const HERO_DIR := "res://src/heroes/"

## Path of the heroes API script (tests point it elsewhere to force the JSON fallback).
static var api_path := "res://src/heroes/hero_abilities.gd"
## Test hook: any object with describe_all(hero_id) / describe(hero_id, slot) (describe_def optional).
static var provider: Object = null
static var _api: Object = null
static var _api_from := ""

static func api() -> Object:
    if provider != null:
        return provider
    if _api_from != api_path:
        _api_from = api_path
        _api = load(api_path) if ResourceLoader.exists(api_path) else null
        if _api != null and not (_has(_api, "describe_all") and _has(_api, "describe")):
            _api = null
    return _api

## has_method for objects, script static functions for a Script resource.
static func _has(o: Object, m: String) -> bool:
    if o is Script:
        return (o as Script).get_script_method_list().any(func(d): return d.name == m)
    return o.has_method(m)

static func has_api() -> bool:
    return api() != null

## Drop the cached script (tests).
static func reset() -> void:
    provider = null
    _api = null
    _api_from = ""
    api_path = "res://src/heroes/hero_abilities.gd"

static func load_def(hero_id: String) -> Dictionary:
    var path := HERO_DIR + hero_id + ".json"
    if not FileAccess.file_exists(path):
        return {}
    var d = JSON.parse_string(FileAccess.get_file_as_string(path))
    return d if d is Dictionary else {}

## All slots of a hero in slot order. `def` (optional) is an already-loaded def: with the real API it is
## described through describe_def (so a modified def is honoured); otherwise the hero is looked up by id.
static func describe_all(hero_id: String, def := {}) -> Array:
    if def.is_empty():
        def = load_def(hero_id)
    if hero_id == "":
        hero_id = String(def.get("id", ""))
    var a := api()
    var out := []
    if a != null:
        var raw: Array = []
        if not def.is_empty() and _has(a, "describe_def"):
            for s in SLOTS:
                var e = a.describe_def(def, s)
                if e is Dictionary and not e.is_empty():
                    raw.append(e)
        else:
            var r = a.describe_all(hero_id)
            raw = r if r is Array else []
        for e in raw:
            if e is Dictionary and not e.is_empty():
                out.append(_normalise(e, def, "api"))
        _sort(out)
        if not out.is_empty():
            return out
    for s in SLOTS:
        var e := fallback(def, s)
        if not e.is_empty():
            out.append(e)
    return out

static func describe(hero_id: String, slot: String, def := {}) -> Dictionary:
    if def.is_empty():
        def = load_def(hero_id)
    var a := api()
    if a != null:
        var e = a.describe_def(def, slot) if (not def.is_empty() and _has(a, "describe_def")) else a.describe(hero_id, slot)
        if e is Dictionary and not e.is_empty():
            return _normalise(e, def, "api")
    return fallback(def, slot)

static func _sort(arr: Array) -> void:
    arr.sort_custom(func(x, y): return _rank(x.slot) < _rank(y.slot))

static func _rank(slot: String) -> int:
    var i := SLOTS.find(slot)
    return i if i >= 0 else SLOTS.size()

static func slot_def(def: Dictionary, slot: String) -> Dictionary:
    if slot == "primary" or slot == "passive":
        var p = def.get(slot, {})
        return p if p is Dictionary else {}
    var a = def.get("abilities", {}).get(slot, {})
    return a if a is Dictionary else {}

static func _normalise(e: Dictionary, def: Dictionary, src: String) -> Dictionary:
    var slot := String(e.get("slot", ""))
    var sd := slot_def(def, slot)
    var st = e.get("stats", {})
    var nm := String(e.get("name", sd.get("name", SLOT_LABELS.get(slot, slot))))
    if slot == "primary" and not sd.has("name") and not def.is_empty():
        nm = KillFeed.primary_name(def)   # unnamed primary: same label as the kill feed
    return {
        "name": nm,
        "slot": slot,
        "type": String(e.get("type", sd.get("type", ""))),
        "text": String(e.get("text", "")),
        "stats": st if st is Dictionary else {},
        "description": String(sd.get("description", "")),
        "source": src,
    }

## JSON-only entry: name, type, cooldown / ult cost, primary numbers, def "description" as the text.
static func fallback(def: Dictionary, slot: String) -> Dictionary:
    var d := slot_def(def, slot)
    if d.is_empty():
        return {}
    var t := String(d.get("type", "hitscan" if slot == "primary" else ""))
    var stats := {}
    var nm := ""
    if slot == "primary":
        nm = KillFeed.primary_name(def)
        for k in ["damage", "fire_rate", "range", "mag", "reload_time"]:
            if d.has(k) and not (k == "mag" and int(d[k]) >= 999):
                stats[k] = d[k]
    else:
        nm = String(d.get("name", d.get("id", t.capitalize())))
        if bool(d.get("needs_ult", false)) or slot == "ultimate":
            stats["ult_cost"] = def.get("ultimate_cost", 500)
        if d.has("cooldown") and float(d.cooldown) > 0.0:
            stats["cooldown"] = d.cooldown
    var desc := String(d.get("description", ""))
    return {"name": nm, "slot": slot, "type": t, "text": desc, "stats": stats, "description": "", "source": "json"}

## "Ability 1" etc.; with_key adds the live binding: "Ability 1 [SHIFT]".
static func slot_label(slot: String, with_key := true) -> String:
    var s: String = SLOT_LABELS.get(slot, slot.capitalize())
    if with_key and SLOT_ACTIONS.has(slot) and InputMap.has_action(SLOT_ACTIONS[slot]):
        s += " [%s]" % Hud.key_label(SLOT_ACTIONS[slot])
    return s

## Readable stat lines for an entry ("Damage per hit: 32", "Cooldown: 7 s"); the label table is StatLabels.
static func stat_lines(e: Dictionary) -> Array:
    var st = e.get("stats", {})
    return StatLabels.lines(st if st is Dictionary else {}, String(e.get("type", "")), String(e.get("slot", "")))

## Same, one per line.
static func stats_text(e: Dictionary) -> String:
    return "\n".join(stat_lines(e))
