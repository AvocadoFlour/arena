extends Node
## Global signal bus (autoload "Events"). Contract: docs/INTERFACES.md section 4.
## Modules never call each other's UI/FX directly; they emit here.

## ev = {source: Hero|null, target: Hero, amount: float, pos: Vector3, kind: String, killed: bool}
signal damage_dealt(ev: Dictionary)
## ev = {killer: Hero|null, victim: Hero, kind: String}
signal killed(ev: Dictionary)
signal respawned(hero)
## Host/offline: an ability's cooldown just ran out (not fired by direct resets such as respawn or test hooks).
signal ability_ready(hero, slot: String)
## slot = "ability1" | "ability2" | "ultimate"
signal ability_used(hero, slot: String, ability_id: String)

## Capture points (single contract, INTERFACES.md sections 4 and 6). Teams int, neutral = -1.
## ev = {zone_id: String, team: int, progress: float 0..1, contested: bool, owner: int}
##   team = team currently capturing (or the owner when nobody is capturing); throttled to <= 10 Hz,
##   always emitted immediately when `contested` flips.
signal capture_progress(ev: Dictionary)
## ev = {zone_id: String, team: int, previous: int}
signal capture_completed(ev: Dictionary)
## Match flow (section 9). ev = {mode, scores: {team: percent}, target} about once per second.
signal match_score(ev: Dictionary)
## ev = {winner_team: int (-1 = draw), reason: String ("score" | "forced"), mode, scores, time}. Emitted once.
signal match_ended(ev: Dictionary)
