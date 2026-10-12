# UI requests to lead (branch ui)

Round 1 requests 1–3 done on master (bbd8445). Round 1 #4 (live HUD key labels) is done in round 2.

## Round 2
1. **`scoreboard` action in `Actions.BINDINGS`** (src/core/actions.gd): `"scoreboard": [KEY_TAB]`.
   UI-only (never read into InputFrame). Until then UI registers it in InputMap via
   `Keybinds.UI_BINDINGS` / `ensure_ui_actions()`; that code skips itself once core defines it.
2. **Capture-point events on `Events`** (INTERFACES §4, published by Maps):
   - `signal capture_progress(ev)`, ev = `{zone_id: String, team: int (-1 = neutral), progress: float 0..1, contested: bool}`
     (emit on change, or ≤10 Hz)
   - `signal capture_completed(ev)`, ev = `{zone_id: String, team: int}`
   `zone_id` = the `zones[].id` from map JSON §6. HUD `CaptureWidget` binds to Events automatically once
   these exist (it checks `has_signal`); `MockCaptureSource` (src/ui) emits the same shapes for tests.
3. **Match end event**: `signal match_ended(result)`, result = `{winner_team: int (-1 = draw), reason: String}`.
   HUD shows `MatchEndScreen` on it automatically. No match rules (score/time limit) exist yet, so
   nothing emits it. Screen emits `play_again` / `main_menu`: main.gd should connect them via
   `hud.match_end` (reload main.tscn / show MainMenu) and pause gameplay.
4. Optional: smoke test could emit a fake `match_ended` near the end to exercise the screen in the gate.

## Round 3
1. **Network menu hook** for core: `MainMenu.network_slot` (hidden VBox under Play),
   `main_menu.add_menu_entry(text, cb) -> Button`, `main_menu.add_screen(name, control)` + `show_screen(name)`.
   Please document in INTERFACES §2.3 if you adopt it.
2. **FOV**: UI sets `fov` on the current Camera3D at HUD setup and on settings change (view-only).
   If CameraRig ever animates FOV (sprint/zoom), please read `Settings.fov` as its base instead.
3. **Audio buses**: only `Master` exists. Volumes for `Music`/`SFX` are persisted and applied automatically
   once buses with those names exist (e.g. a default_bus_layout.tres, core-owned project setting).
4. Roles: every current def has `role`; no request. Hero select shows "Unknown role" if one is missing.
