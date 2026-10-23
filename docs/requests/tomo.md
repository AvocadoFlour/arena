# Requests from the tomo branch (Tomo hero)

Tomo was added with new files only, plus roster registration (`src/abilities/registry.gd`: types `blink`,
`shockwave`; `tests/core_test_roster.gd` expected ids/names; `docs/ROSTER.md` entry). These shared changes are
needed for a clean, fully supported kit:

1. **Burst primary in hero.gd + INTERFACES §2.1. DONE on master** (see the Oct 19 note in heroes.md). `Hero._build` creates `BurstWeapon`, and `_physics_process` calls `continue_burst`. Documented.
2. **Bot ability policy (ai owner). DONE on master 2026-10-23.** `blink` uses the dash rule. `shockwave` fires when aimed at a visible enemy inside the def `radius` (`shock_range`, Tomo 9 m). Breakpoint stays a plain `projectile`.
3. **INTERFACES §2.2. DONE 2026-10-23.** `blink` and `shockwave` are documented. Role `duelist` is in the v0.9 DESIGN table.
4. **Optional, hero FX (heroes owner, `src/heroes/fx/hero_fx.gd`).** Tomo has no per-hero shot or cast FX case yet,
   so he uses the default tracer. A red "data packet" tracer and a Hotfix afterimage visible on clients would need
   entries there. The afterimage mesh is host/offline only; clients see the ring.
5. **DESIGN.md (lead). DONE 2026-10-23.** Tomo is in the v0.9 roster table.
6. **Breakpoint root. DONE.** `Hero.apply_root` is the real root. Breakpoint uses `"root": 1.1`. `root_left` is replicated.
