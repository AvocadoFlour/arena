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
Niđo's Rollback now uses it (no next-tick refund). Please document it in INTERFACES. Not replicated (HP is); if the
HUD wants a DR indicator on clients, net.gd would need to send `damage_taken_mult()` (core).

## Oct 19: burst fire built into hero.gd (tomo.md #1 done) - for the lead (INTERFACES §2.1)
`primary.burst` (> 1 rounds per burst) and `primary.burst_delay` (s between bursts; `fire_rate` = rate inside a burst).
`Hero._build` creates a `BurstWeapon` for it; `_physics_process` calls `BurstWeapon.continue_burst(self)` each auth tick
before the fire input, so a started burst completes. Hotfix (blink.gd) no longer installs/drives it. Please document.

## Oct 19: real root hook (tomo.md #6 done) - for the lead (INTERFACES) and core net
`Hero.apply_root(dur)`, `Hero.rooted()`, `Hero.root_left`; `Hero.ROOT_BLOCKS = ["dash", "blink", "leap", "charge"]`.
While rooted (host/offline): no walking, no jumping, horizontal velocity zeroed (knockback/pull can't move it), no upward
launch, a running dash/leap is cancelled, movement abilities in ROOT_BLOCKS can't be cast (no cooldown spent); aiming,
shooting and other abilities work. Distinct from slows (slow_mult stays 1). Projectile defs take `"root": seconds`
(projectile_shot.gd). Breakpoint now uses `"root": 1.1` instead of `slow {mult 0}`. Cleared on death.
**Core (net.gd):** root_left (like slow_mult today) is not in the snapshot, so a client-predicted own hero keeps walking
locally and gets corrected by the host. Please replicate `root_left` (and ideally `slow_mult`) for `_predict_step`.
**AI:** bots may still try movement abilities while rooted (harmless: _use() refuses).

## Oct 13: Übel (id `ubel`, user-approved fan character) - roster, core, AI, docs
1. **docs/ROSTER.md (lead):** please add Übel with exactly this line:
   'Fan character based on Übel (Frieren). Fine for private play; must be replaced with an original design before any commercial release.'
   (Also in src/heroes/ubel/README.md.)
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
5. **AI (bot_brain.want_ability):** `ride` and `line_slash` are unknown types today, so bots never use Übel's Shift/E.
   Suggested: `ride` like `leap` (aimed, visible enemy within 10 m), `line_slash` like `charge` but dist < 6; while
   mounted (`h.mounted_on() != null`) keep swinging and don't jump.

## Oct 19: 0.9.3 smoke FAIL arena01/ubel (ability1 = 0) - REQUEST core (src/main.gd smoke forcing), exact diff below
Root cause: the smoke forces each unused slot exactly ONCE (at 60% of the run) and marks it "forced" whether or not
it fired. Übel's Uninvited Guest is target-gated by design: ride.can_activate() needs an enemy within 10 m (head),
inside the 30° aim cone, with line of sight; without one nothing happens, no cooldown is spent and no
Events.ability_used fires (correct: a ride with no target is not a use). The autopilot (BotBrain) never casts the
ride type, so the single forced press is the only chance. On master a0a9613 the run is deterministic and at that
instant the nearest enemy is 13.9 m away (4.4° off the crosshair, clear line), on arena01 and arena02 alike, so
ability1 stays 0 -> SMOKE FAIL on both maps (arena02/ubel fails too; the build stops at the first failure).
dc183c9 passed only because positions at that instant differed before the 0.9.3 AI changes.
Fix (smoke only, no gameplay change): keep retrying an unused slot every frame until it fires. Verified locally on
a0a9613 with this diff: arena01/ubel and arena02/ubel SMOKE PASS (ability1 = 1).
```diff
diff --git a/src/main.gd b/src/main.gd
index be2892a..03172fc 100644
--- a/src/main.gd
+++ b/src/main.gd
@@ -269,12 +269,13 @@ func _process(dt: float) -> void:
     if args.has("smoke") and el >= float(args.smoke) * 0.6 and not player.dead:
         # autopilot policy (src/ai) may skip situational abilities: exercise each unused slot once (retries while dead)
         for slot in ["ability1", "ability2", "ultimate"]:
-            if stats.get(slot, 0) == 0 and player.abilities.has(slot) and not stats.get("forced", []).has(slot):
+            if stats.get(slot, 0) == 0 and player.abilities.has(slot):   # retry until it fires (target-gated: ride)
                 player.abilities[slot].cooldown.remaining = 0.0
                 if slot == "ultimate":
                     player.ult.add(player.ult.cost)
                 player._use(slot)
-                stats["forced"] = stats.get("forced", []) + [slot]
+                if not stats.get("forced", []).has(slot):
+                    stats["forced"] = stats.get("forced", []) + [slot]
     if args.has("smoke") and el >= float(args.smoke):
         _finish()
     if args.has("demo") and args.demo != "1" and el >= float(args.demo):
```
**AI (optional, longer term):** let BotBrain cast `ride` (enemy within `range` in the aim cone) so the smoke would
not need to force it at all.
## Oct 19: Twin Tails healing kit changes (user request) - FYI core/UI/AI
- **Left click** `primary.ally_heal: 7` (hitscan): a hit on a living ally (not self) heals 7 (~49 HP/s at 7 shots/s,
  capped at max HP) instead of damaging; enemy damage stays 11.
- **Encore Beam** (`heal_beam`): duration 4 s, hps 60 (240 total); pressing ability1 again cancels; the cooldown (8 s)
  starts when the beam ends/cancels; `exclusive: true` = while it runs she can't fire, use E or Q (walk/aim allowed,
  `Hero.channel_lock()`); it now also targets enemies and damages every enemy whose body is within `width`/2 (0.5 m)
  of the beam at `enemy_dps: 30`. Colour is data (`color_heal` blue / `color_damage` red), switches live.
  Net: no core change. While channelling the snapshot cooldown `remaining` is `duration + left` (clients detect the
  channel with `remaining > duration`), and the target comes from the existing `heal_target` snapshot field; the owner
  predicts the target locally so the colour has no lag.
- **Staccato Note** `ability2.ally_heal: 19`: the note flies through allies; each ally it passes or catches in the 2 m
  splash is healed 19 once per note, never slowed, not self. Enemy damage 30 + slow unchanged.
- All heals are host-only via `Hero.heal` -> `Events.healed` (already in Net.EVENT_SIGNALS) -> MatchStats Top healing.
- **AI (optional, AI owner):** bots never aim at allies, so bot TT won't use the left-click or note heals; bot support logic
  that reads `ab.channeling`/`ab.target` should expect the beam target can now be an enemy and that the beam can be
  cancelled by pressing ability1 again (a bot re-pressing it each tick would toggle it off).
- **UI (optional):** the HUD cooldown for the beam shows `remaining` = duration + cooldown while channelling.
