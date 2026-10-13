extends "res://tests/test_base.gd"
## Skinned GLB hero models (Twin Tails, The Best, Cob): load, rig + anims, tri budget, toon + outline,
## gameplay parts untouched, anchors, driving ONLY from replicated state, primitive fallback.
const TT := "res://src/heroes/twin_tails.json"
const ANIMS := {
    "twin_tails": ["idle", "run", "shoot", "aim", "cast", "death"],
    "the_best": ["idle", "run", "swing_a", "swing_b", "finisher", "leap", "dash", "ult", "death"],
    "cob": ["idle", "run", "shoot", "aim", "roll", "wall", "slam", "death"],
}
const BONES := {
    "twin_tails": ["hips", "head", "hand.R", "thigh.L", "tail_4.L", "tail_4.R"],
    "the_best": ["hips", "head", "hand.R", "thigh.L", "cape_2.L", "cape_2.R"],
    "cob": ["body", "head", "mandible.L", "mandible.R", "leg_f_1.L", "leg_m_1.R", "leg_b_1.L"],
}

func _def(id: String) -> String:
    return "res://src/heroes/%s.json" % id

func _puppet(id: String) -> Hero:
    var h := Hero.from_def(_def(id))
    h.net_role = "puppet"
    h._process(1.0 / 60.0)   # baseline frame
    return h

## Simulates the replicated cooldown jump of `slot` (as Net._apply_state writes cds), then one frame.
func _cast(h: Hero, slot: String) -> void:
    var ab = h.abilities[slot]
    ab.cooldown.remaining = maxf(ab.cooldown.duration, 1.0)
    h._process(0.02)

func test_glb_models_load_with_rig_and_anims() -> void:
    for id in ANIMS:
        var h := Hero.from_def(_def(id))
        check(h.model != null and h.model.skeleton != null, id + ": model + skeleton")
        check(h.model.anim_player != null and h.model.tree != null, id + ": animation player + tree")
        for a in ANIMS[id]:
            check(h.model.anim_player.has_animation(a), "%s: anim %s" % [id, a])
        for b in BONES[id]:
            check(h.model.skeleton.find_bone(b) >= 0, "%s: bone %s" % [id, b])
        h.free()
    var t := Hero.from_def(TT)
    check(t.model.tails != null and t.model.tails.chains.size() == 2, "twin_tails: two tail chains")
    check(t.model.wand_tip != null, "twin_tails: wand tip")
    t.free()
    var b := Hero.from_def(_def("the_best"))
    check(b.model.tails != null and b.model.tails.chains.size() == 2, "the_best: two cape chains sway")
    b.free()

func test_tri_budget() -> void:
    for id in ANIMS:
        var h := Hero.from_def(_def(id))
        var tris := 0
        for mi in h.model.find_children("*", "MeshInstance3D", true, false):
            var m: Mesh = mi.mesh
            for si in m.get_surface_count():
                var arr := m.surface_get_arrays(si)
                var idx = arr[Mesh.ARRAY_INDEX]
                tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
        check(tris >= 5000 and tris <= 15000, "%s: tris in 5-15k (%d)" % [id, tris])
        h.free()

func test_toon_and_outline_applied() -> void:
    for id in ANIMS:
        var h := Hero.from_def(_def(id))
        var n := 0
        var outlined := 0
        for mi in h.model.find_children("*", "MeshInstance3D", true, false):
            for si in mi.mesh.get_surface_count():
                var m = mi.get_active_material(si)
                check(m is ShaderMaterial and m.shader.resource_path.ends_with("toon.gdshader"), id + ": toon material")
                n += 1
                if m.next_pass is ShaderMaterial:
                    outlined += 1
                    check(float(m.next_pass.get_shader_parameter("width")) >= 0.01, id + ": outline at least 1 cm")
        check(n >= 5 and outlined >= n - 3, "%s: outline on body surfaces (%d/%d)" % [id, outlined, n])
        h.free()

func test_gameplay_parts_kept() -> void:
    for id in ANIMS:
        var h := Hero.from_def(_def(id))
        var cols: Array = []
        for c in h.get_children():
            if c is CollisionShape3D:
                cols.append(c)
        check(cols.size() == 1 and cols[0].shape is CapsuleShape3D, id + ": single capsule collider")
        var cfg: Dictionary = h.def.collider
        check(is_equal_approx(cols[0].shape.radius, float(cfg.radius)) and is_equal_approx(cols[0].shape.height, float(cfg.height)), id + ": collider size from def")
        check(h._muzzle != null and h._muzzle.get_parent() == h, id + ": muzzle kept on hero")
        check(h.model.find_children("*", "CollisionShape3D", true, false).is_empty(), id + ": model has no collision")
        check(h.model.find_children("*", "CollisionObject3D", true, false).is_empty(), id + ": model has no bodies")
        h.free()

