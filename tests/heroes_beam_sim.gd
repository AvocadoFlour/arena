extends Node3D
## Encore Beam ribbon on PUPPETS: only replicated snapshot fields are written (position, yaw, pitch,
## team, dead, ability cooldown.remaining) - exactly what Net._apply_state / interpolation set on clients.
var results: Array = []
var done := false
var t := 0.0
var step := 0
var tt: Hero
var ally: Hero
var ab
var cam: Camera3D

func _rec(n: String, ok: bool, info: String = "") -> void:
    results.append([n, ok, info])

func _puppet(path: String, team: int, pos: Vector3) -> Hero:
    var h := Hero.from_def(path)
    h.net_role = "puppet"
    h.team = team
    add_child(h)
    h.set_team(team)
    h.global_position = pos
    return h

func _ready() -> void:
    tt = _puppet("res://src/heroes/twin_tails.json", 0, Vector3(0, 0, 0))
    ally = _puppet("res://src/heroes/the_best.json", 0, Vector3(0, 0, -8))
    tt.yaw = 0.0
    tt.rotation.y = 0.0
    ab = tt.abilities["ability1"]
    cam = Camera3D.new()       # over-the-shoulder view like CameraRig
    add_child(cam)
    cam.global_position = Vector3(0.6, 2.2, 3.2)
    cam.look_at(Vector3(0, 1.2, -6))

func _alpha() -> float:
    return ab.vis_alpha

func _process(dt: float) -> void:
    if done:
        return
    t += dt
    match step:
        0:
            if t > 0.2:
                _rec("idle_no_ribbon", ab.ribbon == null or not ab.ribbon.visible)
                ab.cooldown.remaining = ab.cooldown.duration   # snapshot: Encore Beam just used
                step = 1
                t = 0.0
        1:
            if t > 0.3:
                _rec("ribbon_visible_on_puppet", ab.ribbon != null and ab.ribbon.visible and _alpha() > 0.99)
                _rec("targets_ally", ab.vis_target == ally)
                var a: Vector3 = ab.beam_start()
                var b: Vector3 = ab.beam_end()
                var mid: Vector3 = ab.ribbon.global_position
                _rec("starts_at_mic_wand", a.distance_to(tt.beam_origin()) < 0.01 and (tt.model == null or a.distance_to(tt.model.wand_tip.global_position) < 0.01) and a.z < -0.5, "start=%s" % a)
                _rec("ends_at_target_chest", b.distance_to(ally.global_position + Vector3(0, 1, 0)) < 0.01)
                var kids: Array = ab.ribbon.get_children()
                var first: MeshInstance3D = kids[0]
                var last: MeshInstance3D = kids[kids.size() - 1]
                _rec("spans_full_length", kids.size() == ab.SEG * 2 and ab.wave_point(a, b, 0.0).distance_to(a) < 0.001 and ab.wave_point(a, b, 1.0).distance_to(b) < 0.001
                    and first.global_position.distance_to(a) < a.distance_to(b) / ab.SEG and last.global_position.distance_to(b) < a.distance_to(b) / ab.SEG and mid.distance_to((a + b) * 0.5) < 0.01)
                _rec("wave_has_screen_height", kids.any(func(k): return absf(k.global_position.y - a.lerp(b, 0.5).y) > 0.1), "sound-wave ribbon")
                # visibility: drawn over everything (never occluded by the healer's model), in front of camera,
                # on screen, and the visible span is mostly outside the healer's own model bounds.
                var m: StandardMaterial3D = ab.ribbon.get_child(0).material_override
                _rec("not_depth_occluded", m.no_depth_test and ab.ribbon.get_children().all(func(c): return c.material_override.no_depth_test))
                var sp := cam.unproject_position(mid)
                _rec("on_screen_in_front", not cam.is_position_behind(mid) and sp.x > 0 and sp.y > 0, "screen=%s" % sp)
                var outside := 0
                for i in 11:
                    var p: Vector3 = a.lerp(b, i / 10.0)
                    if Vector2(p.x - tt.global_position.x, p.z - tt.global_position.z).length() > 0.6:
                        outside += 1
                var glow: MeshInstance3D = ab.beads[ab.beads.size() - 1]
                var gs := cam.unproject_position(glow.global_position)
                var vp := get_viewport().get_visible_rect().size
                _rec("target_glow_on_screen", glow.visible and gs.x >= 0 and gs.y >= 0 and gs.x <= vp.x and gs.y <= vp.y and glow.material_override.no_depth_test, "glow=%s" % gs)
                _rec("notes_flow_along_beam", ab.beads.slice(0, ab.BEADS).all(func(n): return n.visible and Geometry3D.get_closest_point_to_segment(n.global_position, a, b).distance_to(n.global_position) < ab.WAVE + 0.05))
                _rec("mostly_outside_own_model", outside >= 9, "%d/11 samples" % outside)
                ally.global_position = Vector3(1.2, 0, -9)   # interpolated move (still in cone): ribbon follows
                step = 2
                t = 0.0
        2:
            if t > 0.1:
                _rec("follows_moving_target", ab.beam_end().distance_to(ally.global_position + Vector3(0, 1, 0)) < 0.01)
                # snapshot: channel time is over (3 s elapsed of an 8 s cooldown)
                ab.cooldown.remaining = ab.cooldown.duration - 3.05
                step = 3
                t = 0.0
        3:
            if t > 0.08 and t < 0.15:
                _rec("fades_not_pops", ab.ribbon.visible and _alpha() > 0.1 and _alpha() < 0.9, "a=%.2f" % _alpha())
                step = 4
        4:
            if t > 0.3:
                _rec("gone_after_fade", not ab.ribbon.visible and _alpha() == 0.0 and ab.beads.all(func(n): return not n.visible))
                ally.global_position = Vector3(30, 0, 30)    # nobody in cone -> self heal aura
                ab.cooldown.remaining = ab.cooldown.duration
                step = 5
                t = 0.0
        5:
            if t > 0.2:
                _rec("self_heal_aura", ab.aura.visible and not ab.ribbon.visible and ab.vis_target == tt)
                tt.dead = true                               # snapshot: healer died
                step = 6
                t = 0.0
        6:
            if t > 0.3:
                _rec("hidden_when_dead", not ab.aura.visible and not ab.ribbon.visible)
                _rec("no_gameplay_state", ally.health.hp == ally.health.max_hp and ab.left == 0.0)
                done = true
