extends "res://tests/test_base.gd"
## UI round 6: ability_id / crit from Events (INTERFACES §3/§4) in kill feed and damage numbers.
var tree: SceneTree

class FakeHero extends Node:
    var display_name := ""
    var team := 0
    var def := {}
    func _init(n: String, d := {}) -> void:
        display_name = n
        def = d

func _hero(id: String) -> FakeHero:
    return FakeHero.new(id, JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id)))

func test_ability_id_maps_to_def_name() -> void:
    for h in UiCatalog.list_heroes():
        var f := _hero(h.id)
        for slot in ["ability1", "ability2", "ultimate"]:
            var a: Dictionary = f.def.abilities[slot]
            check(KillFeed.weapon_name(f, "whatever", a.id) == a.name, "%s %s -> %s" % [h.id, a.id, a.name])
            check(KillFeed.weapon_name(f, "x", a.type) == f.def.abilities[KillFeed.slot_of(f.def, a.type)].name, "type id accepted")
        f.free()
    var cob := _hero("cob")
    check(KillFeed.weapon_name(cob, "slam", "unknown_thing") == "Unknown Thing", "unknown id prettified")
    cob.free()

func test_empty_ability_id_primary_melee_fall_world() -> void:
    var cob := _hero("cob")
    var best := _hero("the_best")
    check(KillFeed.weapon_name(cob, "primary", "") == "Primary", "hitscan primary (no name field)")
    check(KillFeed.weapon_name(best, "primary", "") == "Melee", "melee primary")
    check(KillFeed.weapon_name(FakeHero.new("x", {"primary": {"type": "hitscan", "name": "Pebble Gun"}}), "primary", "") == "Pebble Gun", "primary.name used if present")
    check(KillFeed.weapon_name(null, "fall", "") == "Fall", "fall")
    check(KillFeed.weapon_name(cob, "fall", "") == "Fall", "fall even with killer")
    check(KillFeed.weapon_name(null, "primary", "") == "Environment", "no killer")
    var bot := FakeHero.new("Bot")
    check(KillFeed.entry_text({"killer": null, "victim": bot, "kind": "fall", "ability_id": ""}) == "World  [Fall]  Bot", "fall entry")
    check(KillFeed.entry_text({"killer": cob, "victim": bot, "kind": "slam", "ability_id": "quarry_quake"}) == "cob  [Quarry Quake]  Bot", "ability entry")
    cob.free(); best.free(); bot.free()

func test_legacy_events_without_field() -> void:
    var cob := _hero("cob")
    var bot := FakeHero.new("Bot")
    check(KillFeed.entry_text({"killer": cob, "victim": bot, "kind": "charge"}) == "cob  [Boulder Roll]  Bot", "legacy inference")
    var d := DamageNumber.from_event({"amount": 12.0, "kind": "primary", "killed": false, "source": cob})
    check(not d.crit and not d.ultimate and d.modulate == DamageNumber.COL_PRIMARY, "legacy damage event ok")
    d.free(); cob.free(); bot.free()

func test_damage_number_ultimate_crit_big_independent() -> void:
    var cob := _hero("cob")
    var ult := DamageNumber.from_event({"source": cob, "amount": 30.0, "kind": "slam", "killed": false, "ability_id": "quarry_quake", "crit": false})
    check(ult.ultimate and ult.modulate == DamageNumber.COL_ULT, "ultimate by ability_id (kind is slam)")
    var ab := DamageNumber.from_event({"source": cob, "amount": 30.0, "kind": "charge", "killed": false, "ability_id": "boulder_roll", "crit": false})
    check(not ab.ultimate and ab.modulate == DamageNumber.COL_ABILITY, "regular ability colour")
    var cr := DamageNumber.from_event({"source": cob, "amount": 20.0, "kind": "primary", "killed": false, "ability_id": "", "crit": true})
    check(cr.crit and cr.modulate == DamageNumber.COL_CRIT and cr.text.begins_with("CRIT"), "crit styled")
    var base := DamageNumber.pop_params(20, false)
    var pc := DamageNumber.pop_params(20, false, true)
    var pb := DamageNumber.pop_params(80, false)
    var pbc := DamageNumber.pop_params(80, false, true)
    check(pc.punch > base.punch and pc.shake > 0.0 and pb.shake == 0.0, "crit adds punch + shake, big does not")
    check(pb.size > base.size and pbc.size > pb.size and pbc.size > pc.size, "big and crit stack independently")
    tree.root.add_child(cr)
    cr.pop()
    check(not cr.big, "small crit is not a big hit")
    var bg := DamageNumber.from_event({"source": cob, "amount": 80.0, "kind": "primary", "killed": false, "ability_id": "", "crit": false})
    tree.root.add_child(bg)
    bg.pop()
    check(bg.big and not bg.crit and bg.modulate == DamageNumber.COL_PRIMARY, "big non-crit keeps primary colour")
    for n in [ult, ab, cr, bg, cob]:
        n.free()
