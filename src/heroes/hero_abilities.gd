class_name HeroAbilities
extends RefCounted
## Precise, data-driven ability descriptions for UI (hero select, tooltips, HUD).
## Pure data: reads res://src/heroes/<id>.json only; no spawned hero / scene tree needed.
##   HeroAbilities.describe(hero_id, slot) -> {name, slot, type, text, stats}   ({} if the slot is absent)
##   HeroAbilities.describe_all(hero_id)   -> Array of the above, in SLOTS order (absent slots skipped)
## Slots: "primary" (weapon), "ability1", "ability2", "ultimate", "passive" (none defined yet).
## Every number in `text` comes from the def through a per-type template (TEMPLATES below), so it
## cannot drift. A def key a template does not cover is reported by uncovered_keys() (the tests fail
## on it); an unknown type falls back to a generic "key value" description so new heroes still work.

const SLOTS := ["primary", "ability1", "ability2", "ultimate", "passive"]
const HERO_DIR := "res://src/heroes/"
## Keys that never change gameplay (visual/bookkeeping) - not described.
const COSMETIC := ["id", "name", "type", "color", "visual", "beam_color", "kind", "size", "glyph"]
## Keys every ability type understands (base Ability class).
const COMMON := ["cooldown", "needs_ult"]
## Stat keys each template reads. Add the key here AND use it in _text_<type> when a script gains one.
const TEMPLATES := {
    "hitscan": ["damage", "fire_rate", "mag", "reload_time", "spread_deg", "range"],
    "melee": ["damage", "fire_rate", "mag", "reload_time", "spread_deg", "range", "arc_deg", "combo", "combo_window", "finisher_knockback", "lunge"],
    "charge": ["distance", "duration", "damage", "hit_radius", "knockback"],
    "shield_wall": ["width", "height", "thickness", "distance", "duration"],
    "ground_slam": ["radius", "damage", "dive_speed"],
    "leap": ["forward_speed", "up_speed", "air_time", "radius", "damage", "knockback"],
    "dash": ["distance", "duration"],
    "team_buff": ["radius", "duration", "damage_mult", "knockback_immune", "overheal"],
    "heal_beam": ["duration", "hps", "range", "cone_deg"],
    "projectile": ["speed", "damage", "gravity", "lifetime", "hit_radius", "splash_radius", "slow"],
    "rally": ["radius", "heal"],
    "nova": ["radius", "damage"],
}
## Types that always consume the full ultimate meter, even without "needs_ult".
const ULT_TYPES := ["rally", "nova"]
const MELEE_LUNGE_CONE_DEG := 30.0      # hero.gd melee_swing lunge search cone
const AOE_EDGE_PCT := 50                # HitMath.aoe_damage: linear falloff to 50% at the edge

static var _cache := {}

static func load_hero(hero_id: String) -> Dictionary:
    if not _cache.has(hero_id):
        var path := HERO_DIR + hero_id + ".json"
        var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
        _cache[hero_id] = d if d is Dictionary else {}
    return _cache[hero_id]

## Playable hero ids (every src/heroes/*.json; archive/ is a sub-folder and not scanned).
static func hero_ids() -> Array:
    var out := []
    for f in DirAccess.get_files_at(HERO_DIR):
        if f.ends_with(".json"):
            out.append(f.get_basename())
    out.sort()
    return out

## Raw def of a slot ({} if absent).
static func slot_def(hero: Dictionary, slot: String) -> Dictionary:
    if slot == "primary":
        return hero.get("primary", {})
    if slot == "passive":
        return hero.get("passive", {})
    return hero.get("abilities", {}).get(slot, {})

static func describe(hero_id: String, slot: String) -> Dictionary:
    return describe_def(load_hero(hero_id), slot)

static func describe_all(hero_id: String) -> Array:
    var hero := load_hero(hero_id)
    var out := []
    for s in SLOTS:
        var d := describe_def(hero, s)
        if not d.is_empty():
            out.append(d)
    return out

## Same as describe() for an already-loaded hero def (lets tests / tools feed modified data).
static func describe_def(hero: Dictionary, slot: String) -> Dictionary:
    var d := slot_def(hero, slot)
    if d.is_empty():
        return {}
    var t := String(d.get("type", "hitscan" if slot == "primary" else ""))
    var nm := String(d.get("name", "Primary fire" if slot == "primary" else t.capitalize()))
    var stats := _stats(d)
    var text := ""
    match t:
        "hitscan": text = _text_hitscan(d, stats)
        "melee": text = _text_melee(d, stats)
        "charge": text = _text_charge(d, stats)
        "shield_wall": text = _text_shield_wall(d, stats)
        "ground_slam": text = _text_ground_slam(d, stats)
        "leap": text = _text_leap(d, stats)
        "dash": text = _text_dash(d, stats)
        "team_buff": text = _text_team_buff(d, stats)
        "heal_beam": text = _text_heal_beam(d, stats)
        "projectile": text = _text_projectile(d, stats)
        "rally": text = _text_rally(d, stats)
        "nova": text = _text_nova(d, stats)
        _: text = _text_generic(d)
    if slot != "primary":
        text += " " + _cost_text(hero, d, t, stats)
    return {"name": nm, "slot": slot, "type": t, "text": text.strip_edges(), "stats": stats}

