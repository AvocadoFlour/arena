# Requests from maps

## Round 1 (done in v0.2)
run_tests discovery, INTERFACES §6 optional keys, SpawnPicker respawn hook — all integrated.

## Round 2 — capture zone logic (src/maps/capture_zone.gd)
1. **Core: instantiate zones in main.gd** after `MapLoader.build`:
   `for z in CaptureZone.from_map(map): add_child(z)` (one `CaptureZone` Node per capture zone; it
   ticks itself in `_physics_process`, counting alive heroes of group "heroes" inside its AABB).
   No zones on arena01, so arena01 is unaffected.
2. **Core: Events bus** — add `signal zone_changed(ev)`, `signal zone_captured(ev)`, `signal zone_contested(ev)`
   and forward from each zone (`z.state_changed.connect(Events.zone_changed.emit)`, etc.), so UI only listens.
   Payloads: state `{zone, owner, capturing_team, progress, contested}`; captured `{zone, team, previous}`;
   contested `{zone, contested}`. Teams int, neutral = -1.
3. **INTERFACES §6**: zone keys `capture_time` (s, solo, default 8), `player_scale` (rate multiplier per player
   count, last = cap, default [1,1.5,2]), `decay_rate` (/s when empty, default 0.1), `revert_rate` (default 1).
   `zones` meta entries now also carry these extra keys. Rules: >= 2 teams present = contested, progress pauses;
   a lone team first reverts another team's partial progress; owner standing on its zone reverts enemy progress;
   empty zone decays; reaching 1.0 sets owner and resets progress.
4. **UI (later)**: HUD widget listening to `Events.zone_changed` (owner colour, progress bar, "CONTESTED").
5. **Match/score** (win condition, timers) is out of maps scope — lead to decide.
