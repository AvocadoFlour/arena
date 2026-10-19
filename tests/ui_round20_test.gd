extends "res://tests/test_base.gd"
## HeroSfx per-hero/slot playback volume (VOLUME_GAIN): Cob / The Best left-click sounds at linear_to_db(0.6)
## (60% amplitude), Niđo's at linear_to_db(0.36) (36%, about -8.87 dB), all else 0 dB.
var tree: SceneTree

class MockHero extends RefCounted:
    var def := {}
    var team := 0

func _sfx(id: String) -> HeroSfx:
    var s := HeroSfx.new()
    tree.root.add_child(s)
    var h := MockHero.new()
    h.def = {"id": id}
    s.player = h
    return s

func test_primary_volume_table_applied_on_play() -> void:
    var want := {"cob": "weapons/ric1.wav", "nidjo": "player/axhit1.wav", "the_best": "knight/sword1.wav"}
    var gain := {"cob": 0.6, "nidjo": 0.36, "the_best": 0.6}
    var approx_db := {"cob": -4.437, "nidjo": -8.874, "the_best": -4.437}
    for id in want:
        check(HeroSfx.path_for(id, "fire") == HeroSfx.BASE + want[id], id + " fire is " + want[id])
        check(HeroSfx.VOLUME_GAIN[id].fire == gain[id] and HeroSfx.volume_db_for(id, "fire") == linear_to_db(gain[id]), "%s fire %s amplitude in the table" % [id, gain[id]])
        var s := _sfx(id)
        for p in s.players:
            p.volume_db = 3.0   # stale value from a previous play must be overwritten
        check(s.play_hero("fire") and s.last_file == HeroSfx.BASE + want[id], id + " fire plays")
        check(s.last_player != null and is_equal_approx(s.last_player.volume_db, linear_to_db(gain[id])) and absf(s.last_player.volume_db - approx_db[id]) < 0.01, "%s fire player volume_db = %s" % [id, s.last_player.volume_db if s.last_player else "?"])
        check(s.play_hero("ability1") and s.last_player.volume_db == 0.0, id + " ability1 stays 0 dB")
        s.free()
    for id in ["tomo", "twin_tails"]:
        check(HeroSfx.volume_db_for(id, "fire") == 0.0, id + " fire 0 dB")
        var s := _sfx(id)
        check(s.play_hero("fire") and s.last_player.volume_db == 0.0, id + " fire player volume_db 0")
        s.free()
    var c := _sfx("cob")
    check(c.play_cue("hit_me") and c.last_player.volume_db == 0.0, "cues 0 dB")
    c.free()
    for id in HeroSfx.HERO:
        for slot in HeroSfx.SLOTS:
            var v := HeroSfx.volume_db_for(id, slot)
            check(v == (linear_to_db(gain[id]) if slot == "fire" and id in want else 0.0), "%s/%s = %s dB" % [id, slot, v])
