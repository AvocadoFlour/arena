extends "res://tests/test_base.gd"
## Niđo (sturdy brawler): kit from docs/concept/tomo_nidjo_proposal.md, GLB model (rig, anims, cap/jacket
## materials, hammer anchor), Ping Hammer combo knockback, Firewall wall, Stand-up Meeting pull + slow,
## Rollback HP restore + damage reduction.
var tree: SceneTree
const DEF := "res://src/heroes/nidjo.json"

func _hero(team := 0, pos := Vector3.ZERO, path := DEF) -> Hero:
    var h := Hero.from_def(path)
    h.team = team
    tree.root.add_child(h)
    h.global_position = pos
    return h

func _free(hs: Array) -> void:
    for h in hs:
        if is_instance_valid(h):
            h.free()

func test_kit_and_role() -> void:
    var h := Hero.from_def(DEF)
    check(h.def.name == "Niđo" and h.def.id == "nidjo", "name/id")
    check(h.def.role == "brawler" and absf(h.health.max_hp - 300.0) < 0.1, "brawler, 300 HP")
    var p: Dictionary = h.def.primary
    check(p.type == "melee" and p.name == "Ping Hammer" and p.combo.size() == 3 and p.finisher_knockback > 0, "Ping Hammer: 3-hit combo, 3rd hit knocks back")
    var a: Dictionary = h.def.abilities
    check(a.ability1.name == "Firewall" and a.ability1.type == "shield_wall", "Firewall = shield wall")
    check(a.ability2.name == "Stand-up Meeting" and a.ability2.type == "pull", "Stand-up Meeting = pull")
    check(a.ultimate.name == "Rollback" and a.ultimate.type == "rollback" and a.ultimate.needs_ult, "Rollback ult")
    check(AbilityRegistry.TYPES.has("pull") and AbilityRegistry.TYPES.has("rollback"), "types registered")
    check(GameConfig.hero_ids().has("nidjo"), "selectable")
    h.free()

func test_glb_model() -> void:
    var h := Hero.from_def(DEF)
    check(h.model != null and h.model.skeleton != null and h.model.anim_player != null, "GLB model + rig")
    for an in ["idle", "run", "swing_a", "swing_b", "finisher", "wall", "pull", "ult", "death"]:
        check(h.model.anim_player.has_animation(an), "anim " + an)
    for b in ["hips", "head", "hand.R", "thigh.L", "upper_arm.L"]:
        check(h.model.skeleton.find_bone(b) >= 0, "bone " + b)
    check(h.model.find_child("HammerHead", true, false) != null, "hammer anchor")
    var mats := {}   # imported GLB scene (HeroModel swaps in toon materials at runtime)
    var raw: Node = load(h.def.model_scene.path).instantiate()
    for mi in raw.find_children("*", "MeshInstance3D", true, false):
        for i in mi.mesh.get_surface_count():
            var m = mi.mesh.surface_get_material(i)
            if m:
                mats[m.resource_name] = true
    raw.free()
    for want in ["nj_cap", "nj_green", "nj_red", "nj_navy", "nj_plaid"]:
        check(mats.has(want), "material %s (cap, jacket, tartan lining, striped tee) in %s" % [want, mats.keys()])
    h.free()
    var prev := Hero.use_primitive_models
    Hero.use_primitive_models = true
    var p := Hero.from_def(DEF)
    check(p.model == null and p._muzzle != null, "primitive fallback with muzzle")
    p.free()
    Hero.use_primitive_models = prev

func test_ping_hammer_third_hit_knocks_back() -> void:
    var n := _hero(0, Vector3.ZERO)
    var e := _hero(1, Vector3(0, 0, -2.0))
    n.yaw = 0.0
    n.melee_swing()
    n.melee_swing()
    check(e.velocity.length() < 0.01, "first two hits: no knockback")
    var hp := e.health.hp
    n.melee_swing()
    check(e.velocity.z < -1.0, "third hit pulses a knockback (v %s)" % e.velocity)
    check(e.health.hp < hp, "third hit damages")
    _free([n, e])

