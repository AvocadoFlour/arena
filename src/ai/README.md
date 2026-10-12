# ai — owner: AI bot
`bot_brain.gd`: input source producing InputFrames. States wander (escorts nearest teammate) /
chase / cover / support (heal beam on hurt allies). Navmesh path following, difficulty presets,
type-aware ability policy `decide_abilities()` / `want_ability(type, ctx)`.
`bot_nav.gd`: lazily bakes a NavigationRegion3D from the map's static colliders; `sync_dynamic()`
rebakes with shield walls (world-level StaticBody3D boxes) as projected obstructions; cover detection
by meta `kind` (fallback name prefix). Tests: tests/ai_*. Contract: INTERFACES.md §1, §5.
