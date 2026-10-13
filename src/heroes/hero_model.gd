class_name HeroModel
extends Node3D
## Skinned 3D hero model (GLB) with toon look, driven ONLY by replicated hero state via drive().
## Built from hero JSON "model_scene":
##   path, yaw_deg, scale, outline (width m), no_outline (material-name keys), tails (bone prefixes for sway),
##   wand_tip / fx_anchor (marker node name for beams/tracers),
##   aim_bones / cast_bones / upper_bones (bone-name prefixes filtering the aim pose, the default cast and
##   upper-body one-shots), melee {"swings": [anims], "finisher": anim, "full": [anims played full-body]},
##   casts {slot: {"anim": name, "full": bool}} (per-ability one-shot; default: "cast" on cast_bones).
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
var cfg: Dictionary = {}
var last_anim := ""          ## last one-shot fired (swing/cast/finisher...), for tests/debug
var _nodes: Dictionary = {}  ## swappable AnimationNodeAnimation per one-shot: cast/upper/action
const ARM_R := ["upper_arm.R", "forearm.R", "hand.R", "shoulder.R"]
const ARM_L_HEAD := ["upper_arm.L", "forearm.L", "hand.L", "shoulder.L", "head", "neck"]
const UPPER := ["spine", "chest", "neck", "head", "shoulder.", "upper_arm.", "forearm.", "hand."]

static func create(cfg: Dictionary) -> HeroModel:
    var ps: PackedScene = load(String(cfg.get("path", "")))
    if ps == null:
        return null
    var m := HeroModel.new()
    m.name = "HeroModel"
    m.scene = ps.instantiate()
    m.add_child(m.scene)
    m.rotation_degrees.y = float(cfg.get("yaw_deg", 180.0))
    m.scale = Vector3.ONE * float(cfg.get("scale", 1.0))
    m.cfg = cfg
    m._setup(cfg)
    return m

func _setup(cfg: Dictionary) -> void:
    ToonKit.apply(scene, float(cfg.get("outline", 0.008)), cfg.get("no_outline", []))
    var sks := scene.find_children("*", "Skeleton3D", true, false)
    skeleton = sks[0] if sks.size() > 0 else null
    var aps := scene.find_children("*", "AnimationPlayer", true, false)
    anim_player = aps[0] if aps.size() > 0 else null
    var wt := scene.find_children(String(cfg.get("fx_anchor", cfg.get("wand_tip", "WandTip"))), "Node3D", true, false)
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

func _oneshot(bt: AnimationNodeBlendTree, nm: String, anim: String, bones: Array, input: String, pos: Vector2) -> void:
    var a := _anim(anim)
    _nodes[nm] = a
    bt.add_node(nm + "_anim", a, pos + Vector2(0, 150))
    var os := AnimationNodeOneShot.new()
    if not bones.is_empty():
        os.filter_enabled = true
        for p in _bone_filter(bones):
            os.set_filter_path(p, true)
    os.fadein_time = 0.06
    os.fadeout_time = 0.15
    bt.add_node(nm, os, pos)
    bt.connect_node(nm, 0, input)
    bt.connect_node(nm, 1, nm + "_anim")

## idle <-> run (Blend2 "move") -> aim pose (filtered Blend2, held while shooting/healing) -> "cast" (filtered
## one-shot) -> "upper" (upper-body one-shot: melee swings) -> "action" (full-body one-shot: finisher, leap,
## roll ...). Death is played on a detached corpse copy (the live hero is hidden by core on death).
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
    var has_aim := anim_player.has_animation("aim")
    bt.add_node("aim_pose", _anim("aim" if has_aim else "idle"), Vector2(400, 250))
    var aim := AnimationNodeBlend2.new()
    aim.filter_enabled = true
    _arm_r = _bone_filter(cfg.get("aim_bones", ARM_R))
    for p in _arm_r:
        aim.set_filter_path(p, true)
    bt.add_node("aim", aim, Vector2(600, 100))
    bt.connect_node("aim", 0, "move")
    bt.connect_node("aim", 1, "aim_pose")
    _arm_l = cfg.get("cast_bones", ARM_L_HEAD)
    _oneshot(bt, "cast", "cast" if anim_player.has_animation("cast") else "idle", _arm_l, "aim", Vector2(800, 100))
    _oneshot(bt, "upper", "idle", cfg.get("upper_bones", UPPER), "cast", Vector2(1000, 100))
    _oneshot(bt, "action", "idle", [], "upper", Vector2(1200, 100))
    bt.connect_node("output", 0, "action")
    tree = AnimationTree.new()
    tree.name = "AnimationTree"
    tree.tree_root = bt
    scene.add_child(tree)
    tree.anim_player = tree.get_path_to(anim_player)
    tree.active = true

## Fires a one-shot: `slot` is "cast" (filtered), "upper" (upper body) or "action" (full body).
func play_oneshot(slot: String, anim: String) -> void:
    if tree == null or anim_player == null or not anim_player.has_animation(anim):
        return
    (_nodes[slot] as AnimationNodeAnimation).animation = anim
    tree.set("parameters/%s/request" % slot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
    last_anim = anim

## Per-frame visual update from replicated hero state (see Hero._process).
## st: run (0..1.5), fwd, side, air, shots (cumulative shot count), finisher (bool, from replicated combo_step),
## casts (cumulative), cast_slot (ability slot of the latest cast), healing (bool)
func drive(st: Dictionary, dt: float) -> void:
    if tree:
        var run: float = clampf(float(st.get("run", 0.0)), 0.0, 1.5)
        tree.set("parameters/move/blend_amount", clampf(run * 1.4, 0.0, 1.0))
        tree.set("parameters/run_speed/scale", maxf(0.6, run))
        var shots := int(st.get("shots", 0))
        if _shot_seq >= 0 and shots != _shot_seq:
            var melee: Dictionary = cfg.get("melee", {})
            if melee.is_empty():
                _aim = 1.0
            else:
                var swings: Array = melee.get("swings", [])
                var anim: String = String(melee.get("finisher", "")) if bool(st.get("finisher", false)) else (String(swings[shots % swings.size()]) if swings.size() > 0 else "")
                if anim != "":
                    play_oneshot("action" if melee.get("full", []).has(anim) else "upper", anim)
        _shot_seq = shots
        var target := 1.0 if bool(st.get("healing", false)) else 0.0
        _aim = maxf(target, _aim - dt / 0.6)
        tree.set("parameters/aim/blend_amount", _aim)
        var casts := int(st.get("casts", 0))
        if _cast_seq >= 0 and casts != _cast_seq:
            var spec: Dictionary = cfg.get("casts", {}).get(String(st.get("cast_slot", "")), {})
            play_oneshot("action" if bool(spec.get("full", false)) else "cast", String(spec.get("anim", "cast")))
        _cast_seq = casts
    if tails:
        tails.fwd = float(st.get("fwd", 0.0))
        tails.side = float(st.get("side", 0.0))
        tails.air = float(st.get("air", 0.0))
        tails.run = float(st.get("run", 0.0))

func aim_amount() -> float:
    return _aim

## Death on the live model (hero.keep_body_when_dead): the blend tree is paused and "death" plays to the end.
func play_death() -> void:
    if tree:
        tree.active = false
    if anim_player and anim_player.has_animation("death"):
        anim_player.play("death")
        last_anim = "death"

## Respawn: back to the replicated-state blend tree.
func revive() -> void:
    if anim_player:
        anim_player.stop()
    if tree:
        tree.active = true
    last_anim = ""
