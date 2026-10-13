class_name HeroModel
extends Node3D
## Skinned 3D hero model (GLB) with toon look, driven ONLY by replicated hero state via drive().
## Built from hero JSON "model_scene": {"path", "yaw_deg", "outline", "no_outline", "tails", "wand_tip"}.
## Visual-only and client-side: never affects gameplay, collision or networking.
var scene: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var tails: TailSway
var wand_tip: Node3D
var _shot_seq := -1
var _cast_seq := -1
var _aim := 0.0
var _arm_r: Array = []
var _arm_l: Array = []

static func create(cfg: Dictionary) -> HeroModel:
    var ps: PackedScene = load(String(cfg.get("path", "")))
    if ps == null:
        return null
    var m := HeroModel.new()
    m.name = "HeroModel"
    m.scene = ps.instantiate()
    m.add_child(m.scene)
    m.rotation_degrees.y = float(cfg.get("yaw_deg", 180.0))
    m._setup(cfg)
    return m

func _setup(cfg: Dictionary) -> void:
    ToonKit.apply(scene, float(cfg.get("outline", 0.008)), cfg.get("no_outline", []))
    var sks := scene.find_children("*", "Skeleton3D", true, false)
    skeleton = sks[0] if sks.size() > 0 else null
    var aps := scene.find_children("*", "AnimationPlayer", true, false)
    anim_player = aps[0] if aps.size() > 0 else null
    var wt := scene.find_children(String(cfg.get("wand_tip", "WandTip")), "Node3D", true, false)
    wand_tip = wt[0] if wt.size() > 0 else null
    for mi in scene.find_children("*", "MeshInstance3D", true, false):
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    if skeleton and cfg.has("tails"):
        tails = TailSway.new()
        tails.name = "TailSway"
        skeleton.add_child(tails)
        tails.setup(skeleton, cfg.tails)
    if anim_player:
        _build_tree()

func _bone_filter(prefixes: Array) -> Array:
    var out: Array = []
    if skeleton == null:
        return out
    var sk_path := String(scene.get_path_to(skeleton))
    for i in skeleton.get_bone_count():
        var bn := skeleton.get_bone_name(i)
        if prefixes.any(func(p): return bn.begins_with(p)):
            out.append(NodePath(sk_path + ":" + bn))
    return out

func _anim(name: String) -> AnimationNodeAnimation:
    var a := AnimationNodeAnimation.new()
    a.animation = name
    return a

## idle <-> run (Blend2 "move"), right-arm aim/heal pose (Blend2 "aim", filtered), left-arm cast
## (OneShot "cast", filtered). Death is played on a detached corpse copy (the live hero is hidden).
func _build_tree() -> void:
    var bt := AnimationNodeBlendTree.new()
    bt.add_node("idle", _anim("idle"), Vector2(0, 0))
    bt.add_node("run", _anim("run"), Vector2(0, 150))
    var run_speed := AnimationNodeTimeScale.new()
    bt.add_node("run_speed", run_speed, Vector2(200, 150))
    bt.connect_node("run_speed", 0, "run")
    var move := AnimationNodeBlend2.new()
    bt.add_node("move", move, Vector2(400, 50))
    bt.connect_node("move", 0, "idle")
    bt.connect_node("move", 1, "run_speed")
    bt.add_node("aim_pose", _anim("aim"), Vector2(400, 250))
    var aim := AnimationNodeBlend2.new()
    aim.filter_enabled = true
    _arm_r = _bone_filter(["upper_arm.R", "forearm.R", "hand.R", "shoulder.R"])
    for p in _arm_r:
        aim.set_filter_path(p, true)
    bt.add_node("aim", aim, Vector2(600, 100))
    bt.connect_node("aim", 0, "move")
    bt.connect_node("aim", 1, "aim_pose")
    bt.add_node("cast_anim", _anim("cast"), Vector2(600, 300))
    var cast := AnimationNodeOneShot.new()
    cast.filter_enabled = true
    _arm_l = _bone_filter(["upper_arm.L", "forearm.L", "hand.L", "shoulder.L", "head", "neck"])
    for p in _arm_l:
        cast.set_filter_path(p, true)
    cast.fadein_time = 0.08
    cast.fadeout_time = 0.15
    bt.add_node("cast", cast, Vector2(800, 150))
    bt.connect_node("cast", 0, "aim")
    bt.connect_node("cast", 1, "cast_anim")
    bt.connect_node("output", 0, "cast")
    tree = AnimationTree.new()
    tree.name = "AnimationTree"
    tree.tree_root = bt
    scene.add_child(tree)
    tree.anim_player = tree.get_path_to(anim_player)
    tree.active = true

## Per-frame visual update from replicated hero state (see Hero._process).
## st: run (0..1.5), fwd, side, air, shots (cumulative shot count), casts (cumulative), healing (bool)
func drive(st: Dictionary, dt: float) -> void:
    if tree:
        var run: float = clampf(float(st.get("run", 0.0)), 0.0, 1.5)
        tree.set("parameters/move/blend_amount", clampf(run * 1.4, 0.0, 1.0))
        tree.set("parameters/run_speed/scale", maxf(0.6, run))
        var shots := int(st.get("shots", 0))
        if _shot_seq >= 0 and shots != _shot_seq:
            _aim = 1.0
        _shot_seq = shots
        var target := 1.0 if bool(st.get("healing", false)) else 0.0
        _aim = maxf(target, _aim - dt / 0.6)
        tree.set("parameters/aim/blend_amount", _aim)
        var casts := int(st.get("casts", 0))
        if _cast_seq >= 0 and casts != _cast_seq:
            tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
        _cast_seq = casts
    if tails:
        tails.fwd = float(st.get("fwd", 0.0))
        tails.side = float(st.get("side", 0.0))
        tails.air = float(st.get("air", 0.0))
        tails.run = float(st.get("run", 0.0))

func aim_amount() -> float:
    return _aim

## Client-side death: a detached copy of the model plays "death" where the hero fell, then fades/frees.
func spawn_corpse(world: Node, xf: Transform3D, cfg: Dictionary, life: float = 2.0) -> HeroModel:
    if world == null:
        return null
    var c := HeroModel.create(cfg)
    if c == null:
        return null
    c.name = "Corpse"
    if c.tree:
        c.tree.active = false
    world.add_child(c)
    c.global_transform = xf * Transform3D(Basis(Vector3.UP, deg_to_rad(float(cfg.get("yaw_deg", 180.0)))), Vector3.ZERO)
    if c.anim_player:
        c.anim_player.play("death")
    c.get_tree().create_timer(life).timeout.connect(c.queue_free)
    return c
