extends SceneTree
## Bench (not a gate suite): ai_support_driver over N seeds.  godot --headless --path . -s tests/ai_support_run.gd -- --n=20
var n := 20
var i := 0
var driver
var heals: Array = []
var negl: Array = []
var fails := 0

func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--n="):
            n = int(a.substr(4))

func _process(_dt: float) -> bool:
    if driver != null and not driver.done:
        return false
    if driver != null:
        var bad: Array = driver.results.filter(func(r): return not r[1])
        if not bad.is_empty():
            fails += 1
        heals.append(driver.ally_heal)
        negl.append(driver.worst_neglect)
        print("seed %2d  ally_heal %4.0f  answered %s  worst_neglect %.1f s  %s %s" % [i - 1, driver.ally_heal, driver.responded, driver.worst_neglect, "ok" if bad.is_empty() else "FAIL", bad, ])
        driver.queue_free()
        driver = null
        if i >= n:
            heals.sort()
            negl.sort()
            print("SUPPORT n=%d ally_heal min=%.0f median=%.0f max=%.0f | worst_neglect median=%.1f max=%.1f | failed_runs=%d" % [n, heals[0], heals[n / 2], heals[-1], negl[n / 2], negl[-1], fails])
            quit(0 if fails == 0 else 1)
            return false
    driver = load("res://tests/ai_support_driver.gd").new()
    driver.run_seed = i
    i += 1
    root.add_child(driver)
    return false
