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

## Round 4
1. **INTERFACES: low-quality setting.** Please document (e.g. new §10 "Player settings"):
   `Settings.low_quality: bool` (read-only for non-UI), `Settings.low_quality_changed(on: bool)` signal,
   persisted by UI. Maps/FX read it; only UI sets it (`Settings.set_low_quality`).
2. **NetPanel polish** is done UI-side: `MainMenu.add_screen` runs `MenuStyle.polish(c)` (touch sizes,
   styles, layout spacing). No core file edited. Optional cleanup in core-owned `net_panel.gd`: build its
   LineEdits with a UI helper (`MenuStyle.style_line_edit`) instead of the 48 px `_edit()`, so the polish pass
   isn't needed.
3. **Testability of NetPanel("host")**: `_ready` calls `Net.fetch_public_ip()` (HTTP to api.ipify.org).
   UI tests avoid instantiating the host panel for that reason. A flag (e.g. `Net.offline` / skip under
   headless tests) would let UI test the real host screen.
4. Core's edit to `tests/ui_round3_test.gd` (Music now applied) matches UI behaviour; kept as is.

## Round 5
1. **Ability id on kills/damage**: `Events.killed` / `damage_dealt` carry only `kind`. The kill feed infers the
   ability name from the killer's def by damage kind and falls back to the kind when ambiguous (e.g. a hero with
   two `slam`-producing abilities). Adding `ability_id` (or `slot`) to both payloads would make it exact.
2. **Crits**: no crit/headshot flag exists. DamageNumber emphasises big hits (>= 50) and killing blows; if a
   `crit: bool` is added to `damage_dealt`, UI will style it.

## Round 6
Round 5 requests 1–2 done by core (ability_id, crit). UI now uses them.
1. Optional: a `"name"` on hero `primary` defs (e.g. "Pebble Gun"); the kill feed shows it when present,
   otherwise "Primary" / "Melee". Creative names need user approval (TEAM rule 8), so this is a heroes/user call.

## Round 7 (UI sounds)
1. Optional: an `Events.ability_ready(hero, slot)` signal (cooldown finished / ult full). UI currently
   edge-detects from `ability.cooldown.is_ready()` and `hero.ult.is_full()` in the HUD each frame, which works
   but would also fire on respawn cooldown resets.
2. No assets added: all SFX are synthesised in `src/ui/ui_sfx.gd`; no licence entries needed.

## Queue 2 (scoreboard / match-end summary)
1. **Healing event** (INTERFACES §3/§4): `Events.healed({source: Hero|null, target: Hero, amount: float, ability_id})`,
   emitted from `hero.heal()` with the amount actually restored (and optionally overheal granted). The healing
   column shows "-" and "Top healing" is hidden until this exists; UI picks it up automatically (`has_signal`).

## Queue 3 (pause overlay)
1. **Leave-match hook in main.gd**: there is no documented "leave match" entry point. Please connect
   `menu.leave_requested.connect(func(): _restart(false))` (both offline and client setup paths) and document it
   in INTERFACES (§9 or a new pause/overlay note). Until then `PauseMenu.leave()` falls back to emitting
   `hud.match_end.main_menu`, the documented route that reloads into the main menu (and closes Net online).
2. main.gd's `_unhandled_input` online branch (`get_tree().paused = false` after `menu.open()`) is now redundant:
   PauseMenu never pauses when `Net.is_online()`. Harmless; can be removed.
3. `Net.is_online()` is used by main.gd but INTERFACES §10 only lists the modes; please list `is_online()` /
   `is_host()` / `is_client()` there, since UI depends on `is_online()`.
4. `Events.ability_ready(hero, slot)` still not on master; the HUD binds it automatically when added.

## Miku queue 2 (ping indicator / connection lost)
1. **Ping data**: Net exposes no RTT and INTERFACES §10 doesn't sanction reading the ENet peer from UI. Please add
   `Net.ping_ms() -> int` (client: RTT to host, e.g. `ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME)`; host: -1 or
   worst peer) and `Net.last_packet_age() -> float` (s since the last snapshot/packet). The HUD indicator shows
   "Ping --" and no stall warning until then, and uses them automatically (`has_method`).
2. **Document `Net.disconnected(reason: String)`** in §10 (UI listens to it). Reasons seen: "host closed the
   connection", "could not connect", host rejects.
3. **main.gd `_on_net_lost` restarts immediately**, so the UI's "Host left / Connection lost" screen is replaced by
   the reload before the player can read it. Proposal: in-match, don't `_restart`; instead connect
   `hud.conn_lost.return_requested.connect(func(): _restart(false))` (or keep relying on `menu.leave_requested`,
   which the screen already uses). Net state is already closed by then, so `_restart` stays the single exit.
