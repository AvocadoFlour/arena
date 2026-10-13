class_name MatchStats
extends Node
## UI-side per-hero tally built only from Events (damage_dealt, killed). Read-only w.r.t. gameplay.
## rows: hero -> {kills, deaths, damage, healing}
## Healing: no heal event exists yet (INTERFACES §3/§4 only have hero.heal()). If the bus gains
## `healed({source, target, amount})` (requested in docs/requests/ui.md) it is tallied automatically;
## until then `healing_tracked` is false and the UI shows "-".
var rows := {}
var healing_tracked := false

func bind(bus: Object) -> void:
    bus.connect("damage_dealt", on_damage)
    bus.connect("killed", on_kill)
    if bus.has_signal("healed"):
        healing_tracked = true
        bus.connect("healed", on_heal)

func on_heal(ev: Dictionary) -> void:
    healing_tracked = true
    if ev.get("source") != null:
        _row(ev.source).healing += float(ev.get("amount", 0.0))

func _row(h) -> Dictionary:
    if not rows.has(h):
        rows[h] = {"kills": 0, "deaths": 0, "damage": 0.0, "healing": 0.0}
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
        out.append({"hero": h, "name": h.display_name, "team": h.team, "kills": r.kills, "deaths": r.deaths, "damage": r.damage, "healing": r.healing})
    out.sort_custom(func(a, b):
        if a.kills != b.kills: return a.kills > b.kills
        if a.deaths != b.deaths: return a.deaths < b.deaths
        return a.damage > b.damage)
    return out

## Healing cell text: "-" while healing isn't reported by any event.
func healing_text(v: float) -> String:
    return str(int(round(v))) if healing_tracked else "-"

## Rows grouped by team: {team: [rows]}, each group sorted like sorted_rows.
func by_team(heroes: Array) -> Dictionary:
    var out := {}
    for r in sorted_rows(heroes):
        if not out.has(r.team):
            out[r.team] = []
        out[r.team].append(r)
    return out

## Match highlights: [{label, name, value}] for most kills / top damage / top healing (only if tracked
## and > 0). Ties go to the first in sort order. Labels are plain descriptions.
func highlights(heroes: Array) -> Array:
    var rs := sorted_rows(heroes)
    var out := []
    for spec in [["Most kills", "kills"], ["Top damage", "damage"], ["Top healing", "healing"]]:
        if spec[1] == "healing" and not healing_tracked:
            continue
        var best = null
        for r in rs:
            if r[spec[1]] > 0 and (best == null or r[spec[1]] > best[spec[1]]):
                best = r
        if best != null:
            out.append({"label": spec[0], "name": best.name, "value": int(round(best[spec[1]])), "hero": best.hero})
    return out

## Per-team totals: {team: {kills, deaths, damage, healing}}.
func team_totals(heroes: Array) -> Dictionary:
    var out := {}
    for r in sorted_rows(heroes):
        if not out.has(r.team):
            out[r.team] = {"kills": 0, "deaths": 0, "damage": 0.0, "healing": 0.0}
        for k in ["kills", "deaths", "damage", "healing"]:
            out[r.team][k] += r[k]
    return out