func test_anchors() -> void:
    var root := Node3D.new()
    (Engine.get_main_loop() as SceneTree).root.add_child(root)
    var t := Hero.from_def(TT)
    root.add_child(t)
    t._process(1.0 / 60.0)
    check(t.beam_origin().distance_to(t.model.wand_tip.global_position) < 0.001, "twin_tails: beam starts at wand tip")
    var c := Hero.from_def(_def("cob"))
    root.add_child(c)
    c.global_position = Vector3(5, 0, 0)
    c._process(1.0 / 60.0)
    check(c.model.wand_tip != null and c.model.wand_tip.name == "Muzzle", "cob: crystal muzzle marker")
    check(c.beam_origin().distance_to(c.model.wand_tip.global_position) < 0.001, "cob: tracers leave the shooter crystal")
    check(c.model.wand_tip.global_position.distance_to(c._muzzle.global_position) < 0.35, "cob: crystal near the gameplay muzzle %s vs %s" % [c.model.wand_tip.global_position - c.global_position, c._muzzle.global_position - c.global_position])
    var b := Hero.from_def(_def("the_best"))
    root.add_child(b)
    b.global_position = Vector3(-5, 0, 0)
    b._process(1.0 / 60.0)
    check(b.beam_origin().distance_to(b._muzzle.global_position) < 0.001, "the_best: no fx anchor -> gameplay muzzle")
    root.free()

func test_twin_tails_drive_from_replicated() -> void:
    var h := _puppet("twin_tails")
    check(h.model.aim_amount() == 0.0, "no aim at rest")
    h.weapon.ammo -= 1          # replicated ammo drop = a shot
    h._process(0.02)
    check(h.model.aim_amount() > 0.9, "shot -> aim pose")
    for i in 60:
        h._process(1.0 / 60.0)
    check(h.model.aim_amount() < 0.05, "aim decays")
    for ab in h.abilities.values():   # replicated cooldown just started = beam channel active
        if ab.has_method("channel_visible"):
            ab.cooldown.remaining = ab.cooldown.duration - 0.05
    for i in 30:
        h._process(1.0 / 60.0)
    check(h.model.aim_amount() > 0.9, "healing holds aim")
    check(h.combo_step == 0 and h.weapon._shot_cd == 0.0, "no local-only state touched")
    h.free()

func test_the_best_combo_and_casts_from_replicated() -> void:
    var h := _puppet("the_best")
    var seen: Array = []
    for step in [1, 2, 3, 1]:          # replicated post-swing combo_step; 3 = finisher (combo of 3)
        h.combo_step = step
        h.weapon.ammo -= 1
        h._process(0.02)
        seen.append(h.model.last_anim)
        for i in 30:
            h._process(1.0 / 60.0)
    check(seen[0] != seen[1] and seen[0].begins_with("swing_") and seen[1].begins_with("swing_"), "swings alternate %s" % [seen])
    check(seen[2] == "finisher", "finisher slam from replicated combo_step (%s)" % seen[2])
    check(seen[3].begins_with("swing_"), "combo restarts with a swing")
    check(h.model.aim_amount() == 0.0, "melee never uses the aim pose")
    for pair in [["ability1", "leap"], ["ability2", "dash"], ["ultimate", "ult"]]:
        _cast(h, pair[0])
        check(h.model.last_anim == pair[1], "%s -> %s (%s)" % [pair[0], pair[1], h.model.last_anim])
        for i in 60:
            h._process(1.0 / 60.0)
    check(h.weapon._shot_cd == 0.0, "no local-only state touched")
    h.free()

func test_cob_shoot_and_casts_from_replicated() -> void:
    var h := _puppet("cob")
    h.weapon.ammo -= 1
    h._process(0.02)
    check(h.model.aim_amount() > 0.9, "shot -> head/mandible aim pose")
    for pair in [["ability1", "roll"], ["ability2", "wall"], ["ultimate", "slam"]]:
        _cast(h, pair[0])
        check(h.model.last_anim == pair[1], "%s -> %s (%s)" % [pair[0], pair[1], h.model.last_anim])
        for i in 60:
            h._process(1.0 / 60.0)
    h.velocity = Vector3(0, 0, -5.8)   # replicated velocity -> walk/run gait
    for i in 10:
        h._process(1.0 / 60.0)
    check(float(h.model.tree.get("parameters/move/blend_amount")) > 0.9, "gait from replicated velocity")
    h.free()

