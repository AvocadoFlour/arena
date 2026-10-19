extends "res://tests/test_base.gd"
## Readable ability stats (StatLabels): one label table, exact values, no raw keys, hidden non-applicable stats,
## on hero select, the Match page pane and the HUD tooltip.
var tree: SceneTree

func _def(id: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string("res://src/heroes/%s.json" % id))

func _ids() -> Array:
    return UiCatalog.list_heroes().map(func(h): return String(h.id))

## No raw key in any line: plain capitalised phrase, no underscores, never "key value".
func _no_raw(lines: Array, stats: Dictionary, what: String) -> void:
    for l in lines:
        check(not String(l).contains("_") and String(l)[0] == String(l)[0].to_upper(), "%s plain phrase: %s" % [what, l])
        for k in stats.keys():
            check(not String(l).begins_with(String(k) + " ") and not String(l).begins_with(String(k) + ":"), "%s raw key %s in: %s" % [what, k, l])

func test_number_formatting_is_exact() -> void:
    check(StatLabels.num(7.0) == "7" and StatLabels.num(7) == "7" and StatLabels.num(0.16) == "0.16", "trailing zeros only")
    check(StatLabels.num(51.2) == "51.2" and StatLabels.num(1.35) == "1.35", "decimals kept")
    check(StatLabels.num(89.4886363636364) == "89.4886363636364", "not rounded: " + StatLabels.num(89.4886363636364))
    for v in [0.6, 0.35, 0.125, 1.5, 0.5, 0.05, 2.0, 0.0]:
        var p := StatLabels.pct(v)
        check(is_equal_approx(float(p) / 100.0, v) and not p.contains("000000"), "pct(%s) = %s" % [v, p])
    check(StatLabels.pct(0.6) == "60" and StatLabels.pct(0.35) == "35" and StatLabels.pct(0.125) == "12.5" and StatLabels.pct(1.5) == "150", "exact decimal shift")

func test_every_real_stat_key_is_labelled_or_hidden() -> void:
    AbilityInfo.reset()
    check(AbilityInfo.has_api(), "real HeroAbilities on this branch")
    var seen := {}
    for id in _ids():
        for e in AbilityInfo.describe_all(id):
            for k in e.stats.keys():
                seen[k] = true
                check(StatLabels.coverage(k) != "", "%s %s: stat key '%s' has a label or is deliberately hidden" % [id, e.slot, k])
        var d := _def(id)
        for slot in AbilityInfo.SLOTS:
            var sd := AbilityInfo.slot_def(d, slot)
            for k in sd.keys():
                if (sd[k] is float or sd[k] is int or sd[k] is bool) and not k in HeroAbilities.COSMETIC:
                    check(StatLabels.coverage(k) != "", "%s %s: def key '%s' covered" % [id, slot, k])
        AbilityInfo.api_path = "res://nope.gd"
        for e in AbilityInfo.describe_all(id):   # JSON fallback stats too
            for k in e.stats.keys():
                check(StatLabels.coverage(k) != "", "fallback %s %s: '%s' covered" % [id, e.slot, k])
        AbilityInfo.reset()
    check(seen.size() > 30, "covered %d distinct real keys" % seen.size())

func test_values_match_defs_exactly() -> void:
    AbilityInfo.reset()
    for id in _ids():
        var d := _def(id)
        for e in AbilityInfo.describe_all(id):
            var lines := AbilityInfo.stat_lines(e)
            _no_raw(lines, e.stats, id + " " + e.slot)
            var sd := AbilityInfo.slot_def(d, e.slot)
            for k in sd.keys():
                var v = sd[k]
                if not (v is float or v is int) or float(v) == 0.0:
                    continue
                var lab := StatLabels.label_for(k, e.type, e.slot, e.stats)
                if lab.is_empty() or (k in ["mag", "reload_time"] and float(sd.get("mag", 0)) >= 999) or (k == "spread_deg" and e.type == "melee"):
                    continue
                var want := "%s: %s" % [String(lab[0]).replace("{hit}", "Third" if int(e.stats.get("combo_hits", 0)) == 3 else String(lab[0])), StatLabels._value(v, lab[1])]
                check(lines.has(want), "%s %s shows %s exactly (%s) in %s" % [id, e.slot, k, want, lines])
                check(float(StatLabels.num(v)) == float(v), "%s %s %s round-trips" % [id, e.slot, k])
            var slow = sd.get("slow")
            if slow is Dictionary and float(slow.get("mult", 1)) > 0.0:
                check(lines.has("Slow: %s%% move speed for %s s" % [StatLabels.pct(slow.mult), StatLabels.num(slow.duration)]), "%s slow line: %s" % [id, lines])
            elif slow is Dictionary:
                check(lines.has("Root: %s s" % StatLabels.num(slow.duration)), "%s root line: %s" % [id, lines])
            elif slow is float or slow is int:
                check(lines.has("Slow: %s%% move speed for %s s" % [StatLabels.pct(slow), StatLabels.num(sd.slow_duration)]), "%s pull slow: %s" % [id, lines])

