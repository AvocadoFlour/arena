class_name MatchStats
extends Node
## UI-side per-hero tally built only from Events (damage_dealt, killed). Read-only w.r.t. gameplay.
## rows: hero -> {kills, deaths, damage}
var rows := {}

func bind(bus: Object) -> void:
    bus.damage_dealt.connect(on_damage)
    bus.killed.connect(on_kill)

func _row(h) -> Dictionary:
    if not rows.has(h):
        rows[h] = {"kills": 0, "deaths": 0, "damage": 0.0}
    return rows[h]

func on_damage(ev: Dictionary) -> void:
    if ev.get("source") != null and ev.source != ev.get("target"):
        _row(ev.source).damage += float(ev.amount)

func on_kill(ev: Dictionary) -> void:
    _row(ev.victim).deaths += 1
    if ev.get("killer") != null and ev.killer != ev.victim:
        _row(ev.killer).kills += 1

## Sorted rows for display: [{hero, name, team, kills, deaths, damage}], kills desc, deaths asc, damage desc.
func sorted_rows(heroes: Array) -> Array:
    var out := []
    for h in heroes:
        if not is_instance_valid(h):
            continue
        var r := _row(h)
        out.append({"hero": h, "name": h.display_name, "team": h.team, "kills": r.kills, "deaths": r.deaths, "damage": r.damage})
    out.sort_custom(func(a, b):
        if a.kills != b.kills: return a.kills > b.kills
        if a.deaths != b.deaths: return a.deaths < b.deaths
        return a.damage > b.damage)
    return out
