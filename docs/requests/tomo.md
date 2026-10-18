# Requests from the tomo branch (Tomo hero)

Tomo was added with new files only, plus roster registration (`src/abilities/registry.gd`: types `blink`,
`shockwave`; `tests/core_test_roster.gd` expected ids/names; `docs/ROSTER.md` entry). These shared changes are
needed for a clean, fully supported kit:

1. **Burst primary in hero.gd (heroes owner) + INTERFACES §2.1 (lead).** Packet Burst uses
   `src/heroes/burst_weapon.gd` (`BurstWeapon extends Weapon`; keys `primary.burst`, `primary.burst_delay`;
   `fire_rate` = rate inside a burst). Today the Hotfix ability (`blink.gd`) installs it in `_init`
   (`BurstWeapon.install(hero)`) and completes started bursts in its `tick` (`BurstWeapon.continue_burst(hero)`).
   Request: in `Hero._build` create `BurstWeapon` when `primary.burst` exists, and call `continue_burst` once per
   auth tick in `_physics_process` (before `_try_fire`). Then the two lines move out of `blink.gd`. Please document
   `burst` / `burst_delay` in §2.1.
2. **Bot ability policy (ai owner).** `BotBrain.want_ability` is type-based and doesn't know the new types, so
   bot Tomos never use Hotfix or Force Push (the smoke run still forces each slot once). Suggest:
   `blink` → same rule as `dash`; `shockwave` → like `nova`, but only with an enemy in front (`aim_ok`) within
   `radius` (9 m). Breakpoint is a plain `projectile` and already works.
3. **INTERFACES §2.2 (lead): new ability types.**
   - `blink` (extends dash): `{distance, duration, bonus_mult, bonus_shots, bonus_window, color}`. Momentum is
     capped to run speed when the dash ends. Leaves a host-side afterimage plus a replayed `Fx.ring`. Query:
     `bonus_pending()`.
   - `shockwave` (extends nova, needs a full meter): `{radius, arc_deg, damage, knockback, lift, color}`, a frontal
     cone with HitMath falloff, knockback away from the caster, and damage to `destructible` cover in the cone.
     Damage kind is `ultimate`.
   - Role `duelist` is used again (Tomo). UI may want the label.
4. **Optional, hero FX (heroes owner, `src/heroes/fx/hero_fx.gd`).** Tomo has no per-hero shot or cast FX case yet,
   so he uses the default tracer. A red "data packet" tracer and a Hotfix afterimage visible on clients would need
   entries there. The afterimage mesh is host/offline only; clients see the ring.
5. **DESIGN.md (lead):** add Tomo to the roster table:
   duelist | Packet Burst 3×15, 14/s in a burst, 0.36 s between bursts, 24 mag | Hotfix | Breakpoint | Force Push.
6. **Note: Breakpoint root.** A root is `apply_slow(0.0, 1.1)`. It stops walking, but jumps and dash-type
   abilities still move a rooted hero. A real root/stun state would need a hero.gd hook.
