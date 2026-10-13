extends "res://tests/test_base.gd"
## Miku queue item 1: kill feed with team-coloured names + ability badge; "Damage numbers" setting.
var tree: SceneTree

class FakeHero extends Node:
    var display_name := ""
    var team := 0
    var def = null
    func _init(n: String, t: int, d = null) -> void:
        display_name = n
        team = t
        def = d

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func test_entry_layout_team_colours_badge() -> void:
    var me := FakeHero.new("You", 0, _def("cob"))
    var foe := FakeHero.new("Bot 2", 1, _def("the_best"))
    var kf := KillFeed.new()
    kf.player = me
    tree.root.add_child(kf)
    var row := kf.on_kill({"killer": foe, "victim": me, "kind": "primary", "ability_id": ""})
    var h: HBoxContainer = row.find_child("Row", true, false)
    check(h.get_child(0).name == "Killer" and h.get_child(1).name == "Ability" and h.get_child(2).name == "Victim", "killer / badge / victim order")
    var kl: Label = h.get_child(0)
    var vl: Label = h.get_child(2)
    check(kl.label_settings.font_color == HeroBadge.TEAM_COLORS[1], "killer in team 1 colour")
    check(vl.label_settings.font_color == HeroBadge.TEAM_COLORS[0], "victim in team 0 colour")
    var b: HeroBadge = h.get_child(1)
    check(b.initials == "ME" and b.get_meta("label") == "Melee" and b.ring == HeroBadge.TEAM_COLORS[1], "melee badge, killer ring")
    check(row.get_meta("highlight") == "death", "player death highlighted")
    var sb: StyleBoxFlat = row.get_theme_stylebox("panel")
    check(sb.border_color != HeroBadge.TEAM_COLORS[0] and sb.border_color != HeroBadge.TEAM_COLORS[1], "highlight colour isn't a team colour")
    var r2 := kf.on_kill({"killer": me, "victim": foe, "kind": "slam", "ability_id": "quarry_quake"})
    var b2: HeroBadge = r2.find_child("Ability", true, false)
    check(b2.initials == "QQ" and b2.fill == Color("#8a6a40"), "ability initials + ability def colour")
    check(r2.get_meta("highlight") == "kill" and r2.custom_minimum_size.y >= 40, "kill highlight, row height")
    var r3 := kf.on_kill({"killer": null, "victim": foe, "kind": "fall", "ability_id": ""})
    var k3: Label = r3.find_child("Killer", true, false)
    check(k3.text == "World" and r3.find_child("Ability", true, false).initials == "FA", "world + fall badge")
    check(not r3.has_meta("highlight"), "others plain")
    check(kf.get_child(0) == r3, "newest on top")
    check(KillFeed.LIFETIME == 5.0, "entries last 5 s")
    kf.free(); me.free(); foe.free()

func test_damage_numbers_setting() -> void:
    var keep: bool = Settings.damage_numbers
    var fresh = load("res://src/ui/settings.gd").new()
    check(fresh.damage_numbers == true, "default on")
    fresh.free()
    var path := "user://ui_test_dn.cfg"
    Settings.damage_numbers = false
    Settings.save(path)
    Settings.damage_numbers = true
    check(Settings.load_from(path) and not Settings.damage_numbers, "persisted off")
    var mm := MainMenu.new()
    tree.root.add_child(mm)
    var t: CheckButton = mm.screens.settings.find_child("DamageNumbersToggle", true, false)
    check(t != null and t.text == "Damage numbers" and t.custom_minimum_size.y >= 64, "touch toggle on Settings")
    check(not t.button_pressed, "reflects setting")
    t.button_pressed = true
    check(Settings.damage_numbers, "toggle turns on")
    mm.free()
    Settings.damage_numbers = keep
    Settings.save()
    DirAccess.remove_absolute(path)

func test_hud_spawns_no_numbers_when_off() -> void:
    var keep: bool = Settings.damage_numbers
    var world := Node3D.new()
    tree.root.add_child(world)
    var me := FakeHero.new("You", 0, _def("cob"))
    world.add_child(me)
    var foe := FakeHero.new("Bot", 1, _def("cob"))
    var hud := Hud.new()
    hud.player = me
    hud.crosshair = Hud.Crosshair.new()
    hud.add_child(hud.crosshair)
    var ev := {"source": me, "target": foe, "amount": 20.0, "pos": Vector3.ZERO, "kind": "primary", "killed": false, "ability_id": "", "crit": false}
    Settings.damage_numbers = false
    hud._on_damage(ev)
    check(world.find_children("*", "DamageNumber", true, false).is_empty(), "off: none spawned")
    check(hud.crosshair.hit_t > 0.0, "hit marker still shown")
    Settings.damage_numbers = true
    hud._on_damage(ev)
    check(world.find_children("*", "DamageNumber", true, false).size() == 1, "on: spawned")
    var crit := DamageNumber.from_event({"amount": 20.0, "kind": "primary", "crit": true})
    check(crit.crit and crit.modulate == DamageNumber.COL_CRIT, "crit styling ready")
    crit.free()
    Settings.damage_numbers = keep
    hud.free(); foe.free(); world.free()
