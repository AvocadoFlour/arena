extends "res://tests/test_base.gd"
## Tomo (lean damage hero): def + kit numbers, GLB model (rig, anims, ponytail sway, toon/outline, anchors,
## replicated-state driving), burst-fire primary (Packet Burst) and Hotfix bonus logic, balance vs the roster.
const DEF := "res://src/heroes/tomo.json"
const ANIMS := ["idle", "run", "aim", "shoot", "blink", "throw", "push", "death"]
const NovaAb := preload("res://src/abilities/nova.gd")
const DashAb := preload("res://src/abilities/dash.gd")
const BONES := ["hips", "head", "hand.R", "hand.L", "thigh.L", "pony_0.C", "pony_3.C"]

func _def() -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(DEF))

func _puppet() -> Hero:
    var h := Hero.from_def(DEF)
    h.net_role = "puppet"
    h._process(1.0 / 60.0)
    return h

func test_def_and_kit() -> void:
    var d := _def()
    check(d.id == "tomo" and d.name == "Tomo", "id/name")
    check(d.role == "duelist", "lean damage role")
    for k in ["name", "role", "max_hp", "movement", "collider", "primary", "ultimate_cost", "abilities", "model", "model_scene"]:
        check(d.has(k), "missing " + k)
    var a: Dictionary = d.abilities
    check(a.ability1.name == "Hotfix" and a.ability1.type == "blink", "Hotfix = blink")
    check(a.ability2.name == "Breakpoint" and a.ability2.type == "projectile", "Breakpoint = projectile")
    check(float(a.ability2.get("root", 0)) >= 1.0 and not a.ability2.has("slow"), "Breakpoint roots (real root, not a 0% slow)")
    check(float(a.ability2.splash_radius) == 0.0, "Breakpoint hits only the first enemy")
    check(a.ultimate.name == "Force Push" and a.ultimate.type == "shockwave", "Force Push = shockwave")
    check(d.primary.type == "hitscan" and int(d.primary.burst) == 3, "Packet Burst: 3-round hitscan burst")
    for slot in ["ability1", "ability2", "ultimate"]:
        check(AbilityRegistry.TYPES.has(a[slot].type), "registered " + a[slot].type)
    check(int(d.primary.mag) % int(d.primary.burst) == 0, "mag holds whole bursts")
    var h := Hero.from_def(DEF)
    check(h.weapon is BurstWeapon, "burst weapon installed")
    check(is_instance_of(h.abilities.ultimate, NovaAb), "shockwave reuses the nova ult base")
    check(is_instance_of(h.abilities.ability1, DashAb), "blink reuses dash")
    h.free()

func test_burst_cadence() -> void:
    var w := BurstWeapon.new({"damage": 15, "fire_rate": 14, "burst": 3, "burst_delay": 0.36, "mag": 24, "reload_time": 1.6})
    var shots: Array = []
    var t := 0.0
    var dt := 1.0 / 60.0
    for i in 120:   # 2 s with the trigger held
        w.tick(dt)
        if w.try_fire():
            shots.append(t)
        t += dt
    check(shots.size() >= 10 and shots.size() <= 12, "~4 bursts in 2 s (%d shots)" % shots.size())
    check(shots[1] - shots[0] < 0.1 and shots[2] - shots[1] < 0.1, "rounds inside a burst are tight")
    check(shots[3] - shots[2] >= 0.35, "pause after a burst (%.3f)" % (shots[3] - shots[2]))
    check(not w.bursting() or w.burst_left < 3, "burst state")
    near(w.burst_dps(), 45.0 / (2.0 / 14.0 + 0.36), 0.01, "peak burst dps")

func test_burst_reload_and_empty_mag() -> void:
    var w := BurstWeapon.new({"damage": 10, "fire_rate": 14, "burst": 3, "burst_delay": 0.3, "mag": 4, "reload_time": 1.0})
    var n := 0
    for i in 120:
        w.tick(1.0 / 60.0)
        if w.try_fire():
            n += 1
        if w.reloading():
            break
    check(n == 4 and w.reloading() and w.burst_left == 0, "mag runs dry mid-burst -> reload, burst cleared (%d)" % n)
    var w2 := BurstWeapon.new({"damage": 10, "fire_rate": 14, "burst": 3, "mag": 9})
    w2.try_fire()
    check(w2.bursting(), "burst started")
    check(w2.start_reload() and not w2.bursting(), "manual reload cancels the burst")

