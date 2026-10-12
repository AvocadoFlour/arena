# ui — owner: UI bot
`hud.gd` (listens to Events, reads hero state), `pause_menu.gd`, `settings.gd` (window mode,
resolution, sensitivity; user://settings.cfg). Layout uses anchors on a 1280x720 base with
stretch mode canvas_items / aspect expand, so it fits any resolution/aspect. Next: touch controls overlay.

Round 1: `main_menu.gd` (Play / Hero select / Map select / Settings / Quit; emits
`play_requested(hero, map)`), `catalog.gd` (`UiCatalog`: heroes/maps discovered from data JSON),
`keybind_screen.gd` + `keybinds.gd` (rebinding on the Actions InputMap, user://keybinds.cfg,
loaded by Settings at startup), `damage_number.gd` (outlined, distance-scaled Label3D),
`menu_style.gd` (touch-sized widgets, 64 px min height). Tests: `tests/ui_run_tests.gd`.
