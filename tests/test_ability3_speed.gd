extends "res://tests/test_base.gd"
## Core: ability3 input (right mouse, INTERFACES §1/§2.2/§10) and offline-only game speed.

func _pkt(seq: int, counters: Array) -> Array:
    return [seq, 100, 0.0, 0.0, Vector2.ZERO, false, counters]

func test_ability3_binding_and_frame() -> void:
    check(Actions.MOUSE_BINDINGS.has("ability3") and Actions.MOUSE_BINDINGS["ability3"] == [MOUSE_BUTTON_RIGHT], "ability3 bound to right mouse")
    check(InputMap.has_action("ability3"), "ability3 action registered")
    var f := InputFrame.new()
    check(f.ability3 == false, "InputFrame.ability3 defaults false")
    check(Net.SLOTS.has("ability3") and Net.SLOTS.find("ability3") < Net.SLOTS.find("ultimate"), "Net.SLOTS carries ability3 cooldown")

func test_ability3_counter_roundtrip() -> void:
    var ri := RemoteInput.new()
    var h := {"yaw": 0.0, "pitch": 0.0}
    ri.push(_pkt(1, [0, 0, 0, 0, 0, 0]))
    ri.push(_pkt(2, [0, 0, 0, 0, 0, 1]))
    var f := ri.poll(h)
    check(not f.ability3, "no a3 edge on first packet")
    f = ri.poll(h)
    check(f.ability3 and not f.ability1 and not f.ultimate, "a3 counter increase = one press")
    f = ri.poll(h)
    check(not f.ability3, "a3 edge not repeated")
    var old := RemoteInput.new()   # older 5-counter clients still work
    old.push(_pkt(1, [0, 0, 0, 0, 0]))
    old.push(_pkt(2, [0, 0, 1, 0, 0]))
    old.poll(h)
    f = old.poll(h)
    check(f.ability1 and not f.ability3, "5-counter packet still parsed")

class _Src:
    var a3 := false
    func poll(_h) -> InputFrame:
        var f := InputFrame.new()
        f.ability3 = a3
        return f

func test_client_input_counts_ability3() -> void:
    var src := _Src.new()
    var ci := ClientInput.new(src)
    check(ci.counters.size() == 6, "client counters include a3")
    var h := {"yaw": 0.0, "pitch": 0.0}
    src.a3 = true
    ci.poll(h)
    check(ci.counters[5] == 1 and ci.counters[2] == 0, "a3 press counted in slot 5")

func test_game_speed_offline_only() -> void:
    var keep_speed: float = Settings.game_speed
    var keep_mode: int = Net.mode
    Settings.game_speed = 0.6
    Net.mode = Net.OFFLINE
    Net.mode_changed.emit(Net.mode)
    near(Engine.time_scale, 0.6, 0.001, "offline: game speed applied")
    check(Settings.speed_allowed(), "offline: slider enabled")
    for m in [Net.HOST, Net.CLIENT]:
        Net.mode = m
        Net.mode_changed.emit(m)
        near(Engine.time_scale, 1.0, 0.001, "online: time_scale forced to 1.0")
        check(not Settings.speed_allowed(), "online: slider disabled")
        Settings.apply_speed()
        near(Engine.time_scale, 1.0, 0.001, "online: re-apply keeps 1.0")
    Net.mode = Net.OFFLINE
    Net.mode_changed.emit(Net.mode)
    near(Engine.time_scale, 0.6, 0.001, "back offline: speed restored")
    Net.mode = keep_mode
    Settings.game_speed = keep_speed
    Settings.apply_speed()
