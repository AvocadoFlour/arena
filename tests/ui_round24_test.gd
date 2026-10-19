extends "res://tests/test_base.gd"
## HeroSfx for every hero: positional AudioStreamPlayer3D for other heroes (gentle inverse-distance attenuation,
## no cutoff, no filter), 32-voice pool stealing the quietest/farthest, local + team cues never stolen,
## per-instance rate limits, VOLUME_GAIN kept, ultimates louder (per-play volume_db only), never stolen, layered.
var tree: SceneTree

class MockUlt extends RefCounted:
    var full := false
    func is_full() -> bool: return full

class MockWeapon extends RefCounted:
    var ammo := 30

class MockHero extends Node3D:
    var team := 1
    var dead := false
    var def := {}
    var weapon := MockWeapon.new()
    var ult := MockUlt.new()

var _made: Array = []

func _hero(id: String, pos: Vector3, team := 1) -> MockHero:
    var h := MockHero.new()
    h.def = {"id": id}
    h.team = team
    tree.root.add_child(h)
    h.global_position = pos
    h.add_to_group("heroes")
    _made.append(h)
    return h

func _sfx(pool := -1) -> HeroSfx:
    var s := HeroSfx.new()
    if pool > 0:
        s.pool_size = pool
    s.listener_override = Vector3.ZERO
    tree.root.add_child(s)
    s.set_process(false)
    _made.append(s)
    return s

func _cleanup() -> void:
    for x in _made:
        if is_instance_valid(x):
            x.free()
    _made.clear()

func _ids() -> Array:
    return ["cob", "nidjo", "the_best", "tomo", "twin_tails"]

func _busy_remote(s: HeroSfx) -> Array:
    return s.voices3d.filter(func(v): return s.busy(v))

func test_settings_positional_no_cutoff_no_processing() -> void:
    var s := _sfx()
    check(HeroSfx.DEFAULT_POOL == 32 and s.voices3d.size() == 32, "32 positional voices by default (%d)" % s.voices3d.size())
    for v in s.voices3d:
        check(v is AudioStreamPlayer3D and v.bus == "SFX" and v.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE and v.max_distance == 0.0 and v.attenuation_filter_db == 0.0 and v.attenuation_filter_cutoff_hz >= 20000.0 and v.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED, "3D voice: SFX bus, inverse distance, no cutoff, no filter")
        break
    check(s.local_voices.all(func(v): return v is AudioStreamPlayer and v.bus == "SFX"), "local + cue voices non-positional on SFX")
    var s2 := _sfx(48)
    check(s2.voices3d.size() == 48, "pool size configurable")
    for i in AudioServer.bus_count:
        check(AudioServer.get_bus_effect_count(i) == 0, "no effects on bus " + AudioServer.get_bus_name(i))
    var src := FileAccess.get_file_as_string("res://src/ui/hero_sfx.gd")
    check(not src.contains("AudioEffect") and not src.contains("add_bus") and not src.contains("add_bus_effect"), "HeroSfx adds no bus / effect")
    near(HeroSfx.level_at(0.0, 30.0, false), -6.02, 0.05, "normal: -6 dB at 30 m")
    near(HeroSfx.level_at(0.0, 60.0, false), -12.04, 0.05, "normal: -12 dB at 60 m")
    near(HeroSfx.level_at(HeroSfx.ULT_DB, 80.0, true), 0.0, 0.05, "ult: +6 dB, -6 dB at 80 m -> 0 dB")
    check(HeroSfx.level_at(0.0, 2.0, false) <= 0.0, "a close remote sound is never louder than the local player's own")
    _cleanup()

func test_every_hero_plays_positioned_local_stays_flat() -> void:
    var s := _sfx()
    var me := _hero("cob", Vector3.ZERO, 0)
    s.player = me
    var bot := _hero("tomo", Vector3(40, 0, 0))
    s.on_ability_used(bot, "ability2", "x")
    check(s.last_player is AudioStreamPlayer3D and s.last_player.global_position.is_equal_approx(Vector3(40, 0, 0)) and s.last_file == HeroSfx.path_for("tomo", "ability2"), "bot's E at the bot")
    bot.global_position = Vector3(45, 0, 0)
    s._follow()
    check(s.last_player.global_position.is_equal_approx(Vector3(45, 0, 0)), "voice follows its hero")
    s.on_ability_used(me, "ability1", "x")
    check(s.last_player is AudioStreamPlayer and s.last_player.volume_db == 0.0, "own Shift non-positional, full level")
    s.poll()
    bot.weapon.ammo -= 1
    me.weapon.ammo -= 1
    s.poll()
    check(s.play_count.get("tomo/fire", 0) == 1 and s.play_count.get("cob/fire", 0) == 1, "fire detected for every hero (ammo drop)")
    bot.dead = true
    s.last_play.clear()
    bot.weapon.ammo -= 1
    s.poll()
    check(s.play_count.get("tomo/fire", 0) == 1, "no fire sound while dead")
    _cleanup()

