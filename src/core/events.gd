extends Node
## Global signal bus (autoload "Events"). Contract: docs/INTERFACES.md section 4.
## Modules never call each other's UI/FX directly; they emit here.

## ev = {source: Hero|null, target: Hero, amount: float, pos: Vector3, kind: String, killed: bool}
signal damage_dealt(ev: Dictionary)
## ev = {killer: Hero|null, victim: Hero, kind: String}
signal killed(ev: Dictionary)
signal respawned(hero)
## slot = "ability1" | "ability2" | "ultimate"
signal ability_used(hero, slot: String, ability_id: String)