func test_death_plays_on_live_body() -> void:
    for id in ANIMS:
        var h := _puppet(id)
        check(h.keep_body_when_dead, id + ": uses core keep_body_when_dead hook")
        h.dead = true             # replicated dead flag
        h._process(1.0 / 60.0)
        check(h.model.anim_player.current_animation == "death" and not h.model.tree.active, id + ": live body plays death")
        h.dead = false            # respawn
        h._process(1.0 / 60.0)
        check(h.model.tree.active and h.model.last_anim == "", id + ": back to blend tree on respawn")
        h.free()
    Hero.use_primitive_models = true
    var p := Hero.from_def(_def("cob"))
    check(not p.keep_body_when_dead, "primitive fallback keeps the default hide-on-death")
    p.free()
    Hero.use_primitive_models = false

func test_primitive_fallback_flag() -> void:
    Hero.use_primitive_models = true
    for id in ANIMS:
        var h := Hero.from_def(_def(id))
        check(h.model == null and h._anim_parts.size() >= 3, id + ": fallback primitive model")
        h.free()
    Hero.use_primitive_models = false

## Poses the skeleton from `anim` at time `t` by sampling the rotation/position tracks (no tree needed).
func _pose(h: Hero, anim: String, t: float) -> Skeleton3D:
    var sk: Skeleton3D = h.model.skeleton
    sk.reset_bone_poses()
    var a: Animation = h.model.anim_player.get_animation(anim)
    for ti in a.get_track_count():
        var bn := String(a.track_get_path(ti).get_concatenated_subnames())
        var bi := sk.find_bone(bn)
        if bi < 0:
            continue
        match a.track_get_type(ti):
            Animation.TYPE_ROTATION_3D:
                sk.set_bone_pose_rotation(bi, a.rotation_track_interpolate(ti, t))
            Animation.TYPE_POSITION_3D:
                sk.set_bone_pose_position(bi, a.position_track_interpolate(ti, t))
    return sk

func _gp(sk: Skeleton3D, bone: String) -> Transform3D:   # composed by hand (works outside the tree)
    var bi := sk.find_bone(bone)
    var xf := Transform3D.IDENTITY
    while bi >= 0:
        xf = sk.get_bone_pose(bi) * xf
        bi = sk.get_bone_parent(bi)
    return xf

func test_the_best_v2_poses() -> void:
    var h := Hero.from_def(_def("the_best"))
    for b in ["fingers.L", "fingers.R", "index.L", "index.R"]:
        check(h.model.skeleton.find_bone(b) >= 0, "the_best: hand bone %s" % b)
    # idle: sword hand up at the RIGHT shoulder (model right = -X), not across the chest
    var sk := _pose(h, "idle", 0.0)
    var hand := _gp(sk, "hand.R").origin
    check(hand.y > 1.3 and hand.x < -0.12, "idle: right hand at the shoulder %s" % hand)
    # ult: left index finger straight forward (+Z), other fingers curled
    sk = _pose(h, "ult", 0.5)
    var idx_dir := _gp(sk, "index.L").basis.y.normalized()
    var fng_dir := _gp(sk, "fingers.L").basis.y.normalized()
    check(idx_dir.z > 0.6 and fng_dir.z < idx_dir.z - 0.5, "ult: pointing index %s vs fingers %s" % [idx_dir, fng_dir])
    # swings + finisher: wind-up -> hit -> follow-through keep travelling the same way (sweep / chop)
    for spec in [["swing_a", 3.0, 7.0, 10.0, Vector3.RIGHT], ["swing_b", 3.0, 7.0, 10.0, Vector3.LEFT], ["finisher", 7.0, 10.0, 13.0, Vector3.DOWN]]:
        var a: Animation = h.model.anim_player.get_animation(spec[0])
        var ax: Vector3 = spec[4]
        var p_ant := _gp(_pose(h, spec[0], spec[1] / 24.0), "hand.R").origin.dot(ax)
        var p_hit := _gp(_pose(h, spec[0], spec[2] / 24.0), "hand.R").origin.dot(ax)
        var p_fol := _gp(_pose(h, spec[0], spec[3] / 24.0), "hand.R").origin.dot(ax)
        check(p_ant < p_hit - 0.1 and p_fol > p_hit + 0.03, "%s: wind-up %.2f -> hit %.2f -> follow-through %.2f" % [spec[0], p_ant, p_hit, p_fol])
        check(a.length <= (0.9 if spec[0] != "finisher" else 1.2), "%s: length %.2f s" % [spec[0], a.length])
    h.free()
