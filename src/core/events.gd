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

## Capture zones (forwarded from CaptureZone, INTERFACES.md section 6). Teams int, neutral = -1.
## ev = {zone, owner, capturing_team, progress, contested}
signal zone_changed(ev: Dictionary)
## ev = {zone, team, previous}
signal zone_captured(ev: Dictionary)
## ev = {zone, contested}
signal zone_contested(ev: Dictionary)
## Match flow (section 9). ev = {mode, scores: {team: percent}, target} — about once per second
signal match_score(ev: Dictionary)
## ev = {winner: int, mode, scores, time}. Emitted once; core then pauses the match.
signal match_ended(ev: Dictionary)