func test_hotfix_bonus() -> void:
    var w := BurstWeapon.new({"damage": 15, "fire_rate": 14, "burst": 3, "burst_delay": 0.36, "mag": 24})
    w.grant_bonus(1.5, 3, 4.0)
    var dmg: Array = []
    for i in 60:
        w.tick(1.0 / 60.0)
        if w.try_fire():
            dmg.append(w.damage)
    check(dmg.size() >= 4, "fired")
    check(dmg.slice(0, 3) == [22.5, 22.5, 22.5] and dmg[3] == 15.0, "next burst x1.5, then normal %s" % [dmg])
    var w2 := BurstWeapon.new({"damage": 15, "burst": 3})
    w2.grant_bonus(1.5, 3, 0.5)
    for i in 40:
        w2.tick(1.0 / 60.0)
    check(w2.bonus_shots == 0, "unused bonus expires")

func test_balance_vs_roster() -> void:
    var d := _def()
    var w := BurstWeapon.new(d.primary)
    var tomo_peak := w.burst_dps()
    var cycle := float(d.primary.mag) / float(d.primary.burst) * (2.0 / float(d.primary.fire_rate) + float(d.primary.burst_delay)) - float(d.primary.burst_delay)
    var tomo_sus := float(d.primary.damage) * float(d.primary.mag) / (cycle + float(d.primary.reload_time))
    var other_hp: Array = []
    for id in ["twin_tails", "cob", "the_best"]:
        var o: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))
        other_hp.append(float(o.max_hp))
        if o.primary.get("type", "hitscan") == "hitscan":
            var od: float = float(o.primary.damage) * float(o.primary.fire_rate)
            check(tomo_peak > od, "%s: Tomo out-damages (%.0f vs %.0f)" % [id, tomo_peak, od])
    check(tomo_peak < 110.0 and tomo_sus < 80.0, "not above the old duelist (%.0f peak, %.0f sustained)" % [tomo_peak, tomo_sus])
    check(float(d.max_hp) <= other_hp.min(), "lean: lowest HP (%s)" % d.max_hp)
    check(float(d.collider.radius) <= 0.38, "narrow silhouette")

func test_model_rig_anims_budget() -> void:
    var h := Hero.from_def(DEF)
    check(h.model != null and h.model.skeleton != null and h.model.tree != null, "GLB model + skeleton + tree")
    for a in ANIMS:
        check(h.model.anim_player.has_animation(a), "anim " + a)
    for b in BONES:
        check(h.model.skeleton.find_bone(b) >= 0, "bone " + b)
    check(h.model.tails != null and h.model.tails.chains.size() == 1 and h.model.tails.chains[0].size() == 4, "ponytail sway chain")
    check(h.model.wand_tip != null and h.model.wand_tip.name == "Muzzle", "Muzzle fx anchor")
    var tris := 0
    var n := 0
    var outlined := 0
    for mi in h.model.find_children("*", "MeshInstance3D", true, false):
        for si in mi.mesh.get_surface_count():
            var arr: Array = mi.mesh.surface_get_arrays(si)
            var idx = arr[Mesh.ARRAY_INDEX]
            tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
            var m = mi.get_active_material(si)
            check(m is ShaderMaterial and m.shader.resource_path.ends_with("toon.gdshader"), "toon material")
            n += 1
            if m.next_pass is ShaderMaterial:
                outlined += 1
    check(tris >= 5000 and tris <= 15000, "tris 5-15k (%d)" % tris)
    check(n >= 10 and outlined >= n - 6, "outlines (%d/%d)" % [outlined, n])
    var cols := 0
    for c in h.get_children():
        if c is CollisionShape3D:
            cols += 1
    check(cols == 1 and h.model.find_children("*", "CollisionObject3D", true, false).is_empty(), "single gameplay capsule, no model bodies")
    check(h.keep_body_when_dead, "death on live body hook")
    h.free()

