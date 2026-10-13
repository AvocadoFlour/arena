extends SceneTree
## Bench (not a gate suite): is "easy" gentle but not passive? 3v3 arena02 Control vs a frozen
## human-proxy reference team (the v0.8 normal preset, explicit params so tuning never moves it).
## Per seed, the SAME seed/sides are played twice: old easy (v0.8 preset, frozen here) and the
## current easy preset. Relative verdicts on the medians/totals.
##   godot --headless -s tests/ai_easy_run.gd -- --n=10 --seed0=200
const REF := {"difficulty": "normal", "spread_deg": 6.0, "turn_rate": 4.0, "fire_cone": 0.15, "reaction_time": 0.35, "aim_jitter": 0.05, "ability_delay": 0.6, "focus_slack": 8.0, "low_hp_frac": 0.35, "fire_duty": 1.0}
const OLD_EASY := {"difficulty": "easy", "spread_deg": 10.0, "turn_rate": 2.5, "fire_cone": 0.20, "reaction_time": 0.60, "aim_jitter": 0.12, "ability_delay": 2.0, "focus_slack": 0.0, "low_hp_frac": 0.20, "fire_duty": 1.0}
var n := 10
var seed0 := 200
var frames := 3600
var i := 0
var variant := 0          ## 0 old easy, 1 new easy
var driver
var rows := {0: [], 1: []}

func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--n="):
            n = int(a.substr(4))
        if a.begins_with("--seed0="):
            seed0 = int(a.substr(8))

func _med(a: Array) -> float:
    var b := a.duplicate()
    b.sort()
    return 0.0 if b.is_empty() else float(b[b.size() / 2])

func _col(v: int, k: String) -> Array:
    return rows[v].map(func(r): return r[k])

func _process(_dt: float) -> bool:
    if driver != null and not driver.done:
        return false
    if driver != null:
        var e: int = driver.get_meta("e")
        var r := {"dmg": driver.dmg[e], "ref_dmg": driver.dmg[1 - e], "kills": driver.kills[e], "deaths": driver.kills[1 - e],
            "moved": driver.moved[e], "abil": driver.abil[e], "zone": driver.presence[e], "score": driver.score[e]}
        rows[variant].append(r)
        print("seed %d %s easy  dmg %5.0f  kills %d  deaths %d  moved %4.0f m  abilities %2d  zone presence %4.1f s  owned %4.1f s" % [seed0 + i, ["old", "new"][variant], r.dmg, r.kills, r.deaths, r.moved, r.abil, r.zone, r.score])
        driver.queue_free()
        driver = null
        variant += 1
        if variant > 1:
            variant = 0
            i += 1
        if i >= n:
            var lines := []
            for k in ["dmg", "kills", "deaths", "moved", "abil", "zone", "score"]:
                lines.append("%s %.1f -> %.1f" % [k, _med(_col(0, k)), _med(_col(1, k))])
            print("EASY medians old -> new: " + ", ".join(lines))
            var sd0: float = _col(0, "dmg").reduce(func(a, b): return a + b, 0.0)
            var sd1: float = _col(1, "dmg").reduce(func(a, b): return a + b, 0.0)
            var sk0: int = _col(0, "kills").reduce(func(a, b): return a + b, 0)
            var sk1: int = _col(1, "kills").reduce(func(a, b): return a + b, 0)
            var checks := {
                "gentler_damage": sd1 <= sd0 * 0.8,
                "fewer_kills": sk1 <= sk0,
                "still_moves": _med(_col(1, "moved")) >= _med(_col(0, "moved")) * 0.8,
                "still_uses_abilities": _med(_col(1, "abil")) >= maxf(1.0, _med(_col(0, "abil")) * 0.6),
                "still_contests_point": _med(_col(1, "zone")) >= maxf(3.0, _med(_col(0, "zone")) * 0.6)}
            print("EASY totals dmg %.0f -> %.0f (%.0f%%), kills %d -> %d | checks %s" % [sd0, sd1, 100.0 * sd1 / maxf(1.0, sd0), sk0, sk1, str(checks)])
            quit(0 if not checks.values().has(false) else 1)
            return false
    var sc = load("res://tests/ai_teamplay_driver.gd")
    seed(7000 + i)
    driver = sc.new()
    driver.run_seed = seed0 + i
    driver.frames = frames
    driver.tp_team = -1
    var e := i % 2
    driver.diff = {e: "easy", 1 - e: "normal"}
    driver.extra = {e: OLD_EASY if variant == 0 else {}, 1 - e: REF}
    driver.set_meta("e", e)
    root.add_child(driver)
    return false
