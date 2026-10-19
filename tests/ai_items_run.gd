extends SceneTree
## Bench (not a gate suite): ai_items_driver over N seeds.  godot --headless --path . -s tests/ai_items_run.gd -- --n=12
var n := 12
var seed0 := 0
var i := 0
var driver
var fails := 0
var st := {"heal": [], "pad": [], "nopad": [], "split": 0, "respawn": 0, "esc": 0, "taken": 0.0, "ctrl": 0.0, "faster": 0}

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
        var d = driver
        st.heal.append(d.heal_frames[1])
        st.pad.append(d.heal_frames[4])
        st.nopad.append(d.heal_frames[5] if d.heal_frames[5] > 0 else 99999)
        if d.heal_frames[4] > 0 and (d.heal_frames[5] < 0 or d.heal_frames[4] < d.heal_frames[5]):
            st.faster += 1
        if d.first_pack.get(3, []).size() == 2 and d.first_pack[3][0] != d.first_pack[3][1]:
            st.split += 1
        if d.first_pack.get(2) == [1] and d.heal_frames[2] > 0:
            st.respawn += 1
        if d.upper[6]:
            st.esc += 1
        st.taken += d.taken[6]
        st.ctrl += d.taken[7]
        print("seed %d  heal %d f | pad route %d f vs no pads %d f | split %s | respawn ok %s | escape %s, dmg %.0f vs %.0f  %s" % [seed0 + i - 1, d.heal_frames[1], d.heal_frames[4], d.heal_frames[5], d.first_pack.get(3), d.first_pack.get(2) == [1], d.upper[6], d.taken[6], d.taken[7], "ok" if bad.is_empty() else str(bad)])
        driver.queue_free()
        driver = null
        if i >= n:
            var rel_pad: bool = st.faster * 10 >= n * 8
            var rel_esc: bool = st.taken < st.ctrl
            print("ITEMS relative: pad route faster %d/%d -> %s | escape damage %.0f vs control %.0f -> %s" % [st.faster, n, "OK" if rel_pad else "FAIL", st.taken, st.ctrl, "OK" if rel_esc else "FAIL"])
            if not rel_pad or not rel_esc:
                fails += 1
            print("ITEMS n=%d heal median %.0f f | pad route median %.0f f vs no pads %.0f f | split %d/%d | respawn ok %d/%d | escaped %d/%d | failed_runs=%d" % [n, _med(st.heal), _med(st.pad), _med(st.nopad), st.split, n, st.respawn, n, st.esc, n, fails])
            quit(0 if fails == 0 else 1)
            return false
    driver = load("res://tests/ai_items_driver.gd").new()
    driver.run_seed = seed0 + i
    seed(6000 + i)
    i += 1
    root.add_child(driver)
    return false
