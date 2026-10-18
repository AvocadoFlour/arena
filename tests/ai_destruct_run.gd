extends SceneTree
## Bench (not a gate suite): ai_destruct_driver over N seeds.  -- --n=10 --seed0=0
var n := 10
var seed0 := 0
var i := 0
var driver
var fails := 0
var stats := {"repick": [], "rebake": [], "hit": [], "ctrl": [], "broken": 0}

func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--n="):
            n = int(a.substr(4))
        if a.begins_with("--seed0="):
            seed0 = int(a.substr(8))

func _med(a: Array) -> float:
    var b := a.duplicate()
    b.sort()
    return -1.0 if b.is_empty() else float(b[b.size() / 2])

func _process(_dt: float) -> bool:
    if driver != null and not driver.done:
        return false
    if driver != null:
        var bad: Array = driver.results.filter(func(r): return not r[1])
        if not bad.is_empty():
            fails += 1
        stats.repick.append(driver.repick_frames)
        stats.rebake.append(driver.rebake_frames)
        stats.hit.append(driver.hits[2])
        stats.ctrl.append(driver.hits[3])
        if driver.broken[2]:
            stats.broken += 1
        print("seed %d  repick %d f  rebake %d f  breach: wall broken %s, enemy dmg %.0f vs control %.0f  %s" % [seed0 + i - 1, driver.repick_frames, driver.rebake_frames, driver.broken[2], driver.hits[2], driver.hits[3], "ok" if bad.is_empty() else str(bad)])
        driver.queue_free()
        driver = null
        if i >= n:
            var sh: float = stats.hit.reduce(func(a, b): return a + b, 0.0)
            var sc: float = stats.ctrl.reduce(func(a, b): return a + b, 0.0)
            var rel := sh >= sc
            print("DESTRUCT enemy damage total %.0f vs control %.0f (x%.2f) -> %s" % [sh, sc, sh / maxf(1.0, sc), "OK" if rel else "FAIL"])
            if not rel:
                fails += 1
            print("DESTRUCT n=%d repick median %.0f f max %.0f | rebake median %.0f f | wall broken %d/%d | enemy dmg median %.0f vs control %.0f | failed_runs=%d" % [n, _med(stats.repick), stats.repick.max(), _med(stats.rebake), stats.broken, n, _med(stats.hit), _med(stats.ctrl), fails])
            quit(0 if fails == 0 else 1)
            return false
    driver = load("res://tests/ai_destruct_driver.gd").new()
    driver.run_seed = seed0 + i
    seed(5000 + i)
    i += 1
    root.add_child(driver)
    return false
