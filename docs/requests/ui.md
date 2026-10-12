# UI requests to lead (branch ui)

1. **Run UI tests in the gate.** `tests/run_tests.gd` SUITES is hardcoded and runs suites in
   `_initialize` (before autoloads are ready). UI tests need `Actions`/InputMap and a SceneTree, so
   they live in `tests/ui_run_tests.gd` (first-frame runner). Please either add to build.sh step 2:
   `"$GODOT" --headless --path . -s tests/ui_run_tests.gd | tee build/ui_tests.log; grep -q "UI RESULT: .* 0 failed" build/ui_tests.log`
   or make run_tests.gd auto-discover `tests/*_test*.gd` and run after the first frame.
2. **Wire the main menu in `src/main.gd`** (lead-owned). Proposed: when no test arg is given, add
   `MainMenu.new()` first and build the match on `play_requested(hero_path, map_path)` instead of
   the `HERO`/`MAP` consts; on Esc in-match, PauseMenu could get a "Main menu" button later.
   Selection is also readable via `UiCatalog.selected_hero / selected_map`.
3. **Hero/map listing interface.** INTERFACES.md defines the JSON shape but no listing API. UI
   discovers `src/heroes/*.json` / `src/maps/*.json` via `UiCatalog.list_heroes()/list_maps()`.
   Proposal: bless this as INTERFACES §2.3 / §6.1 (or move to src/core as `Registry`), and state
   that every `.json` in those folders is a playable hero/map (no non-hero json there).
4. **Ability key labels in HUD** still use a constant (SHIFT/E/Q); will switch to
   `Keybinds.binding_text()` next round if OK.
