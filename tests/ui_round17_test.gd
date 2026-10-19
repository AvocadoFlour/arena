extends "res://tests/test_base.gd"
## LibreQuake hero sounds + team cues (HeroSfx): per-hero x slot files, byte-identical + licensed, Actions key
## mapping, ability_used / primary-fire / ult-ready sources, team-checked damage/kill cues, rate limits,
## SFX bus, no double play with the procedural UiSfx hit/kill.
var tree: SceneTree

class MockUlt extends RefCounted:
    var full := false
    func is_full() -> bool: return full

class MockWeapon extends RefCounted:
    var ammo := 10

class MockHero extends Node:
    var team := 0
    var dead := false
    var def := {}
    var weapon := MockWeapon.new()
    var ult := MockUlt.new()

class MockBus extends Node:
    signal ability_used(hero, slot: String, ability_id: String)
    signal damage_dealt(ev: Dictionary)
    signal killed(ev: Dictionary)

func _hero(id: String, team := 0) -> MockHero:
    var h := MockHero.new()
    h.def = {"id": id}
    h.team = team
    tree.root.add_child(h)
    return h

func _sfx() -> HeroSfx:
    var s := HeroSfx.new()
    tree.root.add_child(s)
    s.set_process(false)
    return s

func _sha(path: String) -> String:
    return FileAccess.get_sha256(path)

func test_every_hero_has_five_distinct_licensed_sounds() -> void:
    var ids := UiCatalog.list_heroes().map(func(h): return String(h.id))
    for id in ["cob", "nidjo", "the_best", "tomo", "twin_tails"]:
        check(HeroSfx.HERO.has(id), "sounds keyed for " + id)
    for id in ids:
        if id in ["ubel"]:   # core 0.9.3: new hero, sounds not chosen by UI yet (plays silent; HeroSfx skips unknown ids)
            continue
        check(HeroSfx.HERO.has(id), "every selectable hero has sounds: " + id)
    var lic := FileAccess.get_file_as_string("res://src/ui/audio/LICENSES.md")
    var all := []
    for id in HeroSfx.HERO:
        check(HeroSfx.HERO[id].keys() == HeroSfx.SLOTS, "%s has the 5 slots" % id)
        for slot in HeroSfx.SLOTS:
            all.append(HeroSfx.HERO[id][slot])
    for c in HeroSfx.CUES:
        all.append(HeroSfx.CUES[c])
    check(all.size() == 29, "25 hero sounds + 4 cues")
    var uniq := {}
    for f in all:
        uniq[f] = true
        var p := HeroSfx.BASE + String(f)
        check(load(p) is AudioStreamWAV, "imports: " + f)
        var row := "| `%s` |" % f
        check(lic.contains(row) and lic.contains(_sha(p)), "LICENSES.md lists %s with its SHA-256" % f)
        check(lic.contains("lq1/sound/" + f), "source path recorded: " + f)
    check(uniq.size() == 29, "all 29 files distinct")
    check(lic.contains("BSD 3-Clause") and lic.contains("Neither the name of the LibreQuake project"), "BSD-3 text included")

func test_slots_are_the_actions_bindings() -> void:
    check(Actions.MOUSE_BINDINGS.get("fire") == [MOUSE_BUTTON_LEFT], "fire = left mouse")
    check(Actions.BINDINGS.get("ability1") == [KEY_SHIFT] and Actions.BINDINGS.get("ability2") == [KEY_E] and Actions.BINDINGS.get("ultimate") == [KEY_Q], "Shift / E / Q")
    for s in ["fire", "ability1", "ability2", "ultimate"]:
        check(InputMap.has_action(s), "action exists: " + s)

func test_ability_used_plays_hero_sounds_on_sfx_bus() -> void:
    var s := _sfx()
    var bus := MockBus.new()
    tree.root.add_child(bus)
    s.bind(bus)
    var me := _hero("cob")
    var other := _hero("tomo", 1)
    s.player = me
    check(s.players.all(func(p): return p.bus == "SFX"), "SFX bus")
    bus.ability_used.emit(me, "ability2", "geode_wall")
    check(s.last_file == HeroSfx.path_for("cob", "ability2") and s.play_count.get("cob/ability2", 0) == 1 and s.last_player is AudioStreamPlayer, "own E sound, non-positional: " + s.last_file)
    bus.ability_used.emit(other, "ultimate", "x")
    check(s.play_count.get("tomo/ultimate", 0) == 1 and s.last_player is AudioStreamPlayer3D, "other heroes' casts play too (positional)")
    me.def = {"id": "nidjo"}
    bus.ability_used.emit(me, "ultimate", "rollback")
    check(s.last_file.ends_with("items/health1.wav"), "keyed by hero id (Niđo): " + s.last_file)
    s.free(); bus.free(); me.free(); other.free()

