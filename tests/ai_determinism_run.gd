extends SceneTree
## Bench (not a gate suite): runs each AI driver twice with the gate's seeding (seed(4242) + run_seed 4242)
## and compares every result line.  godot --headless --path . -s tests/ai_determinism_run.gd
const DRIVERS := ["res://tests/ai_melee_driver.gd", "res://tests/ai_support_driver.gd"]
var runs: Array = []
var k := 0
var driver
var diffs := 0

func _process(_dt: float) -> bool:
    if driver != null and not driver.done:
        return false
    if driver != null:
        runs.append(driver.results.map(func(r): return "%s %s %s" % r))
        driver.queue_free()
        driver = null
        if k % 2 == 0:
            var a: Array = runs[-2]
            var b: Array = runs[-1]
            var same: bool = a == b
            if not same:
                diffs += 1
            print("%s  run1 == run2: %s" % [DRIVERS[k / 2 - 1].get_file(), same])
            for i in maxi(a.size(), b.size()):
                print("   1: %s\n   2: %s" % [a[i] if i < a.size() else "-", b[i] if i < b.size() else "-"])
        if k >= DRIVERS.size() * 2:
            print("DETERMINISM %s" % ("PASS" if diffs == 0 else "FAIL (%d drivers differ)" % diffs))
            quit(0 if diffs == 0 else 1)
            return false
    seed(4242)
    driver = load(DRIVERS[k / 2]).new()
    driver.run_seed = 4242
    k += 1
    root.add_child(driver)
    return false
