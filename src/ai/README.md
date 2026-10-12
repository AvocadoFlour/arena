# ai — owner: AI bot
`bot_brain.gd`: input source producing InputFrames. States wander/chase/cover, navmesh path
following, difficulty presets (`difficulty`: easy/normal/hard → spread, turn rate, aim jitter,
reaction time, ability delay, cover threshold), ability policy `decide_abilities()` (dash/slam/ult).
`bot_nav.gd`: lazily bakes a NavigationRegion3D from the map's static colliders (no map-loader
change), path queries, cover-point selection. Tests: tests/ai_*. Contract: INTERFACES.md §1, §5.
