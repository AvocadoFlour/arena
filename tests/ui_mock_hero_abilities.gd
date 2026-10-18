extends RefCounted
## Stand-in for src/heroes/hero_abilities.gd (HeroAbilities, heroes branch) with the same static API shape:
## describe(hero_id, slot) / describe_all(hero_id) -> {name, slot, type, text, stats}. Used by ui_round16_test
## through AbilityInfo.api_path (loaded by path, exactly how the real script is loaded). No describe_def.
static var calls := 0

static func describe(hero_id: String, slot: String) -> Dictionary:
    calls += 1
    if not slot in ["primary", "ability1", "ability2", "ultimate"]:
        return {}
    return {"name": "%s %s" % [hero_id, slot], "slot": slot, "type": "mock",
        "text": "Mock text for %s %s: 12 damage in 3 m." % [hero_id, slot], "stats": {"damage": 12, "radius": 3, "cooldown": 7}}

static func describe_all(hero_id: String) -> Array:
    var out := []
    for s in ["ultimate", "primary", "ability2", "ability1"]:   # out of order on purpose: UI sorts
        out.append(describe(hero_id, s))
    return out