## Gameplay keys of a def that no template covers (empty = fully described).
static func uncovered_keys(d: Dictionary, slot := "") -> Array:
    var t := String(d.get("type", "hitscan" if slot == "primary" else ""))
    var known: Array = TEMPLATES.get(t, [])
    var out := []
    for k in d.keys():
        if not (k in COSMETIC or k in COMMON or k in known):
            out.append(k)
    return out

## Number formatting used in every text (tests use it to find the numbers): 8, 2.5, 0.16, 1.35.
static func n(v) -> String:
    var f := float(v)
    if is_equal_approx(f, roundf(f)):
        return str(int(roundf(f)))
    return String.num(f, 2)

static func pct(v) -> String:
    return n(float(v) * 100.0) + "%"

static func _stats(d: Dictionary) -> Dictionary:
    var s := {}
    for k in d.keys():
        if k in COSMETIC:
            continue
        var v = d[k]
        if v is float or v is int or v is bool:
            s[k] = v
    return s

static func _cost_text(hero: Dictionary, d: Dictionary, t: String, stats: Dictionary) -> String:
    var cd := float(d.get("cooldown", 0.0))
    if bool(d.get("needs_ult", false)) or t in ULT_TYPES:
        var cost := float(hero.get("ultimate_cost", 500))
        stats["ult_cost"] = cost
        return "Ultimate: needs a full meter of %s charge (1 charge per point of damage dealt)%s." % [n(cost), (", then a %s s cooldown" % n(cd)) if cd > 0.0 else ""]
    return "Cooldown %s s." % n(cd)

# ------------------------------------------------------------------ templates (one per ability type)
static func _text_hitscan(d: Dictionary, s: Dictionary) -> String:
    var dps := float(d.get("damage", 0)) * float(d.get("fire_rate", 1))
    s["dps"] = dps
    return "Hitscan: %s damage per shot at %s shots/s (%s DPS), %s-round magazine, %s s reload, %s° spread, %s m range, no damage falloff. Hits enemies and breakable cover." % [
        n(d.get("damage", 0)), n(d.get("fire_rate", 1)), n(dps), n(d.get("mag", 0)), n(d.get("reload_time", 0)), n(d.get("spread_deg", 0)), n(d.get("range", 80))]

static func _text_melee(d: Dictionary, s: Dictionary) -> String:
    var combo: Array = d.get("combo", [1.0])
    var dmg := float(d.get("damage", 0))
    var hits := []
    var mults := []
    for m in combo:
        hits.append(n(dmg * float(m)))
        mults.append("x" + n(m))
    s["combo_hits"] = combo.size()
    s["finisher_damage"] = dmg * float(combo[-1])
    var txt := "Melee: %s° frontal arc, %s m reach, %s swings/s, hits every enemy in the arc. %s-hit combo: %s damage (%s) if each swing follows within %s s; the finisher knocks enemies back at %s m/s." % [
        n(d.get("arc_deg", 100)), n(d.get("range", 3)), n(d.get("fire_rate", 1)), combo.size(), " / ".join(hits), " / ".join(mults), n(d.get("combo_window", 0.8)), n(d.get("finisher_knockback", 6))]
    if float(d.get("lunge", 0)) > 0.0:
        txt += " Lunges up to %s m extra to reach an enemy in a %s° cone ahead." % [n(d.get("lunge", 0)), n(MELEE_LUNGE_CONE_DEG)]
    if int(d.get("mag", 999)) < 999:
        txt += " %s swings, then a %s s reload." % [n(d.get("mag", 0)), n(d.get("reload_time", 0))]
    else:
        txt += " No ammo."
    if float(d.get("spread_deg", 0)) > 0.0:
        txt += " %s° aim spread." % n(d.get("spread_deg", 0))
    return txt

static func _text_charge(d: Dictionary, s: Dictionary) -> String:
    return "Rushes %s m forward over %s s; each enemy within %s m of you takes %s damage (once per enemy) and is knocked back at %s m/s." % [
        n(d.get("distance", 9)), n(d.get("duration", 0.5)), n(d.get("hit_radius", 1.3)), n(d.get("damage", 40)), n(d.get("knockback", 8))]

static func _text_shield_wall(d: Dictionary, s: Dictionary) -> String:
    return "Raises a %s x %s m wall (%s m thick) %s m in front of you for %s s. It is solid world geometry: blocks movement, hitscan and projectiles from both sides, for allies and enemies alike." % [
        n(d.get("width", 4)), n(d.get("height", 2.4)), n(d.get("thickness", 0.25)), n(d.get("distance", 1.6)), n(d.get("duration", 5))]

