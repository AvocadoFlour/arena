extends SceneTree
## Bench (not a gate suite): head-to-head 3v3 (arena02 Control, team play on both sides, equal damage
## scale) between difficulties, sides mirrored every seed.  -- --n=10 --frames=3600 --pairs=hard:normal,normal:easy,hard:easy
var n := 10
var seed0 := 100
var frames := 3600
var pairs: Array = [["hard", "normal"], ["normal", "easy"], ["hard", "easy"]]
var pi := 0
var i := 0
var driver
var tally := {}

func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--n="):
            n = int(a.substr(4))
        if a.begins_with("--frames="):
            frames = int(a.substr(9))
        if a.begins_with("--seed0="):
            seed0 = int(a.substr(8))
        if a.begins_with("--pairs="):
            pairs = []
            for p in a.substr(8).split(","):
                pairs.append(p.split(":"))

func _process(_dt: float) -> bool:
    if driver != null and not driver.done:
        return false
    if driver != null:
        var p: Array = pairs[pi]
        var t: int = driver.get_meta("a_team")
        var o: int = driver.outcome_for(t)
        var k := "%s vs %s" % [p[0], p[1]]
        if not tally.has(k):
            tally[k] = [0, 0, 0, 0.0, 0.0, 0, 0]
        tally[k][o + 1] += 1
        tally[k][3] += driver.score[t]
        tally[k][4] += driver.score[1 - t]
        tally[k][5] += driver.kills[t]
        tally[k][6] += driver.kills[1 - t]
        print("%s seed %3d (%s on side %d)  zone %3.0f/%3.0f s  kills %d/%d  -> %s" % [k, seed0 + i - 1, p[0], t, driver.score[t], driver.score[1 - t], driver.kills[t], driver.kills[1 - t], ["LOSS", "DRAW", "WIN"][o + 1]])
        driver.queue_free()
        driver = null
        if i >= n:
            i = 0
            pi += 1
            if pi >= pairs.size():
                for kk in tally:
                    var v: Array = tally[kk]
                    # relative verdict: stronger side must win more than it loses AND out-kill the weaker side
                    var ok: bool = v[2] > v[0] and v[5] > v[6]
                    print("DIFF %s %s: W/D/L %d/%d/%d (win rate %.0f%%) | zone s %.1f vs %.1f | kills %d vs %d" % ["OK" if ok else "FAIL", kk, v[2], v[1], v[0], 100.0 * v[2] / n, v[3] / n, v[4] / n, v[5], v[6]])
                quit(0)
                return false
    var p2: Array = pairs[pi]
    var sc = load("res://tests/ai_teamplay_driver.gd")
    if sc == null or not sc.can_instantiate():
        quit(2)
        return false
    seed(9000 + i)
    driver = sc.new()
    driver.run_seed = seed0 + i
    driver.frames = frames
    driver.tp_team = -1
    var a_team := i % 2
    driver.diff = {a_team: p2[0], 1 - a_team: p2[1]}
    driver.set_meta("a_team", a_team)
    i += 1
    root.add_child(driver)
    return false