func test_firewall_frontal_wall() -> void:
    var n := _hero(0, Vector3.ZERO)
    n.yaw = 0.0
    var ab = n.abilities["ability1"]
    check(ab.activate() and ab.active(), "wall up")
    check(ab.wall.global_position.z < -1.0 and absf(ab.wall.global_position.x) < 0.01, "in front of Niđo")
    check(ab.wall.collision_layer == 1, "blocks shots (world layer)")
    for i in 4 * 60:
        ab.tick(1.0 / 60.0)
    check(not ab.active(), "expires after a few seconds")
    _free([n])

func test_standup_meeting_pulls_and_slows() -> void:
    var n := _hero(0, Vector3.ZERO)
    var far := _hero(1, Vector3(6, 0, 0))
    var near_e := _hero(1, Vector3(0, 0, 1.0))
    var out := _hero(1, Vector3(0, 0, 12))
    var ally := _hero(0, Vector3(-4, 0, 0))
    var ab = n.abilities["ability2"]
    check(ab.activate() and ab.last_pulled == 2, "two enemies in range")
    check(far.velocity.x < -5.0 and far.velocity.y > 0.0, "far enemy pulled toward Niđo (v %s)" % far.velocity)
    check(far.slow_mult < 1.0 and far.slow_left > 0.0, "slowed")
    check(near_e.velocity.length() < 0.01 and near_e.slow_mult < 1.0, "enemy already close: not flung, still slowed")
    check(out.velocity.length() < 0.01 and out.slow_mult == 1.0, "out of range untouched")
    check(ally.velocity.length() < 0.01 and ally.slow_mult == 1.0, "allies untouched")
    far.velocity = Vector3.ZERO
    far.knockback_immune = true
    ab.cooldown.remaining = 0.0
    ab.activate()
    check(far.velocity.length() < 0.01, "knockback-immune targets are not moved")
    _free([n, far, near_e, out, ally])

func test_rollback_restores_hp_and_reduces_damage() -> void:
    var n := _hero(0, Vector3.ZERO)
    var ally := _hero(0, Vector3(3, 0, 0), "res://src/heroes/the_best.json")
    var far_ally := _hero(0, Vector3(30, 0, 0), "res://src/heroes/the_best.json")
    var enemy := _hero(1, Vector3(0, 0, 5))
    var ult = n.abilities["ultimate"]
    check(not ult.can_activate(), "needs a full meter")
    for i in 60:          # 1 s of history at full HP
        ult.tick(1.0 / 60.0)
    ally.take_damage(150.0, enemy, Vector3.ZERO, "primary")
    far_ally.take_damage(150.0, enemy, Vector3.ZERO, "primary")
    n.take_damage(100.0, enemy, Vector3.ZERO, "primary")
    enemy.take_damage(100.0, n, Vector3.ZERO, "primary")
    for i in 60:
        ult.tick(1.0 / 60.0)
    n.ult.add(100000.0)
    check(ult.activate(), "cast")
    near(ally.health.hp, ally.health.max_hp, 0.5, "ally back to its HP from a few seconds ago")
    near(n.health.hp, n.health.max_hp, 0.5, "Niđo too")
    check(far_ally.health.hp < far_ally.health.max_hp - 100.0, "out of radius: no rollback")
    check(enemy.health.hp < enemy.health.max_hp, "enemies untouched")
    var before := n.health.hp
    n.take_damage(100.0, enemy, Vector3.ZERO, "primary")
    ult.tick(1.0 / 60.0)
    near(before - n.health.hp, 65.0, 0.5, "35% damage reduction while active")
    for i in 5 * 60:
        ult.tick(1.0 / 60.0)
    before = n.health.hp
    n.take_damage(50.0, enemy, Vector3.ZERO, "primary")
    ult.tick(1.0 / 60.0)
    near(before - n.health.hp, 50.0, 0.5, "reduction ends")
    _free([n, ally, far_ally, enemy])

func test_rollback_never_undoes_a_death() -> void:
    var n := _hero(0, Vector3.ZERO)
    var ally := _hero(0, Vector3(2, 0, 0), "res://src/heroes/the_best.json")
    var ult = n.abilities["ultimate"]
    for i in 60:
        ult.tick(1.0 / 60.0)
    ally.take_damage(10000.0, null, Vector3.ZERO, "primary")
    for i in 30:
        ult.tick(1.0 / 60.0)
    n.ult.add(100000.0)
    ult.activate()
    check(ally.dead, "dead ally stays dead")
    _free([n, ally])
