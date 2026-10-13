# ui — owner: UI bot
`hud.gd` (listens to Events, reads hero state), `pause_menu.gd`, `settings.gd` (window mode,
resolution, sensitivity; user://settings.cfg). Layout uses anchors on a 1280x720 base with
stretch mode canvas_items / aspect expand, so it fits any resolution/aspect. Next: touch controls overlay.

Round 1: `main_menu.gd` (Play / Hero select / Map select / Settings / Quit; emits
`play_requested(hero, map)`), `catalog.gd` (`UiCatalog`: heroes/maps discovered from data JSON),
`keybind_screen.gd` + `keybinds.gd` (rebinding on the Actions InputMap, user://keybinds.cfg,
loaded by Settings at startup), `damage_number.gd` (outlined, distance-scaled Label3D),
`menu_style.gd` (touch-sized widgets, 64 px min height). Tests: `tests/ui_run_tests.gd`.

Round 2: HUD ability key labels read live bindings (`Hud.key_label`); `scoreboard.gd` (hold Tab,
action `scoreboard`, rebindable) fed by `match_stats.gd` (K/D/damage from Events);
`match_end_screen.gd` (VICTORY/DEFEAT/DRAW + final board, Play again/Main menu/Quit);
`capture_widget.gd` (capture progress bars, binds to Events capture signals once they exist) and
`mock_capture_source.gd`. Tests: `tests/ui_round2_test.gd`.

Round 3: ammo counter hidden for melee / no-ammo primaries (`Hud.shows_ammo`); hero select shows
role labels (`UiCatalog.role_label`); Settings adds FOV (applied to the current Camera3D) and
Master/Music/SFX volumes (applied only to existing buses); MainMenu network hook
(`network_slot`, `add_menu_entry()`, `add_screen()`). Tests: `tests/ui_round3_test.gd`.

Round 4: audio sliders drive the Master/Music/SFX buses (default_bus_layout.tres).
**Low quality** (for Maps/FX): read `Settings.low_quality` (bool, persisted in user://settings.cfg
`[video] low_quality`), and connect `Settings.low_quality_changed(on: bool)` to react live. Emitted only
when the value changes (also once at startup if the saved value is true). Set via
`Settings.set_low_quality(on)` (UI toggle on the Settings page). `MenuStyle.polish(screen)` is applied by
`MainMenu.add_screen` to screens built elsewhere (core NetPanel): visual only (touch sizes, button/edit
styles, column width/spacing); never changes text, signals or logic.

Round 5: `kill_feed.gd` (`KillFeed`: newest on top, max 5, 5 s life with fade, player kill/death
highlight, weapon/ability name from the killer's def by damage kind); `DamageNumber.pop()` replaces the
HUD's inline tween (scale punch, eased rise, fade; big hits >= 50 and killing blows larger, thicker
outline, "!" on kills). Tests: `tests/ui_round5_test.gd` (incl. real NetPanel host/join with Net.offline).

Round 6: kill feed and damage numbers use `ability_id` / `crit` (INTERFACES §3/§4).
`KillFeed.weapon_name(killer, kind, ability_id)`: id (or type) → ability `name` from the killer's def;
`""` → primary weapon name (`primary.name` if present, else "Melee"/"Primary"), "Fall" for falls,
"Environment" with no killer (killer column shows "World"); field missing (older events) → legacy
kind-based inference. `DamageNumber.from_event(ev)`: colour = kill > crit > ultimate (ability_id is the
source's ultimate slot) > ability > primary; size = big hit (>= 50) / kill; crit adds "CRIT", punch, shake.
Tests: `tests/ui_round6_test.gd`.
