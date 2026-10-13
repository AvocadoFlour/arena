extends Node3D
## Toon ability/weapon effects on PUPPETS: only replicated fields are written (ammo, combo_step, ability
## cooldown.remaining, dash_time, position/velocity, dead) plus replayed Events - as on a network client.
## Every one of the 9 abilities + 3 primaries must spawn visible toon pieces near the hero, change no
## gameplay state, and clean up completely.
var results: Array = []
var done := false
var t := 0.0
var heroes := {}
var queue: Array = []
var cur: Dictionary = {}
var _hp0 := {}

func _rec(n: String, ok: bool, info: String = "") -> void:
    results.append([n, ok, info])

func _puppet(id: String, pos: Vector3) -> Hero:
    var h := Hero.from_def("res://src/heroes/%s.json" % id)
    h.net_role = "puppet"
    add_child(h)
    h.set_team(0)
    h.global_position = pos
    return h

func _ready() -> void:
    heroes.tt = _puppet("twin_tails", Vector3(-12, 0, 0))
    heroes.tb = _puppet("the_best", Vector3(0, 0, 0))
    heroes.cob = _puppet("cob", Vector3(12, 0, 0))
    for k in heroes:
        _hp0[k] = heroes[k].health.hp
    for a in [["tt", "ability1", "encore_beam"], ["tt", "ability2", "staccato_note"], ["tt", "ultimate", "grand_finale"],
              ["tb", "ability1", "fearless_leap"], ["tb", "ability2", "swagger_step"], ["tb", "ultimate", "no_limits"],
              ["cob", "ability1", "boulder_roll"], ["cob", "ability2", "geode_wall"], ["cob", "ultimate", "quarry_quake"],
              ["tt", "shot", "sound_wave"], ["tb", "shot", "sword_arc"], ["tb", "finisher", "finisher_arc"], ["cob", "shot", "crystal_shot"]]:
        queue.append({"h": a[0], "slot": a[1], "name": a[2]})

func _fx_near(h: Hero, r: float) -> Array:
    return get_tree().get_nodes_in_group("toon_fx").filter(func(p): return is_instance_valid(p) and not p.is_queued_for_deletion() and p.global_position.distance_to(h.global_position) < r)

func _start(c: Dictionary) -> void:
    var h: Hero = heroes[c.h]
    c.n0 = h.fx.spawned if h.fx else 0
    match String(c.slot):
        "shot":
            h.weapon.ammo -= 1
        "finisher":
            h.combo_step = 3
            h.weapon.ammo -= 1
        _:
            var ab = h.abilities[c.slot]
            ab.cooldown.remaining = maxf(ab.cooldown.duration, 1.0)
            if c.name == "fearless_leap" or c.name == "swagger_step":
                h.dash_time = 0.3   # replicated dash/leap timer
    c.t = 0.0
    c.max_near = 0
    c.visible_ok = false

func _process(dt: float) -> void:
    if done:
        return
    t += dt
    if t < 0.3:
        return   # baselines
    if cur.is_empty():
        if queue.is_empty():
            if not finishing:
                finishing = true
                _finish()
            return
        cur = queue.pop_front()
        _start(cur)
        return
    var h: Hero = heroes[cur.h]
    cur.t += dt
    if cur.name == "fearless_leap" and cur.t > 0.25:
        h.dash_time = 0.0   # replicated: landed
    if cur.name == "swagger_step" and cur.t > 0.15:
        h.dash_time = 0.0
    if cur.name == "grand_finale" and absf(cur.t - 0.2) < dt:   # replicated heal event from the ult
        Events.healed.emit({"source": h, "target": heroes.tb, "amount": 50.0, "ability_id": "grand_finale"})
    if cur.name == "staccato_note" and absf(cur.t - 0.2) < dt:   # replicated hit event
        Events.damage_dealt.emit({"source": h, "target": heroes.tb, "amount": 30.0, "pos": heroes.tb.global_position + Vector3(0, 1, 0), "kind": "projectile", "killed": false, "ability_id": "staccato_note", "crit": false})
    var near := _fx_near(h, 14.0)
    cur.max_near = maxi(cur.max_near, near.size())
    for p in near:
        if p.is_visible_in_tree() and p.scale.length() > 0.01 and p.get_child_count() > 0:
            cur.visible_ok = true
    if cur.t > 1.6:
        var spawned: int = h.fx.spawned - cur.n0
        _rec("fx_" + cur.name, spawned > 0 and cur.max_near > 0 and cur.visible_ok, "spawned=%d near_max=%d" % [spawned, cur.max_near])
        cur = {}

var finishing := false

func _finish() -> void:
    # gameplay untouched by effects
    var same := true
    for k in heroes:
        same = same and heroes[k].health.hp == _hp0[k]
    _rec("no_gameplay_change", same)
    var colliders := 0
    for p in get_tree().get_nodes_in_group("toon_fx"):
        colliders += p.find_children("*", "CollisionObject3D", true, false).size()
    _rec("fx_have_no_collision", colliders == 0)
    # polish (vfx2): encore heal event -> pop + ground ring + pulse note along the ribbon
    var tt: Hero = heroes.tt
    var n0: int = tt.fx.spawned
    Events.healed.emit({"source": tt, "target": heroes.tb, "amount": 20.0, "ability_id": "encore_beam"})
    _rec("encore_heal_pop_and_pulse", tt.fx.spawned - n0 >= 3, "pieces=%d" % (tt.fx.spawned - n0))
    # staccato cast ring is raised to at least chest height
    tt.abilities.ability2.cooldown.remaining = 0.0
    await get_tree().process_frame
    var before := get_tree().get_nodes_in_group("toon_fx").size()
    tt.abilities.ability2.cooldown.remaining = tt.abilities.ability2.cooldown.duration
    await get_tree().process_frame
    await get_tree().process_frame
    var rings := get_tree().get_nodes_in_group("toon_fx").filter(func(p): return p.get_child_count() > 0 and p.get_child(0) is MeshInstance3D and p.get_child(0).mesh is TorusMesh and p.global_position.distance_to(tt.global_position) < 3.0)
    _rec("staccato_ring_raised", rings.size() > 0 and rings.all(func(p): return p.global_position.y - tt.global_position.y >= 1.2), "rings=%d of %d new" % [rings.size(), get_tree().get_nodes_in_group("toon_fx").size() - before])
    # everything cleans up (longest: geode crystals = wall duration 5 s, no_limits flames 7 s)
    await get_tree().create_timer(7.5).timeout
    var left := get_tree().get_nodes_in_group("toon_fx").size()
    _rec("fx_clean_up", left == 0, "left=%d" % left)
    var proj = load("res://src/abilities/projectile_shot.gd").new(null, heroes.tt.abilities.ability2.def)
    _rec("staccato_projectile_is_note_glyph", proj.glyph != null)
    proj.free()
    for k in heroes:
        heroes[k].queue_free()
    done = true
