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

## Miku queue 3 (hero preview)
- core/heroes: please document in INTERFACES a supported way for UI to build a hero's display model (currently UI calls `HeroModel.create(model_scene)` read-only, with a raw-GLB fallback and a mirror of hero.gd's §2 primitive build). If this is not meant to be public, tell UI which builder to use.
- ai: `ai_teamplay_driver::team_groups_up` fails deterministically on clean master 88f6d8d (6.6 m vs 5.9 m baseline), with or without UI changes; this blocks ./build.sh.

## In-match controls hook spec (Esc overlay "Match" page; adapter src/ui/match_control.gd)
UI calls these on the composition root (main.gd, the PauseMenu's parent) only if `has_method` / `has_signal`
says they exist. Until then the page shows "Not available yet". No UI changes are needed when core adds them.
Owner: core (main.gd + Net). Swap delay owner: **core**, `const HERO_SWAP_DELAY := 3.0` in main.gd
(host/offline runs the timer, UI only displays the `delay` it is given).

Query (every side, local data):
- `func match_bot_counts() -> Dictionary`: `{0: int, 1: int}` current bot count per team (clients: last value from host).
- `func local_team() -> int`: local player's team (0/1).
- `func local_net_id() -> int`: local player's hero net_id (offline: player's id, e.g. Net.register id). Used to filter swap signals.

