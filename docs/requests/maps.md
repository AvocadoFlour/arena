# Requests from maps (round 1)

1. **tests/run_tests.gd** (lead-owned): add `"res://tests/maps_test.gd"` to `SUITES` so map tests run in ./build.sh.
   Until then: `godot --headless --path . -s tests/maps_run.gd`.
2. **INTERFACES.md §6** (additive, optional keys; arena01 unaffected):
   - `"zones": [{"id","kind":"capture","pos":[x,y,z],"size":[x,y,z]}]` → meta `zones` (Array of {id,kind,pos:Vector3,size:Vector3}).
   - `"spawn_rooms": {"<team>": {"pos","size"}}` → meta `spawn_rooms` (Dictionary int → AABB).
   - `SpawnPicker.pick_for(hero, candidates, default_index) -> Vector3` (src/maps/spawn_picker.gd): picks a spawn
     no living enemy has line of sight to (physics ray, layer 1), else fewest watchers / farthest.
   - `MapGrid.from_def(def)` walkability grid + `flood()` (usable for bot nav later).
3. **Respawn hook** (heroes/core): in `Hero.respawn()` (or the spawner in main.gd), use
   `spawn_point = SpawnPicker.pick_for(self, spawns[team])` instead of a fixed point. Not wired yet, so arena01
   gameplay is unchanged. Selecting arena02 in main.gd (`MAP`) is also a core change.
