# Requests from the nidjo branch (Niđo hero)

Niđo was added with new files only, plus roster registration (`src/abilities/registry.gd`: types `pull`, `rollback`;
`tests/core_test_roster.gd` expected ids/names; `docs/ROSTER.md` entry).

1. **INTERFACES §2.2 (lead): new ability types.**
   - `pull` (`src/abilities/pull.gd`): `{radius, pull_speed, up_speed, stop_distance, slow, slow_duration, color}`. Every enemy
     within `radius` gets `knockback()` toward the caster (speed `min(pull_speed, (dist - stop_distance) * 4)`, plus a small
     hop) and `apply_slow(slow, slow_duration)`. No damage. Knockback-immune targets are slowed but not moved. Query: `last_pulled`.
   - `rollback` (`src/abilities/rollback.gd`, use with `needs_ult`): `{radius, window, sample, damage_reduction, dr_duration, color}`.
     Every `sample` s it records the HP of living heroes on its team. On cast, the caster and allies in `radius` are healed up to
     the HP they had `window` s ago (heal only; a death clears the history, so it never revives). Then for `dr_duration` s the
     caster gets back `damage_reduction` of every HP drop on the next tick (via `heal()`).
2. **Damage reduction hook (heroes owner, hero.gd).** Rollback's damage reduction is a next-tick refund because hero.gd has no
   incoming-damage multiplier, so it can't stop a single lethal hit. A `damage_taken_mult` (or `apply_armor(mult, dur)`) applied
   in `take_damage` would make it exact. `rollback.gd` would then call it instead of refunding.
3. **Bot ability policy (ai owner).** `BotBrain.want_ability` is type-based. Suggest: `pull` → enemy within `radius` and
   at least 3 m away (the melee hero wants them close). `rollback` → like `rally`, used when the caster or allies in `radius` lost
   a lot of HP recently. Today bot Niđos only use Firewall (`shield_wall`) on their own; the smoke run forces each slot once.
4. **Optional, hero FX (heroes owner, `src/heroes/fx/hero_fx.gd`).** Niđo has no per-hero swing or cast FX yet. The defaults are
   the `melee_swing` ring and the `Fx.ring` on pull and rollback.
5. **DESIGN.md (lead):** add Niđo to the roster table:
   brawler, 300 HP | Ping Hammer melee 30 ×[1, 1, 1.4], 1.6/s, 3 m, 3rd hit knockback 5 | Firewall (3.4 m wall, 3.5 s, 10 s CD) |
   Stand-up Meeting (8 m pull + 60% slow 2 s, 9 s CD) | Rollback (10 m, 4 s window, 35% DR 4 s, 600 ult).