func test_known_phrases() -> void:
    AbilityInfo.reset()
    var tb := AbilityInfo.stat_lines(AbilityInfo.describe("the_best", "primary"))
    for want in ["Damage per hit: 32", "Third-hit damage: 51.2", "Swings per second: 2.2", "Reach: 3.2 m", "Swing arc: 110°", "Third-hit knockback: 7 m/s"]:
        check(tb.has(want), "The Best primary has '%s': %s" % [want, tb])
    check(not tb.any(func(l): return l.begins_with("Spread") or l.begins_with("Magazine") or l.begins_with("Reload")), "melee: no spread/ammo/reload: %s" % [tb])
    var tomo := AbilityInfo.stat_lines(AbilityInfo.describe("tomo", "primary"))
    check(tomo.has("Shots per second in a burst: 14") and tomo.has("Shots per burst: 3") and tomo.has("Range: 55 m") and tomo.has("Spread: 0.6°") and tomo.has("Magazine: 24 rounds"), "Tomo ranged phrases: %s" % [tomo])
    var bp := AbilityInfo.stat_lines(AbilityInfo.describe("tomo", "ability2"))
    check(bp.has("Root: 1.1 s") and bp.has("Cooldown: 10 s") and not bp.any(func(l): return l.begins_with("Splash") or l.begins_with("Gravity")), "Breakpoint root, zero splash/gravity hidden: %s" % [bp])
    var nj := AbilityInfo.stat_lines(AbilityInfo.describe("nidjo", "ability2"))
    check(nj.has("Slow: 60% move speed for 2 s") and nj.has("Radius: 8 m"), "Stand-up Meeting slow: %s" % [nj])
    var rb := AbilityInfo.stat_lines(AbilityInfo.describe("nidjo", "ultimate"))
    check(rb.has("Damage reduction: 35% for 4 s") and rb.has("Ultimate cost: 600 charge") and rb.has("Rewinds: 4 s"), "Rollback: %s" % [rb])
    var nl := AbilityInfo.stat_lines(AbilityInfo.describe("the_best", "ultimate"))
    check(nl.has("Damage boost: ×1.35") and nl.has("Knockback immune") and nl.has("Overheal: 120"), "No Limits: %s" % [nl])

func test_hidden_values() -> void:
    var l := StatLabels.lines({"damage": 0, "flag": true, "knockback_immune": false, "weird_key": 3, "splash_radius": 0.0, "needs_ult": true, "sample": 0.25, "cooldown": 7.0}, "x", "ability1")
    check(l == ["Cooldown: 7 s"], "zero / false / unknown / hidden keys never shown: %s" % [l])
    check(StatLabels.lines({"slow_mult": 1.0, "slow_duration": 2}, "projectile", "ability2").is_empty(), "x1 speed is no slow")

func test_ui_surfaces_show_labels_not_keys() -> void:
    AbilityInfo.reset()
    var hd := HeroDetail.new()
    tree.root.add_child(hd)
    for id in _ids():
        hd.show_def(_def(id))
        for slot in ["primary", "ability1", "ability2", "ultimate"]:
            var st: Label = hd.info.find_child("Stats_" + slot, true, false)
            check(st != null and st.text == AbilityInfo.stats_text(AbilityInfo.describe(id, slot)), "%s %s hero select uses the labelled lines" % [id, slot])
            if st != null:
                check(not st.text.contains("_") and not st.text.contains("·"), "%s %s no raw keys: %s" % [id, slot, st.text])
    hd.free()
    var tip := AbilityTooltip.new()
    tree.root.add_child(tip)
    tip.entry_for = func(s): return AbilityInfo.describe("cob", s)
    tip.show_tip("ultimate", "hover")
    check(tip.stats.text.contains("Ultimate cost: 600 charge") and tip.stats.text.contains("Damage: 190") and not tip.stats.text.contains("_"), "tooltip: " + tip.stats.text)
    tip.free()
    var lst := AbilityList.new()
    tree.root.add_child(lst)
    lst.show_hero("nidjo")
    var st2: Label = lst.find_child("Stats_ability2", true, false)
    check(st2 != null and st2.text.contains("Slow: 60% move speed for 2 s"), "match pane list (AbilityList)")
    lst.free()
