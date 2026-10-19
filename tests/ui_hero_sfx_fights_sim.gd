extends Node3D
## Real composition root (main.tscn, offline, arena02 Control) with 9 allies + 10 enemy bots fighting: HeroSfx
## must hold >= 10 concurrent voices with distant fights still playing; then 3 bots fire their real ultimates at
## once (hero.gd -> Events.ability_used) and all must play together, unstolen, under the fight load.
var results: Array = []
var done := false
var m
var t := 0.0
var step := 0
var orig := {}
var peak := 0
var peak_far := 0
var far_max := 0.0

func _rec(n: String, ok: bool, info := "") -> void:
    results.append([n, ok, info])

func _ready() -> void:
    orig = {"hero": GameConfig.hero_id, "map": GameConfig.map_id, "a": GameConfig.ally_count, "e": GameConfig.enemy_count}
    GameConfig.set_hero("cob")
    GameConfig.map_id = "arena02"
    GameConfig.ally_count = 9
    GameConfig.enemy_count = 10
    GameConfig.skip_menu_once = true
    m = load("res://src/main.tscn").instantiate()
    add_child(m)

func _restore() -> void:
    GameConfig.set_hero(orig.hero)
    GameConfig.map_id = orig.map
    GameConfig.ally_count = orig.a
    GameConfig.enemy_count = orig.e

func _physics_process(dt: float) -> void:
    if done:
        return
    t += dt
    var s: HeroSfx = m.hud.hero_sfx if m.hud != null else null
    if s == null:
        return
    var lp := s.listener_pos()
    var c := s.active_counts()
    var far := 0
    for v in s.voices3d:
        if s.busy(v):
            var d: float = v.global_position.distance_to(lp)
            far_max = maxf(far_max, d)
            if d >= 25.0:
                far += 1
    if c[0] > peak:
        peak = c[0]
    peak_far = maxi(peak_far, far)
    match step:
        0:
            if t < 8.0:   # 8 s of real bot fights
                return
            var n := get_tree().get_nodes_in_group("heroes").size()
            print("    MEASURED fights sim: %d heroes, peak %d concurrent voices, %d of them >= 25 m (farthest %.0f m), steals %d, dropped %d, t=%.1f s" % [n, peak, peak_far, far_max, s.steals, s.dropped, t])
            _rec("heroes", n >= 20, str(n))
            _rec("concurrent_voices_ge_10", peak >= 10, str(peak))
            _rec("distant_still_play", peak_far >= 1, "far=%d max=%.0f m" % [peak_far, far_max])
            var bots: Array = get_tree().get_nodes_in_group("heroes").filter(func(h): return h != m.player and not h.dead and h.abilities.has("ultimate"))
            var used := 0
            for b in bots:
                if used >= 3:
                    break
                b.ult.charge = b.ult.cost
                var before := int(s.play_count.get(String(b.def.id) + "/ultimate", 0))
                b._use("ultimate")
                if int(s.play_count.get(String(b.def.id) + "/ultimate", 0)) > before:
                    used += 1
            var ults := s.voices3d.filter(func(v): return s.busy(v) and v.get_meta("ult", false))
            _rec("three_ults_play", used >= 3 and ults.size() >= 3, "used=%d playing=%d" % [used, ults.size()])
            set_meta("ults", ults)
            step = 1
            t = 0.0
        1:
            if t < 0.3:   # fights keep going around the ults
                return
            var ults: Array = get_meta("ults")
            var alive := ults.filter(func(v): return s.busy(v) and v.get_meta("ult", false))
            print("    MEASURED fights sim ults: %d concurrent after 0.3 s of fights (%d voices playing, steals %d)" % [alive.size(), s.active_counts()[0], s.steals])
            _rec("ults_survive_pool_pressure", alive.size() >= 3, str(alive.size()))
            _restore()
            done = true
