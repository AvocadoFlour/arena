# heroes — owner: heroes bot
`hero.gd` (generic data-driven body) and one JSON per hero. New hero = new JSON (+ new ability
types in src/abilities if needed). Contract: INTERFACES.md §2, §3. Don't edit core.

## Ability descriptions (UI API)
`src/heroes/hero_abilities.gd`, `class_name HeroAbilities` (static, pure data, no spawned hero / scene tree):
- `HeroAbilities.describe(hero_id: String, slot: String) -> Dictionary` -> `{name, slot, type, text, stats}`; `{}` if the hero/slot doesn't exist.
- `HeroAbilities.describe_all(hero_id: String) -> Array` in slot order `primary, ability1, ability2, ultimate, passive` (absent slots skipped; no hero has a passive yet).
- `text`: precise sentences generated from the hero JSON by a per-type template (`TEMPLATES`); `stats`: the def's numeric/bool stats plus derived values (`dps`, `total_heal`, `max_range`, `combo_hits`, `finisher_damage`, `slow_mult`, `slow_duration`, `ult_cost`).
- New ability type: add its stat keys to `TEMPLATES` and a `_text_<type>` branch. Until then it gets a generic "key value" text and `tests/heroes_test_descriptions.gd` fails listing the uncovered keys.
