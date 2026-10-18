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

Round 7 (queue 1): `ui_sfx.gd` (`UiSfx`, owned by the Settings autoload as `Settings.sfx`): hit / kill /
click / ready sounds synthesised at runtime as 16-bit AudioStreamWAV (no audio files, nothing to license),
6-voice pool on the **SFX** bus, per-sound rate limit so rapid fire doesn't stack. Wiring: player
`damage_dealt` (non-lethal) → hit; `killed` with killer = player → kill; every `MenuStyle.button` / toggle
and buttons passed through `MenuStyle.polish` → click; HUD ability panels → ready (edge-detected from
`cooldown.is_ready()` / `ult.is_full()`, plus a scale pulse). Crosshair `flash(kill)`: hit = short white X;
kill = longer, larger, thicker red X with crosshair tint, never downgraded by a following hit.
Tests: `tests/ui_round7_test.gd`.

Queue 2: `score_table.gd` (`ScoreTable`, shared): one panel per team ("Team 1", "Team 2"), rows with a
`HeroBadge` (hero-name initials in a circle filled with the hero's first model colour, ringed in team
colour; no art), player name, K / D / Damage / Healing; player row highlighted; rows >= 52 px.
`Scoreboard` (hold Tab) uses it, refreshing at 4 Hz. `MatchEndScreen` summary: highlight cards
("Most kills", "Top damage", "Top healing"), the same table, and per-team totals.
Healing: no event yet → column shows "-"; `MatchStats` auto-binds `Events.healed({source, target, amount})`
if core adds it. Tests: `tests/ui_round8_test.gd`.

Queue 3: `pause_menu.gd` is now the in-match Esc overlay: Resume / Settings / Leave match (72 px buttons).
Settings reuses MainMenu's Settings, Audio and Controls screens (`MainMenu.options_only`, emits
`options_closed` on Back). Offline it pauses the tree; online (`Net.is_online()`) it never pauses, only
blocks gameplay input (`Actions.gameplay_enabled = false`). Esc goes back one level (Controls/Audio →
Settings → overlay → closed); the rebind screen's Esc-cancel is consumed first. Leave match emits
`leave_requested` (for main.gd) and falls back to the documented `hud.match_end.main_menu` route.
HUD ability-ready cue uses `Events.ability_ready(hero, slot)` when present, else polls cooldowns.
Tests: `tests/ui_round9_test.gd`.

Miku queue 1: kill feed (top-right, `KillFeed`) entries are rows of killer name, ability badge
(`KillFeed.ability_badge`: initials of the ability/weapon label in a HeroBadge-style circle, filled with the
ability's def colour or the killer's hero colour, ringed in the killer's team colour), victim name. Names use
team colours (`HeroBadge.TEAM_COLORS`); the local player's kills/deaths get a neutral white/grey bordered panel
so the highlight never competes with team colours. 5 s lifetime, max 5, newest on top.
Setting **Damage numbers** (`Settings.damage_numbers`, default on, `[hud] damage_numbers` in
user://settings.cfg, toggle on the Settings page): off = HUD spawns no floating numbers (hit marker and sounds stay).
Tests: `tests/ui_round10_test.gd`.

Miku queue 2: `ping_indicator.gd` (`PingIndicator`, top-left under FPS, only while `Net.is_online()`):
"Ping N ms" green < 60 / yellow < 120 / red, "Connection unstable" (orange, pulsing) when no packet for 0.75 s,
"Ping --" grey while Net exposes no RTT. Data via `net_link_info.gd` (`NetLinkInfo`), documented Net API only;
picks up `Net.ping_ms()` / `Net.last_packet_age()` automatically when core adds them.
`connection_lost_screen.gd`: "Host left" / "Connection lost" + reason + 420x96 "Return to menu"; the HUD shows it
on `Net.disconnected(reason)`. Return: `return_requested` → else PauseMenu `leave_requested` (main.gd) → else
`match_end.main_menu`. Tests: `tests/ui_round11_test.gd` (mock Net).

Ability descriptions (1.0): `ability_info.gd` (`AbilityInfo`) is the only source of ability text for UI. It loads the
heroes-owned `HeroAbilities` (src/heroes/hero_abilities.gd) by path when it exists, otherwise builds entries from
the hero JSON (name, type, cooldown, ult cost, primary numbers, "description"). Shown by `ability_list.gd` (hero
select detail, Match page "HeroInfo" pane: hover/focus a hero or tap its "?") and `ability_tooltip.gd` (HUD icons:
hover with a free cursor or touch long-press; observes input only, never blocks). Tests: ui_round16_test.gd (mocked
HeroAbilities via tests/ui_mock_hero_abilities.gd + JSON fallback), ui_ability_tooltip_sim.gd.
