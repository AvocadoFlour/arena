extends "res://tests/test_base.gd"
## Unit tests for src/ai (pure logic).

func _ctx(o: Dictionary) -> Dictionary:
    var c := {"dist": 20.0, "flat_dist": 20.0, "on_floor": true, "height_above": 0.0, "los": true,
        "low_hp": false, "dash_ready": true, "slam_ready": true, "ult_ready": false, "ult_targets": 0,
        "moving": true, "fleeing": false}
    c.merge(o, true)
    return c

func test_difficulty_presets_ordered() -> void:
    var e := BotBrain.new({"difficulty": "easy"})
    var n := BotBrain.new({"difficulty": "normal"})
    var h := BotBrain.new({"difficulty": "hard"})
    check(e.spread_deg > n.spread_deg and n.spread_deg > h.spread_deg, "spread easy>normal>hard")
    check(e.reaction_time > n.reaction_time and n.reaction_time > h.reaction_time, "reaction easy>normal>hard")
    check(e.aim_jitter > n.aim_jitter and n.aim_jitter > h.aim_jitter, "aim jitter easy>normal>hard")
    check(e.turn_rate < n.turn_rate and n.turn_rate < h.turn_rate, "turn rate easy<normal<hard")
    check(e.ability_delay > n.ability_delay and n.ability_delay > h.ability_delay, "ability delay easy>normal>hard")

func test_default_is_normal_and_params_override() -> void:
    var b := BotBrain.new({"turn_rate": 6.0, "bounds": 12.0})
    check(b.difficulty == "normal", "default normal")
    near(b.spread_deg, 6.0, 0.001, "normal spread kept (spawner contract)")
    near(b.turn_rate, 6.0, 0.001, "explicit param overrides preset")
    near(b.bounds, 12.0, 0.001, "bounds param")
    check(not BotBrain.DIFFICULTY.has("bogus"), "bogus is not a preset")
    check(BotBrain.resolve_difficulty("bogus") == "normal", "unknown difficulty resolves to normal (no warning path)")
    for d in ["easy", "normal", "hard"]:
        check(BotBrain.DIFFICULTY.has(d) and BotBrain.resolve_difficulty(d) == d, "preset " + d)

func test_world_to_move_mapping() -> void:
    var b := Basis()   # yaw 0: forward is -Z, right is +X
    var m := BotBrain.world_to_move(b, Vector3(0, 0, -5))
    check(m.distance_to(Vector2(0, 1)) < 0.01, "forward -> move.y=1 (%s)" % m)
    m = BotBrain.world_to_move(b, Vector3(3, 0, 0))
    check(m.distance_to(Vector2(1, 0)) < 0.01, "+X -> strafe right (%s)" % m)
    var r := Basis(Vector3.UP, PI / 2)   # yaw +90: facing -X
    m = BotBrain.world_to_move(r, Vector3(-1, 0, 0))
    check(m.distance_to(Vector2(0, 1)) < 0.01, "rotated forward (%s)" % m)
    check(BotBrain.world_to_move(b, Vector3.ZERO) == Vector2.ZERO, "zero dir")

func test_ult_only_with_enemy_in_radius() -> void:
    check(not BotBrain.decide_abilities(_ctx({"ult_ready": true, "ult_targets": 0, "dist": 6.0})).ultimate, "no ult without targets")
    check(not BotBrain.decide_abilities(_ctx({"ult_ready": true, "ult_targets": 1, "dist": 9.5})).ultimate, "no ult at edge of range")
    check(BotBrain.decide_abilities(_ctx({"ult_ready": true, "ult_targets": 1, "dist": 5.0})).ultimate, "ult when enemy close")
    check(not BotBrain.decide_abilities(_ctx({"ult_ready": false, "ult_targets": 2, "dist": 5.0})).ultimate, "no ult when not charged")

func test_slam_ground_and_dive() -> void:
    check(BotBrain.decide_abilities(_ctx({"dist": 3.0})).ability2, "ground slam in range")
    check(not BotBrain.decide_abilities(_ctx({"dist": 8.0})).ability2, "no ground slam out of range")
    check(BotBrain.decide_abilities(_ctx({"on_floor": false, "height_above": 3.0, "flat_dist": 2.0, "dist": 3.6})).ability2, "dive onto enemy below")
    check(not BotBrain.decide_abilities(_ctx({"on_floor": false, "height_above": -1.0, "flat_dist": 2.0, "dist": 3.0})).ability2, "no dive when enemy above")
    check(not BotBrain.decide_abilities(_ctx({"dist": 3.0, "slam_ready": false})).ability2, "respects cooldown")

