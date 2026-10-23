class_name StatLabels
extends RefCounted
## THE label table for ability stats (hero select, Match page pane, HUD tooltip). One plain phrase per stat:
## "Damage per hit: 32", "Cooldown: 7 s". Values are shown EXACTLY as the data has them (only trailing zeros
## stripped: 7.0 -> 7); percentages are an exact decimal shift (0.35 -> 35%), never float maths.
## A key not in LABELS / PAIRS / HIDDEN is never shown (no raw keys); tests require every real key to be covered.
## Hidden values: zero / false / empty, spread on melee, ammo + reload on no-ammo weapons (mag >= 999).
##
## LABELS: key -> [label, unit]  (unit "" | " m" | " s" | " m/s" | "°" | "%" | "x" (prefix ×) | "flag" (no value))
## Context overrides are "<context>:<key>"; contexts tried in order: "burst" (stats have a burst), type (e.g.
## "melee", "shield_wall"), "ranged" for any non-melee primary, then the plain key. "{hit}" in a label = ordinal of the combo's last hit.
const LABELS := {
    "damage": ["Damage", ""],
    "melee:damage": ["Damage per hit", ""],
    "ranged:damage": ["Damage per shot", ""],
    "dps": ["Damage per second", ""],
    "finisher_damage": ["{hit}-hit damage", ""],
    "combo_hits": ["Combo hits", ""],
    "combo_window": ["Combo window", " s"],
    "finisher_knockback": ["{hit}-hit knockback", " m/s"],
    "lunge": ["Lunge", " m"],
    "arc_deg": ["Arc", "°"],
    "melee:arc_deg": ["Swing arc", "°"],
    "shockwave:arc_deg": ["Cone", "°"],
    "fire_rate": ["Rate", "/s"],
    "melee:fire_rate": ["Swings per second", ""],
    "ranged:fire_rate": ["Shots per second", ""],
    "burst:fire_rate": ["Shots per second in a burst", ""],
    "burst": ["Shots per burst", ""],
    "burst_delay": ["Time between bursts", " s"],
    "burst_damage": ["Damage per burst", ""],
    "mag": ["Magazine", " rounds"],
    "reload_time": ["Reload", " s"],
    "spread_deg": ["Spread", "°"],
    "range": ["Range", " m"],
    "melee:range": ["Reach", " m"],
    "cooldown": ["Cooldown", " s"],
    "ult_cost": ["Ultimate cost", " charge"],
    "duration": ["Duration", " s"],
    "distance": ["Distance", " m"],
    "shield_wall:distance": ["Distance in front", " m"],
    "width": ["Wall width", " m"],
    "heal_beam:width": ["Beam width", " m"],
    "height": ["Wall height", " m"],
    "thickness": ["Wall thickness", " m"],
    "radius": ["Radius", " m"],
    "hit_radius": ["Hit radius", " m"],
    "splash_radius": ["Splash radius", " m"],
    "knockback": ["Knockback", " m/s"],
    "knockback_immune": ["Knockback immune", "flag"],
    "dive_speed": ["Dive speed", " m/s"],
    "forward_speed": ["Forward speed", " m/s"],
    "up_speed": ["Upward speed", " m/s"],
    "pull:up_speed": ["Lift", " m/s"],
    "air_time": ["Air time", " s"],
    "lift": ["Lift", " m/s"],
    "pull_speed": ["Pull speed", " m/s"],
    "stop_distance": ["Pulls to", " m"],
    "window": ["Rewinds", " s"],
    "damage_mult": ["Damage boost", "x"],
    "overheal": ["Overheal", ""],
    "bonus_mult": ["Bonus damage", "x"],
    "bonus_shots": ["Bonus shots", ""],
    "bonus_window": ["Bonus window", " s"],
    "hps": ["Healing per second", ""],
    "enemy_dps": ["Damage per second", ""],
    "ally_heal": ["Ally heal", " HP"],
    "total_heal": ["Total healing", ""],
    "heal": ["Heal", ""],
    "cone_deg": ["Aim cone", "°"],
    "speed": ["Projectile speed", " m/s"],
    "gravity": ["Gravity", " m/s²"],
    "lifetime": ["Lifetime", " s"],
    "max_range": ["Max range", " m"],
    "root": ["Root", " s"],
    "leap_time": ["Leap time", " s"],
    "ride_time": ["Ride time", " s"],
    "hop_range": ["Hop range", " m"],
    "hop_off_speed": ["Hop-off speed", " m/s"],
    "length": ["Length", " m"],
    "line_slash:width": ["Strip width", " m"],
    "line_slash:height": ["Strip height", " m"],
}
## Two keys shown as one phrase: [value key, duration key, builder].
const PAIRS := [
    ["slow", "slow_duration", "slow"],          # pull: move-speed multiplier + seconds
    ["slow_mult", "slow_duration", "slow"],     # projectile slow {mult, duration}
    ["damage_reduction", "dr_duration", "dr"],  # rollback
]
## Deliberately never shown: bookkeeping / covered by another line.
const HIDDEN := ["needs_ult", "sample", "exclusive"]
## Display order (keys not listed keep their table order after these).
const ORDER := ["damage", "finisher_damage", "burst_damage", "dps", "heal", "hps", "enemy_dps", "ally_heal", "total_heal", "overheal",
    "fire_rate", "burst", "burst_delay", "combo_hits", "combo_window", "range", "max_range", "arc_deg", "lunge",
    "radius", "distance", "width", "height", "thickness", "hit_radius", "splash_radius", "cone_deg",
    "slow", "slow_mult", "root", "damage_reduction", "damage_mult", "bonus_mult", "bonus_shots", "bonus_window",
    "duration", "window", "knockback", "finisher_knockback", "knockback_immune", "pull_speed", "stop_distance",
    "length", "leap_time", "ride_time", "hop_range", "hop_off_speed",
    "forward_speed", "up_speed", "air_time", "lift", "dive_speed", "speed", "lifetime", "gravity",
    "mag", "reload_time", "spread_deg", "cooldown", "ult_cost"]
