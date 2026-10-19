extends "res://tests/test_base.gd"
## Übel (fast melee dive, 250 HP; fan character, private play only - see src/heroes/ubel/README.md): kit data,
## GLB model (rig, anims incl. the mounted "ride", BladeTip anchor, side-ponytail sway), primitive fallback,
## Clean Cut strip geometry, and the client side of the ride replication (MountLink net prop -> puppet and
## predicted riders, ride pose). The 60 Hz ride behaviour is in heroes_ubel_sim.gd.
var tree: SceneTree
const DEF := "res://src/heroes/ubel.json"
const MountLink := preload("res://src/abilities/mount_link.gd")

func _hero(team := 0, pos := Vector3.ZERO, path := DEF) -> Hero:
    var h := Hero.from_def(path)
    h.team = team
    tree.root.add_child(h)
    h.global_position = pos
    return h

func _free(ns: Array) -> void:
    for n in ns:
        if is_instance_valid(n):
            n.free()

func test_kit_and_role() -> void:
    var h := Hero.from_def(DEF)
    check(h.def.name == "Übel" and h.def.id == "ubel" and h.def.role == "dive", "name/id/role")
    check(absf(h.health.max_hp - 250.0) < 0.01 and float(h.def.movement.speed) >= 7.5, "250 HP, fast")
    var p: Dictionary = h.def.primary
    check(p.type == "melee" and p.name == "Paper Cut" and p.combo == [1.0, 1.0, 2.0] and float(p.damage) == 25.0, "Paper Cut 25/25/50")
    var a: Dictionary = h.def.abilities
    check(a.ability1.type == "ride" and a.ability1.name == "Uninvited Guest" and float(a.ability1.ride_time) == 4.0, "Uninvited Guest = ride, 4 s")
    check(a.ability2.type == "line_slash" and a.ability2.name == "Clean Cut" and float(a.ability2.damage) == 60.0, "Clean Cut = line slash, 60")
    check(a.ultimate.type == "nova" and a.ultimate.name == "Last Smile" and a.ultimate.needs_ult, "Last Smile ult")
    check(AbilityRegistry.TYPES.has("ride") and AbilityRegistry.TYPES.has("line_slash"), "types registered")
    check(h._ride == h.abilities["ability1"], "hero found its ride ability")
    check(GameConfig.hero_ids().has("ubel"), "selectable")
    h.free()

func test_values_are_clean() -> void:
    var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEF))
    var vals := [d.max_hp, d.primary.damage, d.primary.fire_rate, d.primary.range, d.primary.lunge, d.ultimate_cost]
    for slot in d.abilities:
        for k in d.abilities[slot]:
            if d.abilities[slot][k] is float:
                vals.append(d.abilities[slot][k])
    for v in vals:
        check(is_equal_approx(snappedf(float(v), 0.1), float(v)), "clean value %s" % v)
    check(float(d.primary.damage) * float(d.primary.combo[-1]) == 50.0, "finisher 50")

func test_readme_fan_character_line() -> void:
    var t := FileAccess.get_file_as_string("res://src/heroes/ubel/README.md")
    check(t.contains("Fan character based on Übel (Frieren). Fine for private play; must be replaced with an original design before any commercial release."), "README line")

func test_glb_model() -> void:
    var h := Hero.from_def(DEF)
    check(h.model != null and h.model.skeleton != null and h.model.anim_player != null, "GLB model + rig")
    for an in ["idle", "run", "swing_a", "swing_b", "finisher", "cut", "leap", "ride", "spin", "death"]:
        check(h.model.anim_player.has_animation(an), "anim " + an)
    for b in ["hips", "head", "hand.R", "thigh.L", "pony_0.L", "pony_3.L"]:
        check(h.model.skeleton.find_bone(b) >= 0, "bone " + b)
    check(h.model.find_child("BladeTip", true, false) != null, "BladeTip anchor")
    check(h.model.tails != null, "side ponytail sway")
    var aabb := AABB()
    for mi in h.model.find_children("*", "MeshInstance3D", true, false):
        aabb = aabb.merge(mi.get_aabb()) if aabb.size != Vector3.ZERO else mi.get_aabb()
    h.free()
    var prev := Hero.use_primitive_models
    Hero.use_primitive_models = true
    var p := Hero.from_def(DEF)
    check(p.model == null and p._muzzle != null and p._anim_parts.size() > 0, "primitive fallback with muzzle + anim parts")
    p.free()
    Hero.use_primitive_models = prev

func test_ride_pose_blends_in_when_mounted() -> void:
    var h := _hero()
    h.model.drive({"run": 0.0, "riding": true}, 0.5)
    check(is_equal_approx(float(h.model.tree.get("parameters/ride/blend_amount")), 1.0), "ride pose on")
    h.model.drive({"run": 0.0, "riding": false}, 0.5)
    check(is_equal_approx(float(h.model.tree.get("parameters/ride/blend_amount")), 0.0), "ride pose off")
    _free([h])

