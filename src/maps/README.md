# maps — owner: maps bot
JSON maps + `map_loader.gd` (boxes, ramps, lighting, spawns, theme/materials/props). Contract: INTERFACES.md §6.

`spawn_rooms.gd` (`SpawnRooms`, map child "SpawnRooms"): protected spawns — host push-out keep-out volumes from
`spawn_rooms[].barriers` / `spawn_areas`, spawn-shield hook (`is_shielded`), toon team-colour barrier panels. See docs/requests/maps.md.