func test_ten_fights_many_concurrent_voices_distant_still_play() -> void:
    var s := _sfx()
    var me := _hero("cob", Vector3.ZERO, 0)
    s.player = me
    var bots: Array = []
    for i in 12:   # 12 fights (24 bots) from 6 m out to 110 m
        var d := 6.0 + i * 9.5
        var a := TAU * i / 12.0
        for side in 2:
            bots.append(_hero(_ids()[(i + side) % 5], Vector3(cos(a), 0, sin(a)) * (d + side * 2.0), side))
    s.poll()
    for b in bots:
        b.weapon.ammo -= 1
    s.poll()
    var busy := _busy_remote(s)
    var far := busy.filter(func(v): return v.global_position.length() >= 60.0)
    var c := s.active_counts()
    print("    MEASURED fights: concurrent voices %d (positional %d, >=60 m %d, farthest %.0f m), steals %d, dropped %d" % [c[0], busy.size(), far.size(), busy.map(func(v): return v.global_position.length()).max(), s.steals, s.dropped])
    check(c[0] >= 10, ">= 10 concurrent voices (%d)" % c[0])
    check(busy.size() == 24 and far.size() >= 8, "every fight audible, distant ones still playing (%d, far %d)" % [busy.size(), far.size()])
    _cleanup()

func test_pool_pressure_steals_farthest_never_local_or_cues() -> void:
    var s := _sfx()
    var me := _hero("nidjo", Vector3.ZERO, 0)
    var mate := _hero("tomo", Vector3(3, 0, 0), 0)
    var foe := _hero("cob", Vector3(4, 0, 0), 1)
    s.player = me
    check(s.play_hero("fire"), "own fire")
    var own_v = s.last_player
    s.on_damage({"source": foe, "target": mate, "amount": 5.0, "killed": false})
    var cue_v = s.last_player
    check(s.last_key == "hit_teammate" and cue_v is AudioStreamPlayer and cue_v != own_v, "team cue on its own local voice")
    near(own_v.volume_db, linear_to_db(0.5), 0.001, "own Niđo fire still at VOLUME_GAIN 0.5")
    var far: Array = []
    for i in 32:
        far.append(_hero(_ids()[i % 5], Vector3(80 + i, 0, 0)))
        s.play_hero("ability1", far[-1])
    check(_busy_remote(s).size() == 32 and s.steals == 0, "pool full with far sounds")
    var near_h: Array = []
    for i in 8:
        near_h.append(_hero(_ids()[i % 5], Vector3(5 + i, 0, 0)))
        check(s.play_hero("ability1", near_h[-1]), "near sound %d gets a voice" % i)
    var dists: Array = _busy_remote(s).map(func(v): return v.global_position.x)
    dists.sort()
    check(s.steals == 8 and dists[-1] <= 80.0 + 23.0 + 0.01, "8 steals took the 8 farthest (max now %.0f m)" % dists[-1])
    var quiet := _hero("cob", Vector3(150, 0, 0))
    check(not s.play_hero("ability1", quiet) and s.dropped == 1, "a sound quieter than everything playing is dropped, not stolen in")
    for i in 100:
        var h := _hero(_ids()[i % 5], Vector3(2, 0, 0))
        s.play_hero("ability2", h)
    check(s.busy(own_v) and s.busy(cue_v) and own_v.get_meta("key") == "nidjo/fire" and cue_v.get_meta("key") == "hit_teammate", "local fire + team cue never stolen")
    check(s.local_voices.all(func(v): return v is AudioStreamPlayer) and s.voices3d.all(func(v): return v.get_meta("kind") == "remote"), "remote sounds only ever use positional voices")
    _cleanup()

