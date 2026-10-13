extends "res://tests/test_base.gd"
## Item 2: bot difficulty picker (pre-match in Map select, live on the Esc Match page), per team,
## Easy/Normal/Hard only, host-only online, persisted, "Not available yet" without hooks.
var tree: SceneTree

class CfgGlobal extends RefCounted:   # today's GameConfig: one global bot_difficulty
    var bot_difficulty := "normal"

class CfgTeams extends CfgGlobal:     # spec: per-team pre-match
    var teams := {0: "normal", 1: "normal"}
    func set_team_difficulty(t: int, lv: String) -> bool:
        teams[t] = lv
        return true

class MockNet extends RefCounted:
    var mode := "offline"
    func is_online() -> bool: return mode != "offline"
    func is_client() -> bool: return mode == "client"

class LiveRoot extends Node:
    signal bot_difficulty_changed(team: int, level: String)
    var lv := {0: "easy", 1: "hard"}
    func match_bot_difficulty() -> Dictionary: return lv.duplicate()
    func set_bot_difficulty(t: int, l: String) -> bool:
        lv[t] = l
        bot_difficulty_changed.emit(t, l)
        return true

func test_adapter_prematch() -> void:
    var g := CfgGlobal.new()
    var d := DifficultyControl.new(g, null, MockNet.new())
    check(not d.prematch_available(0) and d.prematch_available(1), "global cfg: enemy row only")
    check(d.apply_prematch(1, "hard") and g.bot_difficulty == "hard", "enemy -> GameConfig.bot_difficulty")
    check(not d.apply_prematch(0, "easy") and g.bot_difficulty == "hard", "own team not applied")
    check(not d.apply_prematch(1, "insane"), "invalid level")
    var c := CfgTeams.new()
    var d2 := DifficultyControl.new(c, null, MockNet.new())
    check(d2.prematch_available(0) and d2.apply_prematch(0, "easy") and c.teams[0] == "easy", "per-team hook used")
    check(DifficultyControl.LABELS.values() == ["Easy", "Normal", "Hard"], "labels")

func test_settings_persist() -> void:
    var keep: Dictionary = Settings.bot_difficulty.duplicate()
    var p := "user://ui_round15_settings.cfg"
    Settings.bot_difficulty = {0: "easy", 1: "hard"}
    Settings.save(p)
    Settings.bot_difficulty = {0: "normal", 1: "normal"}
    Settings.load_from(p)
    check(Settings.bot_difficulty[0] == "easy" and Settings.bot_difficulty[1] == "hard", "round trip")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
    Settings.bot_difficulty = keep

func test_main_menu_picker_real_gameconfig() -> void:
    var keep: Dictionary = Settings.bot_difficulty.duplicate()
    var keep_g: String = GameConfig.bot_difficulty
    Settings.bot_difficulty = {0: "normal", 1: "easy"}
    var m := MainMenu.new()
    tree.root.add_child(m)
    var p := m.diff_picker
    check(p != null and m.screens.maps.find_child("DifficultyPicker", true, false) == p, "picker on Map select")
    check(GameConfig.bot_difficulty == "easy", "saved choice applied to GameConfig on open")
    check(p.pressed_level(1) == "easy", "shows saved")
    for t in [0, 1]:
        for lv in DifficultyControl.LEVELS:
            var b := p.button(t, lv)
            check(b.custom_minimum_size.y >= 64 and b.custom_minimum_size.x >= 100 and b.text == DifficultyControl.LABELS[lv], "touch " + b.text)
    p.button(1, "hard").pressed.emit()
    check(GameConfig.bot_difficulty == "hard" and Settings.bot_difficulty[1] == "hard" and p.pressed_level(1) == "hard", "pick applies + persists")
    var n := 0
    for lv in DifficultyControl.LEVELS:
        n += int(p.button(1, lv).button_pressed)
    check(n == 1, "one pressed")
    # real GameConfig has no per-team hook yet: own-team row disabled with the note
    if not GameConfig.has_method("set_team_difficulty"):
        check(p.button(0, "easy").disabled and p.note.text.contains(MatchPage.NA), "own team not available yet")
    check(m.hero_info.text.contains("Bots: "), "summary line")
    m.free()
    Settings.bot_difficulty = keep
    Settings.save()
    GameConfig.bot_difficulty = keep_g

func _page(root: Object, net: MockNet) -> PauseMenu:
    var pm := PauseMenu.new()
    tree.root.add_child(pm)
    pm.match_page.set_difficulty_control(DifficultyControl.new(GameConfig, root, net))
    return pm

func test_match_page_live_host_and_client() -> void:
    var r := LiveRoot.new()
    var n := MockNet.new()
    var pm := _page(r, n)
    var p := pm.match_page.diff_picker
    check(p.pressed_level(0) == "easy" and p.pressed_level(1) == "hard" and p.note.text == "", "live levels shown")
    p.button(1, "normal").pressed.emit()
    check(r.lv[1] == "normal" and p.pressed_level(1) == "normal", "offline/host sets live")
    r.set_bot_difficulty(0, "hard")
    check(p.pressed_level(0) == "hard", "signal refreshes")
    n.mode = "client"
    pm.match_page.refresh()
    check(p.button(0, "easy").disabled and p.button(1, "hard").disabled and p.note.text.contains("host"), "client disabled + note")
    p.button(1, "easy").pressed.emit()
    check(r.lv[1] == "normal", "client cannot set")
    pm.free()
    r.free()

func test_match_page_missing_hook() -> void:
    var r := Node.new()
    var pm := _page(r, MockNet.new())
    var p := pm.match_page.diff_picker
    check(p.note.text == MatchPage.NA and p.button(1, "hard").disabled, "not available yet")
    pm.free()
    r.free()
