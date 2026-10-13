extends "res://tests/test_base.gd"
## UI round 7: procedural UI SFX on the SFX bus, hit-marker / kill flash, ability-ready edge.
var tree: SceneTree

func test_sfx_synth_and_bus() -> void:
    for k in UiSfx.SPECS:
        var w := UiSfx.synth(UiSfx.SPECS[k])
        var secs := 0.0
        var samples := 0
        for seg in UiSfx.SPECS[k]:
            secs += seg[2]
            samples += int(UiSfx.RATE * float(seg[2]))
        check(w.format == AudioStreamWAV.FORMAT_16_BITS and w.mix_rate == UiSfx.RATE, k + " 16-bit wav")
        check(w.data.size() == 2 * samples, k + " length")
        check(secs <= 0.25, k + " short")
        var peak := 0
        for i in range(0, w.data.size(), 2):
            var v := w.data[i] | (w.data[i + 1] << 8)
            if v >= 32768:
                v -= 65536
            peak = maxi(peak, absi(v))
        check(peak > 3000 and peak <= 32767, k + " audible, no clipping (%d)" % peak)
    check(Settings.sfx != null, "Settings.sfx exists")
    check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus")
    for p in Settings.sfx.players:
        check(p.bus == "SFX", "player on SFX bus")
    check(Settings.sfx.streams.keys().size() == 4, "hit/kill/click/ready")

func test_sfx_play_and_rate_limit() -> void:
    var s := UiSfx.new()
    tree.root.add_child(s)
    check(s.play("hit"), "plays")
    check(not s.play("hit"), "rate-limited immediately after")
    check(s.play("kill"), "other sound not blocked")
    check(not s.play("nope"), "unknown name")
    check(s.play_count.get("hit", 0) == 1 and s.play_count.get("kill", 0) == 1, "counts")
    s.free()

func test_menu_click_sound() -> void:
    var before: int = Settings.sfx.play_count.get("click", 0)
    Settings.sfx.last_play.erase("click")
    var b := MenuStyle.button("X", func(): pass)
    b.pressed.emit()
    check(Settings.sfx.play_count.get("click", 0) == before + 1, "button click plays")
    b.free()
    var plain := Button.new()
    var root := Control.new()
    root.add_child(plain)
    MenuStyle.polish(root)
    MenuStyle.polish(root)
    check(plain.pressed.get_connections().size() == 1, "polish adds click once")
    root.free()

func test_crosshair_flash_hit_vs_kill() -> void:
    var c := Hud.Crosshair.new()
    c.flash(false)
    check(not c.kill and is_equal_approx(c.hit_t, Hud.Crosshair.HIT.time), "hit flash")
    c.flash(true)
    check(c.kill and is_equal_approx(c.hit_t, Hud.Crosshair.KILL.time), "kill flash")
    c.flash(false)
    check(c.kill, "hit doesn't downgrade active kill flash")
    var h: Dictionary = Hud.Crosshair.HIT
    var k: Dictionary = Hud.Crosshair.KILL
    check(k.time > h.time and k.outer > h.outer and k.width > h.width, "kill stronger")
    c.hit_t = 0.0
    c.flash(false)
    check(not c.kill, "after expiry a hit is a hit")
    c.free()

func test_ability_ready_edge() -> void:
    var hud := Hud.new()
    check(not hud.ready_edge("ability1", true), "first sample never fires")
    check(not hud.ready_edge("ability1", true), "steady ready")
    check(not hud.ready_edge("ability1", false), "going on cooldown")
    check(hud.ready_edge("ability1", true), "cooldown finished -> fires")
    check(not hud.ready_edge("ultimate", false) and hud.ready_edge("ultimate", true), "per slot")
    hud.free()
