# Requests from heroes

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
- Optional, not blocking: the live hero is hidden on death by core, so the death animation is played on a client-side corpse copy (HeroModel.spawn_corpse). If core ever adds a "keep body visible while dead" hook, the corpse copy can be dropped.
- Optional: the import step needs `godot --headless --import` after the GLB changes. If build.sh does not already reimport, consider adding that so fresh checkouts never show a stale model.
- Info: `--primitive_models` user arg / `Hero.use_primitive_models` keeps the old primitive look (fallback, tests).
