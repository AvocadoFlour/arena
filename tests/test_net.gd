extends "res://tests/test_base.gd"
## Networking units (INTERFACES §10): input packets, edge counters, reconciliation acks, address parsing.

func _pkt(seq: int, yaw: float, counters: Array, fire := false) -> Array:
    return [seq, 100, yaw, 0.2, Vector2(0, 1), fire, counters]

func test_remote_input_edges_and_look() -> void:
    var ri := RemoteInput.new()
    var h := {"yaw": 0.0, "pitch": 0.0}
    ri.push(_pkt(1, 0.5, [0, 0, 0, 0, 0]))
    ri.push(_pkt(2, 0.5, [1, 0, 1, 0, 0], true))
    var f := ri.poll(h)
    near(f.look.x, 0.5, 1e-4, "absolute yaw -> delta")
    near(f.look.y, 0.2, 1e-4, "absolute pitch -> delta")
    check(not f.jump and ri.acked == 1, "no edge on first packet")
    f = ri.poll(h)
    check(f.jump and f.ability1 and not f.ability2 and f.fire, "counter increase = one press")
    f = ri.poll(h)   # queue empty: repeat last held state, but never re-fire an edge
    check(not f.jump and not f.ability1 and f.fire, "no doubled edges on repeat")
    ri.push(_pkt(2, 0.0, [5, 5, 5, 5, 5]))
    check(ri.queue.is_empty(), "stale seq dropped")

func test_remote_input_clamps() -> void:
    var ri := RemoteInput.new()
    ri.push([1, 0, 0.0, 9.0, Vector2(5, 5), false, [0, 0, 0, 0, 0]])
    var f := ri.poll({"yaw": 0.0, "pitch": 0.0})
    near(f.look.y, 1.3, 1e-4, "pitch clamped by host")
    near(f.move.length(), 1.0, 1e-4, "move clamped to unit length")

func test_client_ack_returns_prediction() -> void:
    var ci := ClientInput.new(null)
    for i in 5:
        ci.seq += 1
        ci.pending.append({"seq": ci.seq, "move": Vector2.ZERO, "yaw": 0.0, "jump": false, "pos": null})
        ci.record_pos(Vector3(i, 0, 0))
    check(ci.ack(3) == Vector3(2, 0, 0), "predicted pos at acked seq")
    check(ci.pending.size() == 2, "acked inputs dropped")
    check(ci.ack(3) == null, "unknown ack -> null (forces snap)")

func test_parse_address() -> void:
    check(NetPanel.parse_address(" 1.2.3.4:999 ") == ["1.2.3.4", 999], "ip:port")
    check(NetPanel.parse_address("example.org") == ["example.org", 24565], "default port")