const ORDINALS := ["First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth"]

## Exact text of a number: integers without ".0", other values as stored (shortest repr), trailing zeros stripped.
static func num(v) -> String:
    if v is int:
        return str(v)
    var f := float(v)
    if f == floorf(f) and absf(f) < 1e15:
        return str(int(f))
    var s := str(f)
    if s.contains(".") and not s.contains("e"):
        s = s.rstrip("0").rstrip(".")
    return s

## Exact percentage: decimal-shift the value's own digits (0.35 -> "35", 0.6 -> "60", 0.125 -> "12.5").
static func pct(v) -> String:
    var s := num(v)
    var neg := s.begins_with("-")
    if neg:
        s = s.substr(1)
    var ip := s
    var fp := ""
    if s.contains("."):
        ip = s.get_slice(".", 0)
        fp = s.get_slice(".", 1)
    fp += "00"
    var whole := (ip + fp.substr(0, 2)).lstrip("0")
    var rest := fp.substr(2).rstrip("0")
    if whole == "":
        whole = "0"
    return ("-" if neg else "") + whole + ("." + rest if rest != "" else "")

static func _contexts(type: String, slot: String, stats := {}) -> Array:
    var c := ["burst"] if _is_num(stats.get("burst")) and float(stats.burst) > 1.0 else []
    c.append(type)
    if slot == "primary" and type != "melee":
        c.append("ranged")
    return c

## [label, unit] for key in this context, or [] if the key is not in the table.
static func label_for(key: String, type := "", slot := "", stats := {}) -> Array:
    for ctx in _contexts(type, slot, stats):
        if LABELS.has(ctx + ":" + key):
            return LABELS[ctx + ":" + key]
    return LABELS.get(key, [])

## "label" | "pair" | "hidden" | "" (uncovered).
static func coverage(key: String) -> String:
    if key in HIDDEN:
        return "hidden"
    for p in PAIRS:
        if key == p[0] or key == p[1]:
            return "pair"
    if LABELS.has(key):
        return "label"
    for k in LABELS:
        if String(k).ends_with(":" + key):
            return "label"
    return ""

static func _is_num(v) -> bool:
    return v is int or v is float

static func _value(v, unit: String) -> String:
    if unit == "x":
        return "×" + num(v)
    if unit == "°" or unit == "%" or unit == "/s":
        return num(v) + unit
    return num(v) + unit

## Readable lines, one per stat, in ORDER. Hidden: zero/false/empty values, keys not in the table,
## spread on melee, ammo + reload when mag >= 999.
static func lines(stats: Dictionary, type := "", slot := "") -> Array:
    var out := []
    var no_ammo := _is_num(stats.get("mag")) and float(stats.mag) >= 999.0
    var hits := int(stats.get("combo_hits", 0))
    var ordinal: String = ORDINALS[hits - 1] if hits >= 1 and hits <= ORDINALS.size() else "Last"
    var keys := []
    for k in ORDER:
        if stats.has(k):
            keys.append(k)
    for k in stats.keys():
        if not k in keys:
            keys.append(k)
    for k in keys:
        var v = stats[k]
        if k in HIDDEN:
            continue
        if (k == "mag" or k == "reload_time") and no_ammo:
            continue
        if k == "spread_deg" and type == "melee":
            continue
        var paired := false
        for p in PAIRS:
            if k == p[1]:
                paired = true   # shown with its value key
            elif k == p[0]:
                paired = true
                var line := _pair(p[2], v, stats.get(p[1]))
                if line != "":
                    out.append(line)
        if paired:
            continue
        var lab := label_for(k, type, slot, stats)
        if lab.is_empty():
            continue   # never show a raw key
        if v is bool:
            if v and lab[1] == "flag":
                out.append(lab[0])
            continue
        if not _is_num(v) or float(v) == 0.0:
            continue
        out.append("%s: %s" % [String(lab[0]).replace("{hit}", ordinal), _value(v, lab[1])])
    return out

static func _pair(kind: String, v, dur) -> String:
    if not _is_num(v):
        return ""
    var d := (" for %s s" % num(dur)) if _is_num(dur) and float(dur) > 0.0 else ""
    match kind:
        "slow":
            if float(v) >= 1.0:
                return ""   # x1 speed = no slow
            if float(v) <= 0.0:
                return ("Root: %s s" % num(dur)) if d != "" else "Root"
            return "Slow: %s%% move speed%s" % [pct(v), d]
        "dr":
            if float(v) <= 0.0:
                return ""
            return "Damage reduction: %s%%%s" % [pct(v), d]
    return ""
