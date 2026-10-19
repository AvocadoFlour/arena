extends "res://tests/test_base.gd"
## HeroAbilities: data-driven ability descriptions cover every stat key and quote the real numbers.

func _num_keys(d: Dictionary, slot: String) -> Array:
    var out := []
    for k in d.keys():
        if k in HeroAbilities.COSMETIC or k == "needs_ult":
            continue
        out.append(k)
    return out

## Keys a template legitimately omits for this value (e.g. melee with unlimited swings).
func _suppressed(t: String, k: String, d: Dictionary) -> bool:
    if t == "melee" and k in ["mag", "reload_time"] and int(d.get("mag", 999)) >= 999:
        return true
    if t == "melee" and k == "spread_deg" and float(d.get("spread_deg", 0)) <= 0.0:
        return true
    if t == "melee" and k == "lunge" and float(d.get("lunge", 0)) <= 0.0:
        return true
    if t == "projectile" and k == "gravity" and float(d.get("gravity", 0)) <= 0.0:
        return true
    if t == "projectile" and k == "splash_radius" and float(d.get("splash_radius", 0)) <= 0.0:
        return true
    if k == "cooldown" and HeroAbilities.is_ult(d, t, "ultimate" if d.get("needs_ult", false) else "") and float(d.get("cooldown", 0)) <= 0.0:
        return true
    return false

func _has_num(text: String, v) -> bool:
    var s := HeroAbilities.n(v)
    var re := RegEx.create_from_string("(^|[^0-9.])" + s.replace(".", "\\.") + "($|[^0-9])")
    return re.search(text) != null

func test_every_hero_slot_described_and_covered() -> void:
    var ids := HeroAbilities.hero_ids()
    check(ids.size() >= 4 and "tomo" in ids, "heroes found %s" % [ids])
    for id in ids:
        var hero := HeroAbilities.load_hero(id)
        var all := HeroAbilities.describe_all(id)
        check(all.size() >= 4, "%s: primary + 3 abilities described (%d)" % [id, all.size()])
        for desc in all:
            var slot: String = desc.slot
            var d := HeroAbilities.slot_def(hero, slot)
            var t: String = desc.type
            check(HeroAbilities.TEMPLATES.has(t), "%s.%s: template for type '%s'" % [id, slot, t])
            var miss := HeroAbilities.uncovered_keys(d, slot)
            check(miss.is_empty(), "%s.%s (%s): stat keys not covered by the template: %s" % [id, slot, t, miss])
            check(String(desc.text).length() > 30 and not String(desc.name).is_empty(), "%s.%s: text + name" % [id, slot])
            for k in _num_keys(d, slot):
                var v = d[k]
                if _suppressed(t, k, d):
                    continue
                if v is float or v is int:
                    check(_has_num(desc.text, v) or desc.text.contains(HeroAbilities.pct(v)), "%s.%s: '%s' = %s appears in: %s" % [id, slot, k, HeroAbilities.n(v), desc.text])
                elif v is Array:
                    for m in v:
                        check(desc.text.contains("x" + HeroAbilities.n(m)), "%s.%s: combo x%s in text" % [id, slot, HeroAbilities.n(m)])
                        check(_has_num(desc.text, float(d.get("damage", 0)) * float(m)), "%s.%s: combo hit damage %s" % [id, slot, HeroAbilities.n(float(d.get("damage", 0)) * float(m))])
                elif v is Dictionary:
                    if k == "slow":
                        check(desc.text.contains(HeroAbilities.pct(v.get("mult", 0))) and _has_num(desc.text, v.get("duration", 0)), "%s.%s: slow numbers in text" % [id, slot])
                    elif k == "on_hit_speed":
                        check(desc.text.contains("+" + HeroAbilities.pct(v.get("bonus", 0))) and _has_num(desc.text, v.get("decay", 0)), "%s.%s: on_hit_speed numbers in text" % [id, slot])
                    else:
                        check(false, "%s.%s: nested key %s not checked" % [id, slot, k])
            if slot != "primary":
                var ult := HeroAbilities.is_ult(d, t, slot)
                if ult:
                    check(_has_num(desc.text, hero.get("ultimate_cost", 500)) and desc.stats.get("ult_cost") == float(hero.get("ultimate_cost", 500)), "%s.%s: ult cost in text" % [id, slot])
                check(desc.stats.has("cooldown") == d.has("cooldown"), "%s.%s: cooldown in stats" % [id, slot])

func test_api_shape_and_slots() -> void:
    var d := HeroAbilities.describe("the_best", "primary")
    for k in ["name", "slot", "type", "text", "stats"]:
        check(d.has(k), "describe() has " + k)
    check(d.type == "melee" and d.stats.get("damage") == 32.0 and d.stats.has("dps") == false, "the_best primary stats %s" % [d.stats])
    check(HeroAbilities.describe("cob", "passive").is_empty() and HeroAbilities.describe("nope", "primary").is_empty(), "absent slot / hero -> {}")
    var slots := []
    for x in HeroAbilities.describe_all("twin_tails"):
        slots.append(x.slot)
    check(slots == ["primary", "ability1", "ability2", "ultimate"], "slot order %s" % [slots])

func test_text_follows_data_not_hand_typed() -> void:
    var hero: Dictionary = HeroAbilities.load_hero("cob").duplicate(true)
    hero.abilities.ability1.damage = 77
    hero.ultimate_cost = 640
    check(HeroAbilities.describe_def(hero, "ability1").text.contains("77 damage"), "changed damage shows up")
    check(HeroAbilities.describe_def(hero, "ultimate").text.contains("640"), "changed ult cost shows up")
    hero.primary.fire_rate = 10
    check(HeroAbilities.describe_def(hero, "primary").text.contains("80 DPS"), "derived DPS recomputed")

func test_unknown_type_falls_back_and_is_flagged() -> void:
    var hero := {"ultimate_cost": 500, "abilities": {"ability1": {"id": "x", "name": "Rewind", "type": "time_warp", "cooldown": 9.0, "window": 3.0, "min_heal": 40}}}
    var d := HeroAbilities.describe_def(hero, "ability1")
    check(d.name == "Rewind" and d.text.contains("window 3") and d.text.contains("min heal 40") and d.text.contains("Cooldown 9 s"), "generic text: %s" % d.text)
    check(HeroAbilities.uncovered_keys(hero.abilities.ability1).size() == 2, "unknown type keys flagged")
    var cob := HeroAbilities.load_hero("cob").duplicate(true)
    cob.abilities.ability2["new_stat"] = 3
    check(HeroAbilities.uncovered_keys(cob.abilities.ability2) == ["new_stat"], "new key on a known type flagged")
