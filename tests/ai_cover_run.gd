extends SceneTree
## Bench (not a gate suite): ai_cover_driver over N seeds.  godot --headless --path . -s tests/ai_cover_run.gd -- --n=20
var n := 20
var i := 0
var driver
var fails := 0
var rows: Array = []

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
        var frac := float(driver.hide_seen) / maxf(1.0, float(driver.hide_frames))
        rows.append([driver.taken[1], driver.taken[2], driver.brain.peeks if false else 0])
        print("seed %2d  peeks %d  peek_dmg %4.0f  hidden_LOS %3.0f%%  taken cover %4.0f / none %4.0f  %s" % [i - 1, driver.results[2][2].split(" ")[0].trim_prefix("peeks=").to_int(), driver.peek_dealt, frac * 100, driver.taken[1], driver.taken[2], "ok" if bad.is_empty() else "FAIL %s" % [bad]])
        driver.queue_free()
        driver = null
        if i >= n:
            var r1: Array = rows.map(func(r): return r[0])
            var r2: Array = rows.map(func(r): return r[1])
            r1.sort()
            r2.sort()
            print("COVER n=%d taken_with_cover median=%.0f max=%.0f | without median=%.0f min=%.0f | failed_runs=%d" % [n, r1[n / 2], r1[-1], r2[n / 2], r2[0], fails])
            quit(0 if fails == 0 else 1)
            return false
    seed(4242 + i)
    driver = load("res://tests/ai_cover_driver.gd").new()
    driver.run_seed = i
    i += 1
    root.add_child(driver)
    return false
