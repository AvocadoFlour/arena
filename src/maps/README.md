# maps — owner: maps bot
JSON maps + `map_loader.gd` (boxes, ramps, lighting, spawns, theme/materials/props). Contract: INTERFACES.md §6.

`spawn_rooms.gd` (`SpawnRooms`, map child "SpawnRooms"): protected spawns — host push-out keep-out volumes from
`spawn_rooms[].barriers` / `spawn_areas`, spawn-shield hook (`is_shielded`), toon team-colour barrier panels. See docs/requests/maps.md.

Readability tools: `tests/maps_snag_scan.gd` (capsule snag/stuck scan) and `tests/maps_sight_scan.gd` (sightlines, door camping,
narrow passages, cover usefulness); suites `maps_snag_sim.gd`, `maps_sight_sim.gd`, `maps_read_test.gd`.
