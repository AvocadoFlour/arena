class_name AbilityRegistry
extends RefCounted
## Maps ability "type" strings in hero JSON to scripts. Add new ability types here.
const TYPES := {
    "dash": preload("res://src/abilities/dash.gd"),
    "ground_slam": preload("res://src/abilities/ground_slam.gd"),
    "nova": preload("res://src/abilities/nova.gd"),
    "projectile": preload("res://src/abilities/projectile.gd"),
    "shield_wall": preload("res://src/abilities/shield_wall.gd"),
    "charge": preload("res://src/abilities/charge.gd"),
    "heal_beam": preload("res://src/abilities/heal_beam.gd"),
    "rally": preload("res://src/abilities/rally.gd"),
    "leap": preload("res://src/abilities/leap.gd"),
    "team_buff": preload("res://src/abilities/team_buff.gd"),
}

static func create(hero, d: Dictionary) -> Ability:
    var t := String(d.get("type", ""))
    assert(TYPES.has(t), "unknown ability type " + t)
    return TYPES[t].new(hero, d)
