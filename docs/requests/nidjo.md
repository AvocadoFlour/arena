# Requests from the nidjo branch (Niđo hero)

Niđo was added with new files only, plus roster registration (`src/abilities/registry.gd`: types `pull`, `rollback`;
`tests/core_test_roster.gd` expected ids/names; `docs/ROSTER.md` entry).

1. **INTERFACES §2.2. DONE 2026-10-23.** `pull` and `rollback` are documented there. The live rollback uses `apply_damage_reduction`, not a next-tick refund.
2. **Damage reduction hook. DONE on master.** `Hero.apply_damage_reduction` / `damage_taken_mult()` run inside `take_damage` before overheal and HP. Not in the snapshot.
3. **Bot ability policy (ai owner). DONE on master 2026-10-23.** `pull` when a visible enemy is at least 3 m away and inside the def `radius` (`pull_range`, Niđo 8 m). `rollback` when the caster is hurt or an ally in range is hurt. Firewall was already `shield_wall`.
4. **Optional, hero FX (heroes owner, `src/heroes/fx/hero_fx.gd`).** Niđo has no per-hero swing or cast FX yet. The defaults are
   the `melee_swing` ring and the `Fx.ring` on pull and rollback.
5. **DESIGN.md (lead). DONE 2026-10-23.** Niđo is in the v0.9 roster table.
