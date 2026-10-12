extends "res://tests/test_base.gd"
## Hero JSON definitions: schema, abilities resolve, Kestrel unchanged.
const HEROES := ["twin_tails", "the_best", "cob"]
const ARCHIVED := ["kestrel", "rampart", "willow"]

func _load(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func _arch(id: String) -> String:
    return "res://src/heroes/archive/%s.json" % id

func test_all_defs_schema() -> void:
    for id in HEROES:
        var d := _load(id)
        check(d.get("id") == id, id + ": id")
        for k in ["name", "role", "max_hp", "movement", "collider", "primary", "ultimate_cost", "abilities", "model"]:
            check(d.has(k), "%s: missing %s" % [id, k])
        check(d.primary.type in ["hitscan", "melee"], id + ": primary type")
        for slot in ["ability1", "ability2", "ultimate"]:
            var a: Dictionary = d.abilities[slot]
            check(AbilityRegistry.TYPES.has(a.type), "%s: unknown type %s" % [id, a.type])
            for k in ["id", "type", "name", "cooldown"]:
                check(a.has(k), "%s.%s missing %s" % [id, slot, k])
        for p in d.model:
            check(p.shape in ["capsule", "sphere", "box"], id + ": primitive shape")

func test_kestrel_archived_unchanged() -> void:
    var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_arch("kestrel")))
    check(d.max_hp == 250 and d.primary.damage == 14 and d.primary.fire_rate == 9, "kestrel stats")
    check(d.abilities.ability1.type == "dash" and d.abilities.ability2.type == "ground_slam" and d.abilities.ultimate.type == "nova", "kestrel kit")

func test_display_names_exact() -> void:
    check(_load("twin_tails").name == "Twin Tails", "Twin Tails")
    check(_load("the_best").name == "The Best", "The Best")
    check(_load("cob").name == "Cob", "Cob")

func test_archive_complete_and_not_scanned() -> void:
    for id in ARCHIVED:
        check(FileAccess.file_exists(_arch(id)), "archived " + id)
        var h := Hero.from_def(_arch(id))
        check(h != null, "archived loads " + id)
        if h:
            h.free()
    for f in DirAccess.get_files_at("res://src/heroes"):
        check(not f.begins_with("archive"), "archive is a subfolder only")

func test_twin_tails_support_kit() -> void:
    var h := Hero.from_def("res://src/heroes/twin_tails.json")
    check(h.def.role == "support", "role")
    check(h.def.abilities.ability1.type == "heal_beam", "heal beam")
    var b: Dictionary = h.def.abilities.ability2
    check(b.type == "projectile" and b.slow.mult < 1.0, "slowing note projectile")
    check(h.def.abilities.ultimate.type == "rally", "team heal ult")
    var cols: Array = h.def.model.map(func(p): return String(p.color))
    check(not cols.any(func(c): return c.begins_with("#00") or c in ["#39c5bb", "#00ced1"]), "no teal")
    var tails: Array = h.def.model.filter(func(p): return p.get("anim", "") == "tail")
    var left := 0.0
    for p in tails:
        if float(p.pos[0]) < 0.0:
            left += float(p.height)
    check(tails.size() >= 2 and left >= 1.4, "two very long swaying tails (left %.2f m)" % left)
    h.free()

func test_the_best_brawler_kit() -> void:
    var h := Hero.from_def("res://src/heroes/the_best.json")
    check(h.def.primary.type == "melee" and h.def.primary.combo.size() == 3, "melee combo primary")
    check(h.def.abilities.ability1.type == "leap", "leap")
    var u: Dictionary = h.def.abilities.ultimate
    check(u.type == "team_buff" and u.needs_ult and u.knockback_immune and u.overheal > 0 and u.damage_mult > 1.0, "unstoppable ult")
    h.free()

func test_cob_tank_kit() -> void:
    var h := Hero.from_def("res://src/heroes/cob.json")
    check(h.def.role == "tank" and h.health.max_hp >= 500.0, "tank")
    check(h.def.abilities.ability1.type == "charge" and h.def.abilities.ability2.type == "shield_wall", "roll + wall")
    var u: Dictionary = h.def.abilities.ultimate
    check(u.type == "ground_slam" and u.needs_ult, "slam ult")
    check(not h.abilities["ultimate"].can_activate(), "ult locked without meter")
    h.ult.add(10000.0)
    check(h.abilities["ultimate"].can_activate(), "ult ready with meter")
    h.free()

