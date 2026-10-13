extends "res://tests/test_base.gd"
## Twin Tails GLB model: loads, toon + outline, wand-tip beam anchor, replicated-state driving, primitive fallback.
const TT := "res://src/heroes/twin_tails.json"

func test_glb_model_loads_with_rig_and_anims() -> void:
    var h := Hero.from_def(TT)
    check(h.model != null and h.model.skeleton != null, "model + skeleton")
    check(h.model.anim_player != null, "animation player")
    for a in ["idle", "run", "shoot", "aim", "cast", "death"]:
        check(h.model.anim_player.has_animation(a), "anim " + a)
    var sk := h.model.skeleton
    for b in ["hips", "head", "hand.R", "thigh.L", "tail_4.L", "tail_4.R"]:
        check(sk.find_bone(b) >= 0, "bone " + b)
    check(h.model.tails != null and h.model.tails.chains.size() == 2, "two tail chains")
    check(h.model.wand_tip != null, "wand tip")
    h.free()

func test_tri_budget() -> void:
    var h := Hero.from_def(TT)
    var tris := 0
    for mi in h.model.find_children("*", "MeshInstance3D", true, false):
        var m: Mesh = mi.mesh
        for si in m.get_surface_count():
            var arr := m.surface_get_arrays(si)
            var idx = arr[Mesh.ARRAY_INDEX]
            tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
    check(tris >= 5000 and tris <= 15000, "tris in 5-15k (%d)" % tris)
    h.free()

func test_toon_and_outline_applied() -> void:
    var h := Hero.from_def(TT)
    var n := 0
    var outlined := 0
    for mi in h.model.find_children("*", "MeshInstance3D", true, false):
        for si in mi.mesh.get_surface_count():
            var m = mi.get_surface_override_material(si)
            check(m is ShaderMaterial and m.shader.resource_path.ends_with("toon.gdshader"), "toon material")
            n += 1
            if m.next_pass is ShaderMaterial:
                outlined += 1
    check(n >= 5 and outlined >= n - 3, "outline on body surfaces (%d/%d)" % [outlined, n])
    h.free()

func test_gameplay_parts_kept() -> void:
    var h := Hero.from_def(TT)
    var cols := 0
    for c in h.get_children():
        if c is CollisionShape3D:
            cols += 1
    check(cols == 1, "single collider")
    check(h._muzzle != null and h._muzzle.get_parent() == h, "muzzle kept on hero")
    check(h.model.find_children("*", "CollisionShape3D", true, false).is_empty(), "model has no collision")
    h.free()

func test_beam_origin_is_wand_tip() -> void:
    var root := Node3D.new()
    (Engine.get_main_loop() as SceneTree).root.add_child(root)
    var h := Hero.from_def(TT)
    root.add_child(h)
    h._process(1.0 / 60.0)
    check(h.beam_origin().distance_to(h.model.wand_tip.global_position) < 0.001, "beam starts at wand tip")
    root.free()

func test_puppet_drive_from_replicated() -> void:
    var h := Hero.from_def(TT)
    h.net_role = "puppet"
    h._process(1.0 / 60.0)
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

func test_primitive_fallback_flag() -> void:
    Hero.use_primitive_models = true
    var h := Hero.from_def(TT)
    check(h.model == null and h._anim_parts.size() >= 3, "fallback primitive model")
    h.free()
    Hero.use_primitive_models = false
