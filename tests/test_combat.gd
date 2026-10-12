extends "res://tests/test_base.gd"

func test_health_clamps_and_dies() -> void:
    var h := Health.new(100)
    near(h.apply(30), 30, 0.001, "apply 30")
    near(h.apply(500), 70, 0.001, "overkill clamps to remaining")
    check(h.is_dead(), "dead at 0")
    near(h.apply(10), 0, 0.001, "no damage when dead")
    h.reset()
    near(h.hp, 100, 0.001, "reset")

func test_negative_damage_ignored() -> void:
    var h := Health.new(50)
    near(h.apply(-5), 0, 0.001, "negative ignored")

func test_cooldown_cycle() -> void:
    var c := Cooldown.new(2.0)
    check(c.is_ready(), "ready at start")
    check(c.trigger(), "trigger ok")
    check(not c.trigger(), "cannot retrigger")
    for i in 60:
        c.tick(1.0 / 60.0)
    check(not c.is_ready(), "not ready after 1s")
    near(c.fraction(), 0.5, 0.01, "half")
    for i in 61:
        c.tick(1.0 / 60.0)
    check(c.is_ready(), "ready after 2s")

func test_weapon_fire_rate_mag_reload() -> void:
    var w := Weapon.new({"damage": 10, "fire_rate": 10, "mag": 3, "reload_time": 1.0})
    check(w.try_fire(), "first shot")
    check(not w.try_fire(), "fire rate gate")
    w.tick(0.11)
    check(w.try_fire(), "second shot")
    w.tick(0.11)
    check(w.try_fire(), "third shot")
    check(w.ammo == 0 and w.reloading(), "auto reload on empty")
    w.tick(0.5)
    check(not w.try_fire(), "no fire while reloading")
    w.tick(0.6)
    check(w.ammo == 3 and not w.reloading(), "reloaded")
    check(not w.start_reload(), "no reload when full")

func test_ult_meter() -> void:
    var u := UltMeter.new(100)
    u.add(60)
    check(not u.is_full(), "not full")
    check(not u.consume(), "cannot consume")
    u.add(80)
    near(u.charge, 100, 0.001, "clamped")
    check(u.consume() and u.charge == 0.0, "consume resets")