func test_melee_arc() -> void:
    var f := Vector3(0, 0, -1)
    check(MeleeMath.in_arc(Vector3.ZERO, f, Vector3(0, 0, -2.5), 3.2, deg_to_rad(55)), "in front")
    check(MeleeMath.in_arc(Vector3.ZERO, f, Vector3(1.5, 0, -1.5), 3.2, deg_to_rad(55)), "45 deg side")
    check(not MeleeMath.in_arc(Vector3.ZERO, f, Vector3(0, 0, 2), 3.2, deg_to_rad(55)), "behind")
    check(not MeleeMath.in_arc(Vector3.ZERO, f, Vector3(0, 0, -4), 3.2, deg_to_rad(55)), "out of range")

func test_buff_overheal_knockback() -> void:
    var h := Hero.from_def("res://src/heroes/the_best.json")
    h.apply_buff(1.35, 1.0, true)
    near(h.damage_mult(), 1.35, 0.001, "damage boost")
    h.knockback(Vector3(10, 0, 0))
    near(h.velocity.x, 0.0, 0.001, "knockback immune")
    h.add_overheal(100.0, 1.0)
    h.take_damage(60.0, null, Vector3.ZERO, "primary")
    near(h.health.hp, h.health.max_hp, 0.001, "overheal absorbs first")
    near(h.overheal, 40.0, 0.001, "overheal left")
    for i in 61:
        h._tick_buffs(1.0 / 60.0)
    near(h.damage_mult(), 1.0, 0.001, "buff expires")
    check(not h.knockback_immune and h.overheal == 0.0, "immunity + overheal expire")
    h.knockback(Vector3(10, 0, 0))
    near(h.velocity.x, 10.0, 0.001, "knockback after expiry")
    h.free()

func test_hero_slow_and_heal() -> void:
    var h := Hero.from_def("res://src/heroes/twin_tails.json")
    h.apply_slow(0.5, 2.0)
    near(h.effective_move_cfg().speed, 3.6, 0.001, "slowed speed")
    near(h.move_cfg.speed, 7.2, 0.001, "base cfg untouched")
    h.apply_slow(0.8, 1.0)
    near(h.slow_mult, 0.5, 0.001, "weaker slow does not override")
    h.health.hp = 100.0
    near(h.heal(50.0), 50.0, 0.001, "heal amount")
    near(h.heal(500.0), 75.0, 0.001, "heal clamps to max")
    h.free()

func test_heal_beam_self_fallback() -> void:
    var h := Hero.from_def("res://src/heroes/twin_tails.json")
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

func test_models_animated_and_visual_only() -> void:
    for id in HEROES:
        var h := Hero.from_def("res://src/heroes/%s.json" % id)
        check(h._vis != null and h._anim_parts.size() >= 3, id + ": visual root + animated parts")
        var kinds: Array = h._anim_parts.map(func(a): return a[1])
        check(kinds.has("weapon"), id + ": weapon animates")
        check(h._muzzle != null and h._muzzle.get_parent() == h, id + ": muzzle not under animated root")
        var cols := 0
        for c in h.get_children():
            if c is CollisionShape3D:
                cols += 1
        check(cols == 1, id + ": single gameplay collider")
        # animation must not touch gameplay state
        h.velocity = Vector3(0, 0, -6)
        var v0 := h.velocity
        var p0 := h.position
        var hp0 := h.health.hp
        for i in 30:
            h._process(1.0 / 60.0)
        check(h.velocity == v0 and h.position == p0 and h.health.hp == hp0, id + ": anim is read-only")
        check(h._vis.rotation.x != 0.0, id + ": run lean applied")
        h.free()

func test_tails_sway_over_time() -> void:
    var h := Hero.from_def("res://src/heroes/twin_tails.json")
    var tail: Node3D = null
    for a in h._anim_parts:
        if a[1] == "tail":
            tail = a[0]
            break
    h._process(0.1)
    var r1 := tail.rotation
    h._process(0.5)
    check(tail.rotation != r1, "tail sways while idle")
    h.free()