func test_clean_cut_strip() -> void:
    var LS = load("res://src/abilities/line_slash.gd")
    var o := Vector3.ZERO
    var f := Vector3(0, 0, -1)
    check(LS.in_box(o, f, Vector3(0, 0, -5.9), 6.0, 1.2, 2.5), "far end in")
    check(not LS.in_box(o, f, Vector3(0, 0, -6.2), 6.0, 1.2, 2.5), "past the end out")
    check(LS.in_box(o, f, Vector3(0.55, 0, -3), 6.0, 1.2, 2.5) and not LS.in_box(o, f, Vector3(0.7, 0, -3), 6.0, 1.2, 2.5), "width 1.2")
    check(not LS.in_box(o, f, Vector3(0, 0, 1.0), 6.0, 1.2, 2.5), "behind out")
    check(not LS.in_box(o, f, Vector3(0, 3.0, -3), 6.0, 1.2, 2.5), "above height out")

func test_clean_cut_through_cover_and_spares_others() -> void:
    var u := _hero(0, Vector3(500, 0, 0))
    var foe := _hero(1, Vector3(500, 0, -4), "res://src/heroes/cob.json")
    var side := _hero(1, Vector3(503, 0, -3), "res://src/heroes/cob.json")
    var ally := _hero(0, Vector3(500, 0, -2), "res://src/heroes/cob.json")
    var wall := StaticBody3D.new()
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = Vector3(4, 3, 0.4)
    cs.shape = bs
    wall.add_child(cs)
    tree.root.add_child(wall)
    wall.global_position = Vector3(500, 1.5, -3)
    u.yaw = 0.0
    var hp := foe.health.hp
    check(u.abilities["ability2"].activate(), "cut fires")
    check(absf(hp - foe.health.hp - 60.0) < 0.01, "hits through the wall: %.1f" % (hp - foe.health.hp))
    check(side.health.hp == side.health.max_hp and ally.health.hp == ally.health.max_hp, "outside strip / ally spared")
    check(not u.abilities["ability2"].activate(), "on cooldown")
    _free([u, foe, side, ally, wall])

func test_no_target_no_cooldown() -> void:
    var u := _hero(0, Vector3(800, 0, 0))
    check(not u.abilities["ability1"].activate() and u.abilities["ability1"].cooldown.is_ready(), "nobody in range: no leap, no cooldown")
    var ally := _hero(0, Vector3(800, 0, -5), "res://src/heroes/cob.json")
    check(not u.abilities["ability1"].activate(), "allies are not ridden")
    _free([u, ally])

## Client view of a ride: the host's MountLink prop arrives as (kind, visual) -> Net.make_prop builds a MountLink,
## which maps rider -> victim by net id; puppets show the ride pose, the predicted local rider follows the head
## and replays no movement; the prop despawn ends it.
func test_net_replication_client_side() -> void:
    var rider := _hero(0, Vector3(900, 0, 0))
    var victim := _hero(1, Vector3(900, 0, -5), "res://src/heroes/cob.json")
    rider.net_role = "puppet"
    victim.net_role = "puppet"
    Net.register_as(rider, 900001)
    Net.register_as(victim, 900002)
    check(rider.mounted_on() == null, "not riding before the prop")
    # host side: what the ride ability announces
    var host_link = MountLink.build_prop(MountLink.kind_for(rider, victim), Vector3.ONE * 0.1, Color.WHITE)
    host_link.set_meta("net_kind", MountLink.kind_for(rider, victim))
    host_link.set_meta("net_visual", MountLink.PATH)
    var info := Net.prop_info(host_link, 1)
    check(info.kind == "mount:900001:900002" and info.visual == MountLink.PATH, "prop spawn info %s" % info)
    host_link.free()
    # client side
    var n := Net.make_prop(String(info.kind), info.size, info.color, String(info.visual))
    check(n != null and n.get_script() == MountLink, "client builds a MountLink")
    tree.root.add_child(n)
    check(rider.mounted_on() == victim and MountLink.victim_id_of(900001) == 900002, "puppet rider -> victim")
    check(victim.mounted_on() == null, "victim is not riding")
    rider._process(0.5)
    check(is_equal_approx(float(rider.model.tree.get("parameters/ride/blend_amount")), 1.0), "puppet shows the ride pose")
    # predicted local rider: follows the displayed head, no own movement in replays
    rider.net_role = "predicted"
    rider.input_source = FakeInput.new()
    var cfg := rider.effective_move_cfg()
    check(float(cfg.speed) == 0.0 and float(cfg.jump_velocity) == 0.0 and float(cfg.gravity) == 0.0, "no movement replay while mounted")
    for i in 30:
        rider._predict_step(1.0 / 60.0)
    var seat: Vector3 = victim.global_position + Vector3(0, float(victim.def.collider.height), 0)
    check(rider.global_position.distance_to(seat) < 0.05, "predicted rider sits on the head: %s vs %s" % [rider.global_position, seat])
    victim.global_position += Vector3(2, 0, 0)
    for i in 30:
        rider._predict_step(1.0 / 60.0)
    check(rider.global_position.distance_to(victim.global_position + Vector3(0, float(victim.def.collider.height), 0)) < 0.05, "follows the head smoothly")
    # despawn (ride over)
    n.free()
    check(rider.mounted_on() == null and MountLink.victim_id_of(900001) == -1, "prop gone -> not riding")
    check(float(rider.effective_move_cfg().speed) > 0.0, "movement back")
    _free([rider, victim])

class FakeInput:
    func poll(_h) -> InputFrame:
        return InputFrame.new()