static func _text_ground_slam(d: Dictionary, s: Dictionary) -> String:
    return "Slams the ground: %s damage to enemies within %s m (linear falloff to %d%% at the edge), also hits breakable cover. Used in the air, you first dive down at %s m/s and slam on landing." % [
        n(d.get("damage", 70)), n(d.get("radius", 5)), AOE_EDGE_PCT, n(d.get("dive_speed", 30))]

static func _text_leap(d: Dictionary, s: Dictionary) -> String:
    return "Leaps forward (%s m/s forward, %s m/s up, up to %s s airborne). On landing: %s damage to enemies within %s m (linear falloff to %d%% at the edge), knocking them away at %s m/s." % [
        n(d.get("forward_speed", 14)), n(d.get("up_speed", 9)), n(d.get("air_time", 0.7)), n(d.get("damage", 50)), n(d.get("radius", 3.5)), AOE_EDGE_PCT, n(d.get("knockback", 6))]

static func _text_dash(d: Dictionary, s: Dictionary) -> String:
    return "Dashes %s m in your movement direction (facing if standing still) over %s s. No damage." % [n(d.get("distance", 7)), n(d.get("duration", 0.18))]

static func _text_team_buff(d: Dictionary, s: Dictionary) -> String:
    var txt := "For %s s, you and allies within %s m deal x%s damage and gain %s overheal (absorbed before health, decays linearly to 0 over the %s s)." % [
        n(d.get("duration", 6)), n(d.get("radius", 8)), n(d.get("damage_mult", 1.3)), n(d.get("overheal", 100)), n(d.get("duration", 6))]
    if bool(d.get("knockback_immune", true)):
        txt += " Also immune to knockback."
    return txt

static func _text_heal_beam(d: Dictionary, s: Dictionary) -> String:
    var tot := float(d.get("hps", 60)) * float(d.get("duration", 3))
    s["total_heal"] = tot
    return "Channels a beam for %s s healing %s HP/s (%s HP total) on the ally nearest your aim within %s m and a %s° cone; heals you instead if no ally is in reach. Heals up to max HP." % [
        n(d.get("duration", 3)), n(d.get("hps", 60)), n(tot), n(d.get("range", 15)), n(d.get("cone_deg", 15))]

static func _text_projectile(d: Dictionary, s: Dictionary) -> String:
    var rng := float(d.get("speed", 20)) * float(d.get("lifetime", 3))
    s["max_range"] = rng
    var g := float(d.get("gravity", 0))
    var txt := "Fires a projectile (not hitscan) at %s m/s, lasting %s s (~%s m), %s, %s m hit radius: %s damage on a direct hit" % [
        n(d.get("speed", 20)), n(d.get("lifetime", 3)), n(rng), ("arcing with %s m/s² gravity" % n(g)) if g > 0.0 else "flying straight", n(d.get("hit_radius", 0.3)), n(d.get("damage", 0))]
    var sp := float(d.get("splash_radius", 0))
    if sp > 0.0:
        txt += ", plus splash to other enemies within %s m (linear falloff to %d%% at the edge)" % [n(sp), AOE_EDGE_PCT]
    txt += "."
    var slow: Dictionary = d.get("slow", {})
    if not slow.is_empty():
        s["slow_mult"] = float(slow.get("mult", 0.6))
        s["slow_duration"] = float(slow.get("duration", 2))
        txt += " Every enemy hit is slowed to %s move speed for %s s." % [pct(slow.get("mult", 0.6)), n(slow.get("duration", 2))]
    return txt

static func _text_rally(d: Dictionary, s: Dictionary) -> String:
    return "Instantly heals you and every ally within %s m for %s HP (up to max HP)." % [n(d.get("radius", 10)), n(d.get("heal", 150))]

static func _text_nova(d: Dictionary, s: Dictionary) -> String:
    return "Blasts %s damage to enemies within %s m (linear falloff to %d%% at the edge)." % [n(d.get("damage", 220)), n(d.get("radius", 10)), AOE_EDGE_PCT]

## Unknown type: still precise, just generic ("Type: key value, ..."). uncovered_keys() flags it.
static func _text_generic(d: Dictionary) -> String:
    var parts := []
    var keys := d.keys()
    keys.sort()
    for k in keys:
        if k in COSMETIC or k in COMMON:
            continue
        var v = d[k]
        if v is Dictionary:
            var sub := []
            for k2 in v.keys():
                sub.append("%s %s" % [String(k2).replace("_", " "), n(v[k2]) if (v[k2] is float or v[k2] is int) else str(v[k2])])
            parts.append("%s (%s)" % [String(k).replace("_", " "), ", ".join(sub)])
        elif v is float or v is int:
            parts.append("%s %s" % [String(k).replace("_", " "), n(v)])
        else:
            parts.append("%s %s" % [String(k).replace("_", " "), str(v)])
    return "%s: %s." % [String(d.get("type", "ability")).capitalize(), ", ".join(parts)]
