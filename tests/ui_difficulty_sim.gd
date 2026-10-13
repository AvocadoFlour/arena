extends Node3D
## Pre-match difficulty end to end with the real hooks: pick Hard for the enemy team in the main menu,
## start a real offline match (main.tscn), check the enemy bots' BotBrain runs "hard".
## The Esc Match page reports the live hook state of the real root.
var results: Array = []
var done := false
var m
var t := 0.0
var keep_s := {}
var keep_g := ""

func _rec(n: String, ok: bool, info := "") -> void:
    results.append([n, ok, info])

func _ready() -> void:
    keep_s = Settings.bot_difficulty.duplicate()
    keep_g = GameConfig.bot_difficulty
    var mm := MainMenu.new()
    add_child(mm)
    mm.diff_picker.button(1, "hard").pressed.emit()
    _rec("menu_sets_config", GameConfig.bot_difficulty == "hard")
    mm.free()
    GameConfig.skip_menu_once = true
    m = load("res://src/main.tscn").instantiate()
    add_child(m)

func _physics_process(dt: float) -> void:
    if done:
        return
    t += dt
    if t < 0.3:
        return
    var bots := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.team == 1 and h.input_source is BotBrain)
    _rec("enemy_bots_hard", bots.size() > 0 and bots.all(func(h): return h.input_source.difficulty == "hard"), "%d bots" % bots.size())
    _rec("stats_difficulty", m.stats.get("difficulty") == "hard")
    var page: MatchPage = m.menu.match_page
    var live: bool = m.has_method("set_bot_difficulty")
    _rec("match_page_matches_hook", (page.diff_picker.note.text == MatchPage.NA) != live, "live hook=%s" % live)
    Settings.bot_difficulty = keep_s
    Settings.save()
    GameConfig.bot_difficulty = keep_g
    Net.world = null
    get_tree().paused = false
    done = true
