extends SceneTree
## Bench (not a gate suite): runs ai_melee_driver N times with different seeds and prints the
## distribution of the ranged bot's closest gap.  godot --headless --path . -s tests/ai_standoff_run.gd -- --n=24
var n := 24
var i := 0
var driver
var gaps: Array = []
var fails := 0

func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--n="):
            n = int(a.substr(4))

func _process(_dt: float) -> bool:
    if driver != null and not driver.done:
        return false
    if driver != null:
        gaps.append(driver.min_gap2)
        var ok := true
        for r in driver.results:
            ok = ok and r[1]
        if not ok:
            fails += 1
        print("seed %2d  closest %.2f m  end %.2f m  %s" % [i - 1, driver.min_gap2, driver._flat(driver.ranged, driver.dummy2), "ok" if ok else "FAIL " + str(driver.results.filter(func(r): return not r[1]))])
        driver.queue_free()
        driver = null
        if i >= n:
            gaps.sort()
            var s := 0.0
            for g in gaps:
                s += g
            print("STANDOFF n=%d min=%.2f p10=%.2f median=%.2f mean=%.2f max=%.2f failed_runs=%d" % [n, gaps[0], gaps[int(n * 0.1)], gaps[n / 2], s / n, gaps[-1], fails])
            quit(0 if fails == 0 else 1)
            return false
    driver = load("res://tests/ai_melee_driver.gd").new()
    driver.run_seed = i
    i += 1
    root.add_child(driver)
    return false