Commands:
- `func set_bot_count(team: int, n: int) -> bool`: **offline/host only** (clients return false, no RPC). Validate team in {0,1}; clamp n to 0..5.
  Spawns (`_spawn_bot` at the team's next spawn slot, roster as in _start_match) or despawns (`Net.despawn`, newest first) bots live.
  Online the host's spawn/despawn replicate through the existing broadcast_spawn / hero_despawned path. Emits `bot_counts_changed`.
  Host also sends `@rpc("authority", "call_remote", "reliable") _bot_counts(counts: Dictionary)` (host -> all clients) so clients update `match_bot_counts()` and emit the signal.
- `func request_hero_change(hero_id: String) -> bool`: offline/host: validate and start the swap locally. Client: `Net` sends
  `@rpc("any_peer", "call_remote", "reliable") _rq_hero(hero_id: String)` (client -> host, rpc_id 1); returns true once sent.
  Host validation: sender = `multiplayer.get_remote_sender_id()` owns a hero; `hero_id in GameConfig.hero_ids()`; differs from current hero;
  no swap already pending for that hero; match not ended. On reject: `hero_swap_cancelled(net_id, reason)` sent back to that client
  (`_swap_cancelled(net_id, reason)`, host -> client rpc_id). On accept: host starts the HERO_SWAP_DELAY timer, broadcasts
  `@rpc("authority", "call_local", "reliable") _swap_started(net_id: int, hero_id: String, delay: float)` -> emits `hero_swap_started`
  on every peer. When the timer ends the host despawns the old hero and spawns the new one (same net owner, team, stats/score kept) at the
  team spawn (`SpawnPicker.pick_for`) with full HP, then `_swap_finished(net_id, hero_id)` -> `hero_swap_finished`. Dying during the
  delay keeps the swap pending (the respawn uses the new hero). Offline: GameConfig.set_hero(hero_id) is also called so "Play again" keeps it.
- `func request_team_change(team: int) -> bool`: same transport: `_rq_team(team: int)` client -> host. Host validates team in {0,1},
  differs from the current team, and humans on the target team <= humans on the other team (no stacking). On accept: move one bot from
  the target team to the old team (keeps counts), respawn the requester on the new team after HERO_SWAP_DELAY (same signals as the hero swap,
  with the current hero_id), then emit `team_changed(net_id, team)` on all peers (`_team_changed` host -> all, call_local).
  Rejects use `hero_swap_cancelled(net_id, reason)`.

Signals on main.gd (UI connects these):
- `signal hero_swap_started(net_id: int, hero_id: String, delay: float)`
- `signal hero_swap_finished(net_id: int, hero_id: String)`
- `signal hero_swap_cancelled(net_id: int, reason: String)`: short reason shown to the player (e.g. "match ended")
- `signal bot_counts_changed(counts: Dictionary)`
- `signal team_changed(net_id: int, team: int)`
Docs: please add these to INTERFACES (§8/§10) when implemented.

## Bot difficulty hook spec (UI: Map select picker + Esc Match page; adapter src/ui/difficulty_control.gd)
Exists today and used: `GameConfig.bot_difficulty` (one level for all bots; main.gd passes it to every
`BotBrain.new({"difficulty": ...})`) and per-brain `BotBrain.set_difficulty(level)`. UI drives the global value from the
Enemy team row; the Your team row shows "Not available yet" until the per-team hook exists. Levels: "easy" | "normal" | "hard".
Owner: core (GameConfig, main.gd, Net); ai already has what is needed.

Pre-match (GameConfig, §8):
- `var team_difficulty := {0: "normal", 1: "normal"}` and `func set_team_difficulty(team: int, level: String) -> bool`:
  validates team in {0,1} and level in DIFFICULTY (false otherwise, no change); emits `changed`. Keep `bot_difficulty` as the
  team-1 alias for CLI (`--difficulty=`), and add `--ally_difficulty=` for team 0 if wanted.
- `func difficulty_for(team: int) -> Dictionary` (damage_scale etc.). main.gd uses `team_difficulty[team]` for each bot's
  BotBrain and `difficulty_for(team)` for its damage scale, including bots spawned by `set_bot_count` and team-change swaps.

Live (composition root main.gd; host/offline only, like `set_bot_count`):
- `func match_bot_difficulty() -> Dictionary`: `{0: level, 1: level}` on every side (clients: last value from the host).
- `func set_bot_difficulty(team: int, level: String) -> bool`: clients return false (no client RPC; UI disables the
  control). Validates as above; sets `GameConfig.team_difficulty[team]`, calls `BotBrain.set_difficulty(level)` on every live bot
  of that team and applies the damage scale to them; emits `bot_difficulty_changed(team, level)`.
- `signal bot_difficulty_changed(team: int, level: String)` on main.gd (every peer).
- Replication: host -> all `@rpc("authority", "call_remote", "reliable") Net._bot_difficulty(team: int, level: String)` ->
  `world.net_bot_difficulty(team, level)` (updates the client copy, emits the signal). Welcome info carries `bot_difficulty`
  (`{0: level, 1: level}`) for late joiners.
- Please add to INTERFACES §8.1 / §10 when implemented. No UI change needed: the page enables itself once `set_bot_difficulty` exists.

## LibreQuake audio (hero ability sounds + team cues; src/ui/hero_sfx.gd, src/ui/audio/)
1. **Asset location.** The 29 LibreQuake WAVs live in `src/ui/audio/lq/<original lq1/sound path>` with
   `src/ui/audio/LICENSES.md`, because TEAM.md gives UI no `assets/` path. If you want a shared `assets/audio/`,
   move the folder as is (files are byte-identical; only `HeroSfx.BASE` changes).
2. **Ship the licence notice (BSD-3 clause 2, binary redistribution).** The release zip holds only Arena.exe and
   Arena.pck, and `export_presets.cfg` has include_filter `*.json`, so LICENSES.md isn't shipped. Please add one of:
   (a) build.sh zip step: also write `src/ui/audio/LICENSES.md` as `Arena/LICENSES-audio.md` (and copy it next to
   dist/linux/arena.x86_64), or (b) add `src/ui/audio/LICENSES.md` to both presets' include_filter. (a) is visible
   to players.
3. **Optional: a shot event.** Primary-fire sounds detect a shot UI-side from the local player's `weapon.ammo`
   dropping (no event exists). If core adds `Events.shot_fired(hero)` (or includes the primary in `ability_used`
   with slot "primary"), HeroSfx will switch to it. Only the local player's own casts and shots play for now
   (non-positional); hearing other heroes' abilities positionally would need hero-side players and is out of scope.

## Online rematch hook (match-end screen; adapter src/ui/rematch_control.gd)
Today the match-end "Play again" → `_restart(true)`, which closes Net when online, so a host can't rematch with the
same players. UI shows: offline "Play again"; online host "Rematch" (disabled until this hook exists, with a note) +
"Main menu"; online client "Leave" (→ `main_menu` → `_restart(false)`). Requested (core: main.gd + Net):
- `func rematch() -> void` on the composition root (main.gd), host only: tells every client
  (`@rpc("authority", "call_remote", "reliable") Net._rematch()`), then reloads the match with the same session,
  map, mode, heroes and bot settings (no `Net.close()`); clients reload into the same session and re-join.
  The UI enables "Rematch" as soon as `rematch()` exists on main.gd (no UI change needed).
- Optional: `Events.rematch_started` (or a Net signal) so the client end screen can say "Starting rematch...".
Please add to INTERFACES §9/§10 when implemented.

## Match mode on every peer (overhead team colours; src/ui/team_palette.gd)
Overhead bars colour heroes self / ally / enemy from the authoritative `hero.team` (replicated in `Net.hero_info`;
team changes and hero swaps re-spawn the node, so that's covered). In FFA everyone but the local player is an enemy,
so the UI needs the match mode on clients too, where no MatchRules exists. Today the UI falls back to "control
when the client built the map's CaptureZone nodes, else ffa" (matches INTERFACES §9). Requested (core: main.gd):
- `func match_mode() -> String` on the composition root, every side ("ffa" | "control"; host/offline:
  `rules.mode`; client: from the welcome info, e.g. `info.mode`). The UI uses it as soon as it exists.
Please add to INTERFACES §8.1/§9 when implemented.
