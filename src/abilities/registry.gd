class_name AbilityRegistry
extends RefCounted
## Maps ability "type" strings in hero JSON to scripts. Add new ability types here.
const TYPES := {
    "dash": preload("res://src/abilities/dash.gd"),
    "ground_slam": preload("res://src/abilities/ground_slam.gd"),
    "nova": preload("res://src/abilities/nova.gd"),
}

static func create(hero, d: Dictionary) -> Ability:
    var t := String(d.get("type", ""))
    assert(TYPES.has(t), "unknown ability type " + t)
    return TYPES[t].new(hero, d)
