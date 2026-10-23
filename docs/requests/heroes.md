# Requests from heroes

## Status for Grokbot (2026-10-23, branch master, on top of 78d2d49 / v0.9.4)
`master` is the default branch. Do not redo a line marked done.
- `00ad722` (build passed, 735 tests, smoke and network test, version left at 0.9.4): documented burst, root, damage reduction, blink, shockwave, pull, rollback, ride, line_slash. Übel roster line. Snapshot fields 19–20 are `root_left` and `slow_mult`.
- Bot policies for `blink`, `shockwave`, `pull`, `rollback`, `ride`, and `line_slash` are in `BotBrain.want_ability`. While mounted, bots do not jump. Tests: `tests/ai_unit_tests.gd::test_tomo_nidjo_ubel_ability_policy`. Ranges come from the hero def.

Still open. Older sections below are history, not a fresh queue. `ui`, `maps`, `tomo` and `nidjo` are already merged.
1. **Optional, net:** a snapshot field for the ride (rider, victim, time left) instead of the `mount:<rider>:<victim>` prop. Hop-off on the client still waits for the host.
2. **Not done:** `damage_taken_mult()` is not in the snapshot. Only add it if the HUD needs a damage-reduction indicator on clients. Nothing in `src/ui` reads it today.
3. **Parked, do not merge:** `heroes-melee-wip` (`on_hit_speed` is not on `master`), `heroes-tt-wip`, `ai-tuning-wip`.
4. **Optional FX, not started:** Tomo and Niđo have no per-hero cases in `src/heroes/fx/hero_fx.gd` (tomo.md #4, nidjo.md #4).

## Round 6 (open, optional; nothing blocks heroes)
The Encore Beam ribbon is driven from replicated state only:
- **Channel active:** derived from the replicated ability1 cooldown (`duration - remaining < channel duration`).
- **Target:** clients re-run `heal_beam.pick_target()` on replicated positions, yaw, pitch, team and dead.

The healed target itself is NOT replicated. Because remote heroes are interpolated 0.1 s behind, the client's
pick can differ from the host's when two allies sit at the cone edge.
1. **Optional:** add `beam_target` (net_id or -1) to the hero snapshot, e.g. `abilities.ability1.target`, for the
   exact target. A cheaper alternative is to replicate the host's `heal_beam.target` via a reliable
   `Events.ability_target(hero, slot, target)`. If added, heroes switches `visual_process` to prefer it (one line).
2. **Removed the per-tick `Fx.tracer` from heal_beam.** It sent ~60 unreliable `_s_fx` RPCs/s per healer and was
   invisible. No core change needed.

## Round 5 (open, non-heroes)
1. **AI test flake (ai owner):** `ai_melee_driver::ranged_keeps_standoff` failed once in ./build.sh (min gap 7.24 m < 8.0)
   and passed on the next 3 runs. It runs unseeded by default (`run_seed := -1`); suggest seeding it in the gate.

## Round 4 (resolved in v0.5: combo_step + dash_time replicated)
Attack visuals are now driven only by replicated snapshot fields: a drop in `weapon.ammo` = shot or swing
(melee also spends 1 of 999 per swing). That drives sword swing, gun recoil, and the side alternation
(from shot-count parity). `reloading` drives the weapon dip, and a jump in ability `cds` drives the cast
flourish. Not replicated, so not used for visuals:
1. **`combo_step`** (melee): needed for a distinct finisher (3rd-hit) animation on remote heroes. Suggest adding
   `combo_step` (int) to the hero snapshot (`net.gd` `_hero_state` / `_apply_state`, field 16).
2. **`dash_time`**: the dash/leap lean uses it. Remote heroes still lean from interpolated velocity, so this is low priority.
3. Note: if a hero ever fires > 1 shot per snapshot (20 Hz), it shows as one swing/kick (the side parity
   stays correct). Fine for all current heroes (max 7 shots/s).

## Round 3 (open)
1. **Smoke flake (core, main.gd / build.sh):** smoke requires `kills > 0` within 35 s. On arena02 this randomly
   fails with 0 kills, for cob and twin_tails. It reproduces on unmodified master (1 of 3 runs of
   `--smoke=35 --force_end=32 --hero=cob --map=arena02` failed with kills 0). Suggest a fixed RNG seed
   in smoke mode, or a longer window / pass on damage + ability usage.
2. **INTERFACES.md §2 model (visual-only, optional keys):** `rot` (deg), `scale`, `pivot`, `metallic`, `roughness`,
   `emission`, `anim` ∈ tail|weapon|leg_l|leg_r|arm_l|arm_r|head. Parts live under a `Visual` child node animated in
   `_process` from existing state (velocity, is_on_floor, weapon cooldown, combo_step, dash_time); no synced state.

## Round 2 (open)

1. **Archive move blocked by core/ui/ai references (needs owners' changes).** Archive copies already exist at
   `src/heroes/archive/{kestrel,rampart,willow}.json` (subfolder, not scanned by `GameConfig.hero_ids()` /
   `UiCatalog`). The top-level originals are still in place, because removing them breaks code outside heroes:
   - `src/core/game_config.gd:15` default `hero_id := "kestrel"`: change it to e.g. `"twin_tails"`.
   - `tests/ui_test.gd:9` asserts `kestrel` is listed: assert a current hero instead.
   - `tests/core_control_sim.gd:31`, `tests/core_nav_maps_sim.gd:42,80` (kestrel, rampart) and
     `tests/ai_nav_driver.gd:4` (kestrel): point them at current heroes or `src/heroes/archive/…`.
   - `tools/capture_v02.sh` uses `--hero=rampart/willow/kestrel`.
   When these have landed, heroes deletes the three top-level files (one commit; tests already use archive paths).
2. **INTERFACES.md §2: melee primary.** Implemented entirely in heroes (hero.gd `_try_fire` branches on
   `primary.type`; core `Weapon` still handles rate/mag and ignores extra keys). Please document:
   `"primary": {"type":"melee","damage","fire_rate","mag","reload_time","range","arc_deg","combo":[mult…],
   "combo_window","finisher_knockback"}`. Hits are frontal arc (`MeleeMath.in_arc`), damage kind `primary`, final
   combo hit knocks back. Bots/HUD: melee range is `primary.range` (bot AI may want to close distance; ammo is 999).
3. **INTERFACES.md §2.2/§3: new hero API & ability options.**
   `damage_mult()` (= damage_scale × buff; all hero/ability damage uses it), `apply_buff(mult, dur, kb_immune)`,
   `knockback(v)` (ignored while `knockback_immune`), `add_overheal(amount, dur)` + `overheal` (absorbed before HP
   inside `take_damage`; the returned/applied amount includes absorbed overheal; HUD may show `overheal`),
   `clear_buffs()` on death. Ability def option `"needs_ult": true` (any type becomes an ultimate; consumes meter).
   New types: `leap` (query `leaping()`), `team_buff`. `ground_slam` now only impacts on landing after its own dive.
   Optional `color` param on heal_beam / ground_slam.
4. Still open from round 1: optional `"primary": {"type":"projectile"}` (not implemented).
5. Role string `"brawler"` is new (The Best); UI may want a label/icon.

## Round 1 (resolved in master 13df7ab/bbd8445)
Test auto-discovery, hero API docs, damage kinds, mixed bot roster.

## R7 (Twin Tails 3D model)
- DONE (core a36e935+): death now uses `hero.keep_body_when_dead`; the corpse copy was removed.
- Optional: the import step needs `godot --headless --import` after the GLB changes. If build.sh does not already reimport, consider adding that so fresh checkouts never show a stale model.
- Info: `--primitive_models` user arg / `Hero.use_primitive_models` keeps the old primitive look (fallback, tests).

## R8 (The Best + Cob 3D)
- No blocking requests.
- Info: Cob's model (legs ~1.95 m wide at scale 0.85) is wider than its 1.3 m capsule and sits low; the core third-person camera frames it from very close (shell fills the lower screen). If core ever adds a per-hero camera offset/distance, Cob would benefit (e.g. +0.6 m back, +0.3 m up).
- Info: engine quirk (4.7.2): freeing a MeshInstance3D with per-surface override materials while another instance of the same mesh is alive logs `Parameter "material" is null`. ToonKit now bakes the toon materials into a shared mesh copy instead (no overrides), which avoids it.

## R9 – ability VFX (requests to core)
- **Net-prop visual hook:** on clients, projectiles and walls are recreated by core as plain sphere/box props. That means the Staccato Note glyph shows only on host/offline (hits still pop via the replayed damage event), and the Geode Wall box hides most of the toon crystals. Request: an optional `visual_scene`/`visual_id` field in net_props so hero code can supply the client-side visual.
- **Test helper naming:** `abilities_sim::projectile_freed` treats any scene child that has a `vel` property as a projectile. The FX pieces now use `drift` to avoid this, but a group- or class-based check would be sturdier.

## R10 – hit reactions (notes / requests)
- The toon shader now has a per-instance `instance uniform float hit_flash`, which keeps meshes shared. GL Compatibility allows only a limited number of instance uniforms per material; this uses one.
- `HeroModel` now keeps loaded model PackedScenes referenced. Previously a scene could unload between spawns, so the ToonKit bake was redone each time and its cache grew (found by the new sharing test).
- Request (core): replicate a hit direction (attacker position or hit pos) in the hp snapshot, or always replay damage events to all clients. Then remote flinches could always be directional. Today a hit without a damage event gets a generic backward flinch.
- FYI (not heroes): `ai_teamplay_driver::team_groups_up` fails on current master without this branch's changes too.

## Queue notes (Oct 13)
- PAUSED (not cancelled): Cob shell polish; Twin Tails face/wing polish.
- Tomo and Niđo: concept step 1 only (docs/concept/tomo_v1.png, nidjo_v1.png, tomo_nidjo_proposal.md). No 3D, nothing in-game yet.

## FYI (Oct 19): ability descriptions API (no core change needed)
`HeroAbilities.describe(hero_id, slot)` / `describe_all(hero_id)` in src/heroes/hero_abilities.gd (global class_name, pure JSON data).
UI can call it directly; nothing to wire in core. See src/heroes/README.md.

## Oct 19: damage-reduction hook (hero.gd) - for the lead (INTERFACES §1/§3)
`Hero.apply_damage_reduction(frac, dur, key := "default")`, `Hero.damage_taken_mult()`, `Hero.damage_reduction_left(key)`,
`Hero.damage_reductions` (key -> [frac, secs]). Applied in `take_damage` BEFORE overheal and HP (host/offline only), so it
can stop a one-shot; keys stack multiplicatively, same key refreshes (max frac / max time); cleared by `clear_buffs()`.
Niđo's Rollback now uses it (no next-tick refund). Documented in INTERFACES 2026-10-23. Not replicated (HP is); if the
HUD wants a DR indicator on clients, net.gd would need to send `damage_taken_mult()` (core).

## Oct 19: burst fire built into hero.gd (tomo.md #1 done) - DOCUMENTED 2026-10-23 on master
`primary.burst` (> 1 rounds per burst) and `primary.burst_delay` (s between bursts; `fire_rate` = rate inside a burst).
`Hero._build` creates a `BurstWeapon` for it; `_physics_process` calls `BurstWeapon.continue_burst(self)` each auth tick
before the fire input, so a started burst completes. Hotfix (blink.gd) no longer installs/drives it. Please document.

## Oct 19: real root hook (tomo.md #6 done) - DOCUMENTED, and root_left/slow_mult replicated 2026-10-23
`Hero.apply_root(dur)`, `Hero.rooted()`, `Hero.root_left`; `Hero.ROOT_BLOCKS = ["dash", "blink", "leap", "charge"]`.
While rooted (host/offline): no walking, no jumping, horizontal velocity zeroed (knockback/pull can't move it), no upward
launch, a running dash/leap is cancelled, movement abilities in ROOT_BLOCKS can't be cast (no cooldown spent); aiming,
shooting and other abilities work. Distinct from slows (slow_mult stays 1). Projectile defs take `"root": seconds`
(projectile_shot.gd). Breakpoint now uses `"root": 1.1` instead of `slow {mult 0}`. Cleared on death.
**Core (net.gd):** DONE. `root_left` and `slow_mult` are snapshot fields 19 and 20. `_predict_step` and reconcile honour a root.
**AI:** bots may still try movement abilities while rooted (harmless: _use() refuses).

## Oct 13: Übel (id `ubel`, user-approved fan character) - roster line and INTERFACES done 2026-10-23
1. **docs/ROSTER.md:** done. The entry includes exactly: 'Fan character based on Übel (Frieren). Fine for private play; must be replaced with an original design before any commercial release.'
2. **tests/core_test_roster.gd (core-owned):** edited in this branch the same way tomo 4c4aee1 / nidjo f5b6f50 did
   (adds "ubel" / "Übel" to the expected roster), because adding src/heroes/ubel.json otherwise fails the build.
   Please keep or redo it on master as you prefer.
3. **New ability types (INTERFACES §2.2):** `ride` (src/abilities/ride.gd) and `line_slash` (src/abilities/line_slash.gd).
   New Hero API: `mounted_on()`, `cancel_ride(why)` (stuns / hard CC should call it; knockback and root already end a
   ride), `ridden_by` (host), `_ride`. HeroModel drive key `riding` -> "ride" pose.
4. **Net (core, optional improvement):** the ride replicates without core changes through a net prop
   (`net_kind "mount:<rider>:<victim>"`, `net_visual` res://src/abilities/mount_link.gd). A proper snapshot field
   (rider -> victim id + ride time left) would remove the dependency on the reliable prop spawn order and let the
   client predict the hop-off on jump (today the hop-off waits for the host). Also: while mounted the client-predicted
   rider sits on the *interpolated* victim, so reconcile counts rise during rides (harmless, the predicted step re-seats).
5. **AI (bot_brain.want_ability). DONE on master 2026-10-23.** `ride`: aimed, on the ground, visible enemy inside the def `range`, never while mounted. `line_slash`: aimed visible enemy inside the def `length` (6 m). Mounted bots do not jump, so a ride is not ended by the stuck-jump.