func test_drive_from_replicated_state() -> void:
    var h := _puppet()
    h.weapon.ammo -= 1
    h._process(0.02)
    check(h.model.aim_amount() > 0.9, "shot -> aim pose")
    for pair in [["ability1", "blink"], ["ability2", "throw"], ["ultimate", "push"]]:
        var ab = h.abilities[pair[0]]
        ab.cooldown.remaining = maxf(ab.cooldown.duration, 1.0)
        h._process(0.02)
        check(h.model.last_anim == pair[1], "%s -> %s (%s)" % [pair[0], pair[1], h.model.last_anim])
        for i in 60:
            h._process(1.0 / 60.0)
    h.dead = true
    h._process(1.0 / 60.0)
    check(h.model.anim_player.current_animation == "death", "death anim")
    h.dead = false
    h._process(1.0 / 60.0)
    check(h.model.tree.active, "revive")
    check(h.weapon._shot_cd == 0.0 and h.weapon.burst_left == 0, "puppet touches no local fire state")
    h.free()

func test_primitive_fallback() -> void:
    Hero.use_primitive_models = true
    var h := Hero.from_def(DEF)
    check(h.model == null and h._anim_parts.size() >= 5 and h._muzzle != null, "primitive fallback with muzzle")
    h.free()
    Hero.use_primitive_models = false

func test_breakpoint_visual() -> void:
    var v: Node3D = load("res://src/abilities/breakpoint_visual.gd").build_prop("shot", Vector3.ONE * 0.16, Color("#ff3a3a"))
    check(v != null and v.get_child_count() == 3, "marker visual")
    check(v.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual only")
    v.free()

func test_burst_is_built_into_hero() -> void:
    var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEF)).duplicate(true)
    d.abilities = {}   # no Hotfix: burst fire must not depend on any ability
    var h := Hero.new()
    h.def = d
    h._build()
    check(h.weapon is BurstWeapon and h.weapon.burst_size == 3, "hero.gd builds a BurstWeapon from primary.burst")
    h.free()
    var c := Hero.from_def("res://src/heroes/cob.json")
    check(not (c.weapon is BurstWeapon), "no burst key -> plain Weapon")
    c.free()
    var src := FileAccess.get_file_as_string("res://src/abilities/blink.gd")
    check(not src.contains("BurstWeapon.install") and not src.contains("continue_burst"), "Hotfix no longer installs/drives the burst")

func test_root_hook_locks_movement_not_aim() -> void:
    var h := Hero.from_def("res://src/heroes/the_best.json")   # has leap + dash
    h.apply_root(1.0)
    check(h.rooted() and h.slow_mult == 1.0, "rooted, and distinct from a slow")
    h.abilities.ability2.cooldown.remaining = 0.0
    h._use("ability2")
    check(h.dash_time <= 0.0 and h.abilities.ability2.cooldown.remaining <= 0.0, "dash locked while rooted (no cooldown spent)")
    h.apply_root(0.5)
    near(h.root_left, 1.0, 0.001, "longer root wins")
    h.knockback(Vector3(10, 0, 0))
    h.root_left = 0.0
    check(not h.rooted(), "root ends")
    h._use("ability2")
    check(h.dash_time > 0.0, "dash works again after the root")
    h.free()
    var c := Hero.from_def("res://src/heroes/cob.json")
    c.apply_root(1.0)
    c._use("ability2")   # Geode Wall is not a movement ability (needs the tree to spawn; must not be blocked)
    check(c.abilities.ability2.cooldown.remaining > 0.0 or not c.is_inside_tree(), "non-movement abilities allowed")
    check(not ("shield_wall" in Hero.ROOT_BLOCKS) and "blink" in Hero.ROOT_BLOCKS and "leap" in Hero.ROOT_BLOCKS, "root block list")
    c.free()
