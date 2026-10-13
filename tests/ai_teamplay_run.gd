extends SceneTree
## Bench (not a gate suite): ai_teamplay_driver over N seeds, alternating which side has team play.
## godot --headless --path . -s tests/ai_teamplay_run.gd -- --n=20 --frames=3600
var n := 20
var frames := 3600
var i := 0
var driver
var w := 0
var l := 0
var d := 0
var fails := 0
var acc := {"conc": [], "conc0": [], "grp": [], "grp0": [], "tank": [], "tank0": []}

var seed0 := 0

func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--seed0="):
            seed0 = int(a.substr(8))
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--n="):
            n = int(a.substr(4))
        if a.begins_with("--frames="):
            frames = int(a.substr(9))

func _med(a: Array) -> float:
    var b := a.duplicate()
    b.sort()
    return b[b.size() / 2]

func _process(_dt: float) -> bool:
    if driver != null and not driver.done:
        return false
    if driver != null:
        var o: int = driver.outcome()
        if o > 0: w += 1
        elif o < 0: l += 1
        else: d += 1
        var t: int = driver.tp_team
        acc.conc.append(driver.m(driver.conc, t)); acc.conc0.append(driver.m(driver.conc, 1 - t))
        acc.grp.append(driver.m(driver.group, t)); acc.grp0.append(driver.m(driver.group, 1 - t))
        acc.tank.append(float(driver.tank_on[t][0]) / maxf(1.0, driver.tank_on[t][1]))
        acc.tank0.append(float(driver.tank_on[1 - t][0]) / maxf(1.0, driver.tank_on[1 - t][1]))
        var bad: Array = driver.results.filter(func(r): return not r[1])
        if not bad.is_empty():
            fails += 1
        print("seed %2d side %d  zone %3.0f s vs %3.0f s  kills %d vs %d  conc %.2f/%.2f  group %.1f/%.1f m  tank %3.0f%%/%3.0f%%  -> %s  %s" % [seed0 + i - 1, t, driver.score[t], driver.score[1 - t], driver.kills[t], driver.kills[1 - t], acc.conc[-1], acc.conc0[-1], acc.grp[-1], acc.grp0[-1], acc.tank[-1] * 100, acc.tank0[-1] * 100, ["LOSS", "DRAW", "WIN"][o + 1], "" if bad.is_empty() else str(bad)])
        driver.queue_free()
        driver = null
        if i >= n:
            print("TEAMPLAY n=%d win/draw/loss %d/%d/%d (win rate %.0f%%) | focus conc median %.2f vs %.2f | group median %.1f vs %.1f m | tank on point median %.0f%% vs %.0f%% | runs with a failed check %d" % [n, w, d, l, 100.0 * w / n, _med(acc.conc), _med(acc.conc0), _med(acc.grp), _med(acc.grp0), _med(acc.tank) * 100, _med(acc.tank0) * 100, fails])
            quit(0)
            return false
    seed(4242 + i)
    var sc = load("res://tests/ai_teamplay_driver.gd")
    if sc == null or not sc.can_instantiate():
        quit(2)
        return false
    driver = sc.new()
    driver.run_seed = seed0 + i
    driver.frames = frames
    driver.tp_team = i % 2
    i += 1
    root.add_child(driver)
    return false