func test_dash_gap_close_and_escape() -> void:
    check(BotBrain.decide_abilities(_ctx({"dist": 15.0})).ability1, "dash to close gap")
    check(not BotBrain.decide_abilities(_ctx({"dist": 6.0})).ability1, "no dash when close")
    check(not BotBrain.decide_abilities(_ctx({"dist": 15.0, "los": false})).ability1, "no blind dash")
    check(not BotBrain.decide_abilities(_ctx({"dist": 15.0, "low_hp": true})).ability1, "no aggressive dash when hurt")
    check(BotBrain.decide_abilities(_ctx({"fleeing": true, "low_hp": true, "los": false})).ability1, "dash to escape to cover")
    check(not BotBrain.decide_abilities(_ctx({"fleeing": true, "dist": 3.0})).ability2, "no slam while fleeing")
    check(not BotBrain.decide_abilities(_ctx({"dist": 15.0, "moving": false})).ability1, "no dash standing still")

func test_cover_point_is_behind_block() -> void:
    var blk := {"pos": Vector3(0, 1, 0), "half": Vector3(1, 1, 1), "height": 2.0}
    var cp := BotNav.cover_point(blk, Vector3(0, 0, -10))
    check(cp.z > 1.0 and absf(cp.x) < 0.01, "cover on far side (%s)" % cp)
    near(cp.y, 0.0, 0.001, "cover point at block base")
    cp = BotNav.cover_point(blk, Vector3(10, 0, 0))
    check(cp.x < -1.0, "far side for threat at +X (%s)" % cp)

func test_best_cover_choice() -> void:
    var blocks := [
        {"pos": Vector3(-5, 1, 0), "half": Vector3(1, 1, 1), "height": 2.0},
        {"pos": Vector3(5, 0.6, 0), "half": Vector3(1, 0.6, 1), "height": 1.2},   # too low
        {"pos": Vector3(20, 1, 0), "half": Vector3(1, 1, 1), "height": 2.0},
    ]
    var cp = BotNav.best_cover(blocks, Vector3(0, 0, 3), Vector3(0, 0, -10))
    check(cp != null and absf(cp.x + 5.0) < 1.5, "nearest tall cover chosen (%s)" % [cp])
    check(BotNav.best_cover([], Vector3.ZERO, Vector3(0, 0, -10)) == null, "no cover -> null")

func _typed(types: Dictionary, o: Dictionary) -> Dictionary:
    var c := _ctx(o)
    c.types = types
    var r := {}
    for k in types:
        r[k] = true
    c.ready = r
    return c

func test_rampart_charge_and_shield_policy() -> void:
    var t := {"ability1": "charge", "ability2": "shield_wall", "ultimate": "nova"}
    check(BotBrain.decide_abilities(_typed(t, {"dist": 6.0, "aim_ok": true})).ability1, "charge aimed enemy in reach")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 6.0, "aim_ok": false})).ability1, "no charge when not aimed")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 15.0, "aim_ok": true})).ability1, "no charge out of reach")
    check(BotBrain.decide_abilities(_typed(t, {"dist": 12.0, "hurt": true})).ability2, "shield when hurt under fire")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 12.0, "hurt": false})).ability2, "no shield at full health")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 12.0, "hurt": true, "los": false})).ability2, "no shield without enemy in sight")

func test_willow_projectile_and_rally_policy() -> void:
    var t := {"ability1": "heal_beam", "ability2": "projectile", "ultimate": "rally"}
    check(BotBrain.decide_abilities(_typed(t, {"dist": 20.0, "aim_ok": true})).ability2, "bolt at aimed enemy")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 20.0, "aim_ok": true, "fleeing": true})).ability2, "no bolt while fleeing")
    check(BotBrain.decide_abilities(_typed(t, {"allies_hurt": 1})).ultimate, "rally for hurt ally")
    check(not BotBrain.decide_abilities(_typed(t, {"allies_hurt": 0})).ultimate, "no rally when team healthy")
    check(BotBrain.decide_abilities(_typed(t, {"ult_targets": 1})).ultimate, "rally entering close fight")
    check(BotBrain.decide_abilities(_typed(t, {"low_hp": true})).ability1, "self heal when low")
    check(BotBrain.decide_abilities(_typed(t, {"hurt": true})).ability1, "self heal when hurt (no ally around)")
    check(not BotBrain.decide_abilities(_typed(t, {})).ability1, "no beam on self at full hp")

func test_cover_detection_by_kind_and_prefix() -> void:
    var a := StaticBody3D.new()
    a.name = "cover_03"
    check(BotNav.is_cover(a), "cover_03 by prefix")
    var b := StaticBody3D.new()
    b.name = "wall_02"
    b.set_meta("kind", "wall")
    check(not BotNav.is_cover(b), "wall not cover")
    var c := StaticBody3D.new()
    c.name = "block_07"
    c.set_meta("kind", "cover")
    check(BotNav.is_cover(c), "kind meta wins")
    var d := StaticBody3D.new()
    d.name = "discover_01"
    check(not BotNav.is_cover(d), "no substring false positive")
    for n in [a, b, c, d]:
        n.free()

