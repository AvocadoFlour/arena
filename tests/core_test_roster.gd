extends "res://tests/test_base.gd"
## Roster: Twin Tails, The Best, Cob (v0.3), Tomo and Niđo (user-approved) are selectable; placeholders live in src/heroes/archive/.

func test_hero_ids_are_the_v03_roster() -> void:
    var ids: Array = GameConfig.hero_ids()
    check(ids == ["cob", "nidjo", "the_best", "tomo", "twin_tails"], "hero_ids: %s" % [ids])

func test_hero_select_lists_only_new_heroes() -> void:
    var names: Array = UiCatalog.list_heroes().map(func(h): return h.name)
    names.sort()
    check(names == ["Cob", "Niđo", "The Best", "Tomo", "Twin Tails"], "hero select: %s" % [names])

func test_default_hero_is_twin_tails() -> void:
    check(GameConfig.DEFAULT_HERO == "twin_tails", "default hero")

func test_archive_not_selectable() -> void:
    for id in ["kestrel", "rampart", "willow"]:
        check(FileAccess.file_exists("res://src/heroes/archive/%s.json" % id), "archived %s exists" % id)
        check(not GameConfig.hero_ids().has(id), "%s not selectable" % id)
