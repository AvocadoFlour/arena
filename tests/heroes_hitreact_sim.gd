extends Node3D
## Hit reactions on PUPPETS (only replicated fields written: health.hp, dead) + a replayed damage event.
## hp drop -> flash + flinch that both recover; heals/respawn/dead -> nothing; stronger hits react more
## (capped); shared toon meshes stay shared; no gameplay state changes.
var results: Array = []
var done := false
var heroes := {}

func _rec(n: String, ok: bool, info: String = "") -> void:
    results.append([n, ok, info])

func _puppet(id: String, pos: Vector3, prim := false) -> Hero:
    var was := Hero.use_primitive_models
    Hero.use_primitive_models = prim
    var h := Hero.from_def("res://src/heroes/%s.json" % id)
    Hero.use_primitive_models = was
    h.net_role = "puppet"
    add_child(h)
    h.set_team(0)
    h.global_position = pos
    return h

func _wait(s: float) -> void:
    await get_tree().create_timer(s).timeout

func _geo_flash(h: Hero) -> float:
    var mx := 0.0
    for mi in h.hit._geo:
        mx = maxf(mx, float(mi.get_instance_shader_parameter("hit_flash")))
    return mx

func _prim_lit(h: Hero) -> bool:
    for p in h.hit._prims:
        if p[0].emission_enabled != p[1] or p[0].emission != p[2]:
            return true
    return false

func _ready() -> void:
    heroes.tt = _puppet("twin_tails", Vector3(-6, 0, 0))
    heroes.tb = _puppet("the_best", Vector3(0, 0, 0))
    heroes.cob = _puppet("cob", Vector3(6, 0, 0))
    heroes.prim = _puppet("the_best", Vector3(0, 0, 8), true)
    _run()

func _run() -> void:
    await _wait(0.3)
    var state0 := {}
    for k in heroes:
        var h: Hero = heroes[k]
        state0[k] = [h.weapon.ammo, h.velocity, h.dead, h.ult.charge if "charge" in h.ult else 0.0]
    _rec("models_have_flash_surfaces", heroes.tt.hit._geo.size() > 0 and heroes.tb.hit._geo.size() > 0 and heroes.cob.hit._geo.size() > 0 and heroes.prim.hit._prims.size() > 0)
    # 1) hp-only drop
    var c0 := {}
    for k in heroes:
        c0[k] = heroes[k].hit.count
        heroes[k].health.hp -= 40.0
    await _wait(0.05)
    for k in heroes:
        var h: Hero = heroes[k]
        var lit := _prim_lit(h) if k == "prim" else _geo_flash(h) > 0.2
        _rec("%s_hp_drop_flash" % k, lit and h.hit.flash > 0.2, "flash=%.2f" % h.hit.flash)
        _rec("%s_hp_drop_flinch" % k, h.hit.count == c0[k] + 1 and (h._flinch.rotation.length() > 0.02 or h._flinch.position.length() > 0.01), "rot=%.3f" % h._flinch.rotation.length())
    var small: float = heroes.tb.hit.strength
    await _wait(0.6)
    for k in heroes:
        var h: Hero = heroes[k]
        var rec_ok := h.hit.flash == 0.0 and h._flinch.rotation.length() < 0.001 and h._flinch.position.length() < 0.001
        rec_ok = rec_ok and (not _prim_lit(h) if k == "prim" else _geo_flash(h) == 0.0)
        _rec("%s_recovers" % k, rec_ok)
    # 2) heals do not react
    for k in heroes:
        c0[k] = heroes[k].hit.count
        heroes[k].health.hp += 30.0
    await _wait(0.1)
    _rec("heal_no_reaction", heroes.keys().all(func(k): return heroes[k].hit.count == c0[k] and heroes[k].hit.flash == 0.0))
    # 3) bigger hit -> stronger, capped
    heroes.tb.health.hp -= 150.0
    await _wait(0.03)
    var big: float = heroes.tb.hit.strength
    _rec("bigger_hit_stronger_capped", big > small and big <= HitReact.MAX_STRENGTH, "small=%.2f big=%.2f" % [small, big])
    await _wait(0.5)
    # 4) damage event gives direction (source at -X pushes towards +X)
    var src := Node3D.new()
    add_child(src)
    src.global_position = heroes.cob.global_position + Vector3(-5, 0, 0)
    Events.damage_dealt.emit({"source": src, "target": heroes.cob, "amount": 20.0, "pos": heroes.cob.global_position, "kind": "test", "killed": false, "ability_id": "", "crit": false})
    heroes.cob.health.hp -= 20.0
    await _wait(0.05)
    _rec("event_direction", heroes.cob.hit.dir_local.x > 0.9 and heroes.cob._flinch.position.x > 0.0, "dir=%s" % heroes.cob.hit.dir_local)
    _rec("event_plus_hp_one_reaction", heroes.cob.hit.count == c0.cob + 1, "count=%d" % (heroes.cob.hit.count - c0.cob))
    src.queue_free()
    await _wait(0.5)
    # 5) dead / respawn: no reaction
    var h2: Hero = heroes.tt
    var c1 := h2.hit.count
    h2.dead = true
    h2.health.hp = 0.0
    await _wait(0.1)
    _rec("no_reaction_dead", h2.hit.count == c1 and h2.hit.flash == 0.0)
    h2.dead = false
    h2.health.hp = h2.health.max_hp
    await _wait(0.1)
    _rec("no_reaction_respawn", h2.hit.count == c1 and h2.hit.flash == 0.0)
    # 6) shared meshes stay shared, no material overrides
    var other := _puppet("twin_tails", Vector3(-6, 0, 8))
    var mesh_a := {}
    var overrides := 0
    for mi in heroes.tt.hit._geo:
        mesh_a[mi.mesh] = true
        for i in mi.get_surface_override_material_count():
            overrides += 1 if mi.get_surface_override_material(i) != null else 0
        overrides += 1 if mi.material_override != null else 0
    var shared_n := 0
    for mi in other.hit._geo:
        shared_n += 1 if mesh_a.has(mi.mesh) else 0
    _rec("toon_meshes_still_shared", shared_n == other.hit._geo.size() and shared_n > 0 and overrides == 0, "shared=%d/%d overrides=%d" % [shared_n, other.hit._geo.size(), overrides])
    other.queue_free()
    # 7) gameplay state untouched (only the hp/dead we wrote)
    var same := true
    for k in heroes:
        var h: Hero = heroes[k]
        same = same and state0[k] == [h.weapon.ammo, h.velocity, h.dead, h.ult.charge if "charge" in h.ult else 0.0]
    _rec("no_state_changes", same)
    await _wait(0.1)
    for k in heroes:
        heroes[k].queue_free()
    done = true
