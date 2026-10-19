extends Node3D
## Real HUD on main.tscn (offline): the ability3 cooldown slot sits between ability2 and ultimate, is hidden
## for a hero without ability3 (no errors), shows when the slot exists (name + MOUSE RIGHT) and hides again.
var results: Array = []
var done := false
var m
var t := 0.0
var step := 0
var orig := ""

func _rec(n: String, ok: bool, info := "") -> void:
    results.append([n, ok, info])

func _ready() -> void:
    orig = GameConfig.hero_id
    GameConfig.set_hero("cob")
    GameConfig.skip_menu_once = true
    m = load("res://src/main.tscn").instantiate()
    add_child(m)

func _physics_process(dt: float) -> void:
    if done:
        return
    t += dt
    if t < 0.4:
        return
    var hud = m.hud
    var row: Node = hud.ab_labels.ability1[0].get_parent().get_parent()
    var names: Array = row.get_children().map(func(c): return String(c.name))
    var pc: Control = hud.ab_labels.ability3[0].get_parent()
    match step:
        0:
            _rec("slot_order", names == ["Slot_ability1", "Slot_ability2", "Slot_ability3", "Slot_ultimate"], str(names))
            _rec("hidden_without_ability3", not m.player.abilities.has("ability3") and not pc.visible, str(pc.visible))
            m.player.abilities["ability3"] = m.player.abilities["ability2"]   # stand-in until Heroes adds the slot
            step = 1
        1:
            var txt: String = hud.ab_labels.ability3[0].text
            _rec("shown_with_ability3", pc.visible and txt.begins_with("[MOUSE RIGHT]"), txt.replace("\n", " | "))
            m.player.abilities.erase("ability3")
            step = 2
        2:
            _rec("hidden_again", not pc.visible)
            GameConfig.set_hero(orig)
            done = true