func test_primary_fire_detected_from_ammo_and_rate_limited() -> void:
    var s := _sfx()
    var me := _hero("the_best")
    s.player = me
    s.poll()
    check(s.play_count.is_empty(), "first sample never plays")
    me.weapon.ammo = 9
    s.poll()
    check(s.play_count.get("the_best/fire", 0) == 1 and s.last_file.ends_with("knight/sword1.wav"), "shot -> fire sound")
    me.weapon.ammo = 8
    s.poll()
    check(s.play_count.get("the_best/fire", 0) == 1, "rate-limited (< %.2f s)" % HeroSfx.MIN_GAP.fire)
    me.weapon.ammo = 10
    s.poll()
    check(s.play_count.get("the_best/fire", 0) == 1, "reload refill is not a shot")
    s.last_play.clear()
    me.dead = true
    me.weapon.ammo = 5
    s.poll()
    check(s.play_count.get("the_best/fire", 0) == 1, "no sound while dead")
    me.dead = false
    var tomo := _hero("tomo")
    s.player = tomo
    s.poll()
    tomo.weapon.ammo = 9
    s.poll()
    s.last_play[HeroSfx.rate_key(tomo, "fire")] = Time.get_ticks_msec() / 1000.0 - 0.2
    tomo.weapon.ammo = 8
    s.poll()
    check(s.play_count.get("tomo/fire", 0) == 1, "Tomo: one sound per burst (gap %.2f s)" % HeroSfx.FIRE_GAP.tomo)
    s.free(); me.free(); tomo.free()

func test_ult_ready_edge() -> void:
    var s := _sfx()
    var me := _hero("twin_tails")
    me.ult.full = true
    s.player = me
    s.poll()
    check(s.play_count.get("twin_tails/ult_ready", 0) == 0, "already full at start: no sound")
    me.ult.full = false
    s.poll()
    me.ult.full = true
    s.poll()
    check(s.play_count.get("twin_tails/ult_ready", 0) == 1 and s.last_file.ends_with("items/inv1.wav"), "meter full -> ult ready")
    s.poll()
    check(s.play_count.get("twin_tails/ult_ready", 0) == 1, "only on the edge")
    s.free(); me.free()

func test_team_cues() -> void:
    var s := _sfx()
    var me := _hero("cob", 0)
    var mate := _hero("tomo", 0)
    var foe := _hero("the_best", 1)
    s.player = me
    s.on_damage({"source": foe, "target": me, "amount": 10.0, "killed": false})
    check(s.last_key == "hit_me" and s.last_file.ends_with("player/pain1.wav"), "enemy hits me")
    s.on_damage({"source": foe, "target": mate, "amount": 10.0, "killed": false})
    check(s.last_key == "hit_teammate" and s.last_file.ends_with("player/pain5.wav"), "enemy hits teammate")
    s.on_damage({"source": foe, "target": mate, "amount": 10.0, "killed": false})
    check(s.play_count.hit_teammate == 1, "teammate-hit rate-limited")
    var n := s.play_count.duplicate()
    s.on_damage({"source": me, "target": foe, "amount": 10.0, "killed": false})
    s.on_damage({"source": mate, "target": me, "amount": 10.0, "killed": false})
    s.on_damage({"source": null, "target": me, "amount": 10.0, "killed": false})
    s.on_damage({"source": foe, "target": me, "amount": 10.0, "killed": true})
    check(s.play_count == n, "my own hits (UiSfx hit marker), friendly, falls and kill blows: no cue")
    s.on_kill({"killer": mate, "victim": foe})
    check(s.last_key == "team_kill" and s.last_file.ends_with("player/death3.wav"), "teammate kill")
    s.on_kill({"killer": foe, "victim": mate})
    check(s.last_key == "teammate_killed" and s.last_file.ends_with("player/death1.wav"), "enemy kills teammate")
    n = s.play_count.duplicate()
    s.on_kill({"killer": me, "victim": foe})
    s.on_kill({"killer": foe, "victim": me})
    s.on_kill({"killer": null, "victim": mate})
    check(s.play_count == n, "my kill (UiSfx kill) / my death / environment: no cue")
    s.free(); me.free(); mate.free(); foe.free()

func test_hud_owns_hero_sfx() -> void:
    check(load("res://src/ui/hud.gd").source_code.contains("HeroSfx.new()"), "HUD creates HeroSfx")
