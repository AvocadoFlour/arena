extends Node3D
## HUD ability tooltip on the real composition root (main.tscn, offline): icons wired, entries match the
## player's def, hover over an icon via Hud._input shows name + live key, event left unhandled, leave hides.
var results: Array = []
var done := false
var m
var t := 0.0

func _rec(n: String, ok: bool, info := "") -> void:
    results.append([n, ok, info])

func _ready() -> void:
    GameConfig.skip_menu_once = true
    m = load("res://src/main.tscn").instantiate()
    add_child(m)

func _physics_process(dt: float) -> void:
    if done:
        return
    t += dt
    if t < 0.5:
        return
    var hud: Hud = m.hud
    var tip: AbilityTooltip = hud.tooltip
    _rec("wired", tip != null and tip.panels.keys() == ["ability1", "ability2", "ultimate"])
    var names_ok := true
    for s in ["ability1", "ability2", "ultimate"]:
        names_ok = names_ok and hud.ability_entry(s).get("name", "") == String(m.player.def.abilities[s].name)
    _rec("entries_match_def", names_ok)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var ev := InputEventMouseMotion.new()
    ev.position = (tip.panels.ability1 as Control).get_global_rect().get_center()
    hud._input(ev)
    _rec("hover_shows", tip.visible and tip.slot == "ability1" and tip.title.text.contains("[%s]" % Hud.key_label("ability1")), tip.title.text)
    _rec("not_handled", not get_viewport().is_input_handled())
    var r := tip.get_global_rect()
    _rec("on_screen", Rect2(Vector2.ZERO, tip.get_viewport_rect().size).encloses(r), str(r))
    var away := InputEventMouseMotion.new()
    away.position = Vector2(20, 20)
    hud._input(away)
    _rec("leave_hides", not tip.visible)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    done = true
