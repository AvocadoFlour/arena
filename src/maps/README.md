# maps — owner: maps bot
JSON maps + `map_loader.gd` (boxes, ramps, lighting, spawns, theme/materials/props). Contract: INTERFACES.md §6.

`spawn_rooms.gd` (`SpawnRooms`, map child "SpawnRooms"): protected spawns — host push-out keep-out volumes from
`spawn_rooms[].barriers` / `spawn_areas`, spawn-shield hook (`is_shielded`), toon team-colour barrier panels. See docs/requests/maps.md.

Readability tools: `tests/maps_snag_scan.gd` (capsule snag/stuck scan) and `tests/maps_sight_scan.gd` (sightlines, door camping,
narrow passages, cover usefulness); suites `maps_snag_sim.gd`, `maps_sight_sim.gd`, `maps_read_test.gd`.

`map_bounds.gd` (`MapBounds`, map child "Bounds"): out-of-bounds + fall recovery from map JSON `out_of_bounds` (playable
box = outer-wall faces, kill plane, ceiling, kill/recover volumes). Host position checks each physics tick, no bodies,
no visuals. Recover = teleport to the nearest MapGrid safe point + small "fall" damage; kill credited to the last enemy
within `credit_window` s. Tests: `tests/maps_oob_test.gd` (unit), `tests/maps_oob_sim.gd` (Jolt: pads + Force Push).
