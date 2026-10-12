extends "res://tests/test_base.gd"
## Hero JSON definitions: schema, abilities resolve, Kestrel unchanged.
const HEROES := ["kestrel", "rampart", "willow"]

func _load(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func test_all_defs_schema() -> void:
    for id in HEROES:
        var d := _load(id)
        check(d.get("id") == id, id + ": id")
        for k in ["name", "role", "max_hp", "movement", "collider", "primary", "ultimate_cost", "abilities", "model"]:
            check(d.has(k), "%s: missing %s" % [id, k])
        check(d.primary.type == "hitscan", id + ": primary type")
        for slot in ["ability1", "ability2", "ultimate"]:
            var a: Dictionary = d.abilities[slot]
            check(AbilityRegistry.TYPES.has(a.type), "%s: unknown type %s" % [id, a.type])
            for k in ["id", "type", "name", "cooldown"]:
                check(a.has(k), "%s.%s missing %s" % [id, slot, k])
        for p in d.model:
            check(p.shape in ["capsule", "sphere", "box"], id + ": primitive shape")

func test_kestrel_unchanged() -> void:
    var d := _load("kestrel")
    check(d.max_hp == 250 and d.primary.damage == 14 and d.primary.fire_rate == 9, "kestrel stats")
    check(d.abilities.ability1.type == "dash" and d.abilities.ability2.type == "ground_slam" and d.abilities.ultimate.type == "nova", "kestrel kit")

func test_rampart_is_tank() -> void:
    var h := Hero.from_def("res://src/heroes/rampart.json")
    check(h.def.role == "tank", "role")
    check(h.health.max_hp == 500.0, "tank hp")
    check(h.def.abilities.ability1.type == "charge", "charge")
    check(h.def.abilities.ability2.type == "shield_wall", "shield wall")
    check(h.abilities["ability2"].has_method("remove_wall"), "shield script")
    h.free()

func test_willow_is_support() -> void:
    var h := Hero.from_def("res://src/heroes/willow.json")
    check(h.def.role == "support", "role")
    check(h.def.abilities.ability1.type == "heal_beam", "heal beam")
    var b: Dictionary = h.def.abilities.ability2
    check(b.type == "projectile" and b.slow.mult < 1.0 and b.slow.duration > 0.0, "slowing projectile")
    h.free()

func test_hero_slow_and_heal() -> void:
    var h := Hero.from_def("res://src/heroes/willow.json")
    h.apply_slow(0.5, 2.0)
    near(h.effective_move_cfg().speed, 3.5, 0.001, "slowed speed")
    near(h.move_cfg.speed, 7.0, 0.001, "base cfg untouched")
    h.apply_slow(0.8, 1.0)
    near(h.slow_mult, 0.5, 0.001, "weaker slow does not override")
    h.health.hp = 100.0
    near(h.heal(50.0), 50.0, 0.001, "heal amount")
    near(h.heal(500.0), 75.0, 0.001, "heal clamps to max")
    h.free()

func test_heal_beam_self_fallback() -> void:
    var h := Hero.from_def("res://src/heroes/willow.json")
    var ab = h.abilities["ability1"]
    h.health.hp = 100.0
    check(ab.activate(), "activates")
    check(not ab.activate(), "on cooldown")
    for i in 60:
        ab.tick(1.0 / 60.0)
    near(h.health.hp, 160.0, 1.0, "self heal 60 hps for 1 s")
    for i in 180:
        ab.tick(1.0 / 60.0)
    check(not ab.channeling(), "channel ends")
    near(h.health.hp, 225.0, 0.01, "capped")
    h.free()