func test_ults_top_priority_layer_never_stolen() -> void:
    var s := _sfx()
    var me := _hero("twin_tails", Vector3.ZERO, 0)
    s.player = me
    var fill: Array = []
    for i in 32:
        fill.append(_hero(_ids()[i % 5], Vector3(6 + i, 0, 0)))
        s.play_hero("ability1", fill[-1])
    check(_busy_remote(s).size() == 32, "pool full")
    var ulters := [_hero("cob", Vector3(90, 0, 0)), _hero("cob", Vector3(-90, 0, 0)), _hero("tomo", Vector3(0, 0, 70)), _hero("nidjo", Vector3(0, 0, -100))]
    for h in ulters:
        s.on_ability_used(h, "ultimate", "x")
    s.on_ability_used(me, "ultimate", "x")
    check(s.last_player is AudioStreamPlayer, "own ult non-positional")
    near(s.last_player.volume_db, HeroSfx.ULT_DB, 0.001, "own ult +%.0f dB" % HeroSfx.ULT_DB)
    var uv := _busy_remote(s).filter(func(v): return v.get_meta("ult", false))
    check(uv.size() == 4 and s.play_count.get("cob/ultimate", 0) == 2, "4 remote ults layered, both Cobs (per instance) (%d)" % uv.size())
    for v in uv:
        check(v.unit_size == HeroSfx.ULT_UNIT_SIZE and v.max_db == HeroSfx.ULT_DB and is_equal_approx(v.volume_db, HeroSfx.ULT_DB), "ult voice: widest attenuation, +6 dB")
    for i in 120:   # heavy pressure from loud close sounds
        s.play_hero("ability2", _hero(_ids()[i % 5], Vector3(1, 0, 0)))
    var c := s.active_counts()
    check(uv.all(func(v): return s.busy(v) and v.get_meta("ult")), "no ult stolen under pressure")
    print("    MEASURED ults: %d concurrent (4 remote + own), %d voices playing, pool %d" % [c[1], c[0], s.voices3d.size()])
    check(c[1] >= 5, ">= 3 ults concurrently (%d)" % c[1])
    var many: Array = []
    for i in 36:   # more ults than the pool: extra ult-only voices, still nothing stolen from an ult
        many.append(_hero(_ids()[i % 5], Vector3(10 + i, 0, 0)))
        s.on_ability_used(many[-1], "ultimate", "x")
    var u2 := _busy_remote(s).filter(func(v): return v.get_meta("ult", false)).size()
    check(u2 == mini(40, 32 + HeroSfx.ULT_EXTRA) and uv.all(func(v): return s.busy(v)), "pool of ults grows (extra voices %d), first ults survive (%d ults)" % [s.voices3d.size() - 32, u2])
    _cleanup()

func test_rate_limit_per_instance_and_volume_table() -> void:
    var s := _sfx()
    s.player = _hero("tomo", Vector3.ZERO, 0)
    var a := _hero("cob", Vector3(10, 0, 0))
    var b := _hero("cob", Vector3(-10, 0, 0))
    check(s.play_hero("fire", a) and s.play_hero("fire", b), "two bots on the same hero both play")
    check(not s.play_hero("fire", a), "same instance rate-limited")
    check(s.play_count.get("cob/fire", 0) == 2, "counted per hero id: 2")
    check(HeroSfx.rate_key(a, "fire") != HeroSfx.rate_key(b, "fire"), "keys per instance")
    var want := {"cob": 0.6, "nidjo": 0.5, "the_best": 0.6}
    for id in want:
        var h := _hero(id, Vector3(20, 0, 0))
        check(s.play_hero("fire", h) and is_equal_approx(s.last_player.volume_db, linear_to_db(want[id])), "%s remote fire at VOLUME_GAIN %s" % [id, want[id]])
        check(s.play_hero("ultimate", h) and is_equal_approx(s.last_player.volume_db, HeroSfx.ULT_DB), id + " ult +6 dB")
    near(HeroSfx.play_db("nidjo", "fire"), -6.0206, 0.001, "Niđo fire -6.02 dB")
    _cleanup()

## Online clients: casts arrive through the replicated Events bus (Net.EVENT_SIGNALS, hero refs decoded) and
## remote shots through the snapshot ammo field, so HeroSfx needs no client-only path or core hook.
func test_online_clients_hear_remote_heroes() -> void:
    check(Net.EVENT_SIGNALS.has("ability_used"), "ability_used is replicated to clients")
    check(FileAccess.get_file_as_string("res://src/core/net/net.gd").contains("h.weapon.ammo = int(s[8])"), "snapshot applies ammo to every client-side hero")
    var s := _sfx()
    s.player = _hero("cob", Vector3.ZERO, 0)
    var puppet := _hero("twin_tails", Vector3(25, 0, 0))
    s.poll()
    puppet.weapon.ammo -= 3   # one 20 Hz snapshot can carry several shots: one sound
    s.poll()
    check(s.play_count.get("twin_tails/fire", 0) == 1 and s.last_player is AudioStreamPlayer3D, "puppet shot from snapshot ammo, positional")
    _cleanup()