func test_box_footprint() -> void:
    var t := Transform3D(Basis(Vector3.UP, PI / 2), Vector3(5, 1, 0))
    var fp := BotNav.box_footprint(t, Vector3(4, 2, 0.5))
    check(fp.size() == 4, "4 corners")
    var minz := INF
    var maxz := -INF
    for p in fp:
        minz = minf(minz, p.z)
        maxz = maxf(maxz, p.z)
    near(maxz - minz, 4.0, 0.01, "rotated width along z")

func test_melee_standoff() -> void:
    near(BotBrain.standoff(3.2, false), 1.92, 0.01, "melee holds inside weapon range")
    check(BotBrain.standoff(3.2, true) < 3.2, "melee ignores slam stand-off, stays in reach")
    near(BotBrain.standoff(0.0, false), 10.0, 0.01, "ranged keeps 10 m")
    near(BotBrain.standoff(0.0, true), 3.0, 0.01, "ranged closes for slam")
    var mel := {"def": {"primary": {"type": "melee", "range": 3.2}}}
    var gun := {"def": {"primary": {"type": "hitscan", "range": 60}}}
    near(BotBrain.melee_range(_Def.new(mel.def)), 3.2, 0.001, "melee range from def")
    near(BotBrain.melee_range(_Def.new(gun.def)), 0.0, 0.001, "hitscan -> 0")

class _Def:
    var def: Dictionary
    func _init(d: Dictionary) -> void:
        def = d

func test_melee_dash_gap_close() -> void:
    check(BotBrain.decide_abilities(_ctx({"dist": 8.0, "melee": true})).ability1, "melee dashes in from mid range")
    check(not BotBrain.decide_abilities(_ctx({"dist": 8.0})).ability1, "ranged does not dash at 8 m")
    check(not BotBrain.decide_abilities(_ctx({"dist": 3.0, "melee": true})).ability1, "no dash when already in reach")

func test_leap_policy() -> void:
    var t := {"ability1": "leap", "ability2": "dash", "ultimate": "team_buff"}
    check(BotBrain.decide_abilities(_typed(t, {"dist": 8.0, "aim_ok": true, "leap_range": 11.5})).ability1, "leap onto aimed enemy in arc")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 3.0, "aim_ok": true, "leap_range": 11.5})).ability1, "no leap when already in reach")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 14.0, "aim_ok": true, "leap_range": 11.5})).ability1, "no leap beyond arc")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 8.0, "aim_ok": false, "leap_range": 11.5})).ability1, "no leap unaimed")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 8.0, "aim_ok": true, "leap_range": 11.5, "on_floor": false})).ability1, "no leap in air")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 8.0, "aim_ok": true, "leap_range": 11.5, "los": false})).ability1, "no blind leap")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 8.0, "aim_ok": true, "leap_range": 11.5, "fleeing": true})).ability1, "no leap while fleeing")

func test_team_buff_policy() -> void:
    var t := {"ability1": "leap", "ability2": "dash", "ultimate": "team_buff"}
    check(BotBrain.decide_abilities(_typed(t, {"dist": 3.0, "engage_range": 6.4})).ultimate, "buff when engaged close")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 20.0, "engage_range": 6.4})).ultimate, "no buff at range")
    check(BotBrain.decide_abilities(_typed(t, {"dist": 12.0, "engage_range": 6.4, "hurt": true})).ultimate, "buff when hurt in a fight")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 3.0, "los": false})).ultimate, "no buff without enemy in sight")
    check(not BotBrain.decide_abilities(_typed(t, {"dist": 3.0, "fleeing": true})).ultimate, "no buff while fleeing")

func test_standoff_dir_restores_range() -> void:
    var tgt := Vector3.ZERO
    var far := BotBrain.standoff_dir(Vector3(0, 0, 12), tgt, 10.0, 1.0)
    check(far.dot(Vector3(0, 0, -1)) > 0.5, "too far -> moves in (%s)" % far)
    var close := BotBrain.standoff_dir(Vector3(0, 0, 7), tgt, 10.0, 1.0)
    check(close.dot(Vector3(0, 0, 1)) > 0.5, "too close -> backs off (%s)" % close)
    var at := BotBrain.standoff_dir(Vector3(0, 0, 10), tgt, 10.0, 1.0)
    near(at.z, 0.0, 0.001, "at range -> no radial component")
    check(absf(at.x) > 0.5, "at range -> pure tangential strafe (%s)" % at)
    var other := BotBrain.standoff_dir(Vector3(0, 0, 10), tgt, 10.0, -1.0)
    check(at.x * other.x < 0.0, "strafe sign flips direction")
    # orbit simulation: 6 s of integration at 7 m/s with strafing never leaves the 10 m band
    var p := Vector3(0, 0, 10)
    var lo := INF
    var hi := 0.0
    for i in 360:
        p += BotBrain.standoff_dir(p, tgt, 10.0, 1.0 if (i / 90) % 2 == 0 else -1.0) * 7.0 / 60.0
        lo = minf(lo, p.length())
        hi = maxf(hi, p.length())
    check(lo > 9.0 and hi < 11.0, "orbit stays in band (%.2f..%.2f)" % [lo, hi])
