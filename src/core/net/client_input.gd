class_name ClientInput
extends RefCounted
## CLIENT side wrapper around the local input source (Actions or autopilot).
## Each tick: polls, sends an input packet to the host, keeps it for reconciliation, and returns
## the frame so the hero can predict its own movement.
var inner
var seq := 0
var counters := [0, 0, 0, 0, 0]
var pending: Array = []    ## [{seq, move, yaw, jump, pos}]
var sent := 0

func _init(src) -> void:
    inner = src

func poll(h) -> InputFrame:
    var f: InputFrame = inner.poll(h)
    seq += 1
    var edges := [f.jump, f.reload, f.ability1, f.ability2, f.ultimate]
    for i in 5:
        if edges[i]:
            counters[i] += 1
    var yaw := wrapf(h.yaw + f.look.x, -PI, PI)
    var pitch := clampf(h.pitch + f.look.y, -1.3, 1.3)
    var view := Net.server_tick - int(Net.INTERP_DELAY * Engine.physics_ticks_per_second)
    Net.send_input([seq, view, yaw, pitch, f.move, f.fire, counters.duplicate()])
    sent += 1
    pending.append({"seq": seq, "move": f.move, "yaw": yaw, "jump": f.jump, "pos": null})
    while pending.size() > 120:
        pending.pop_front()
    return f

func record_pos(p: Vector3) -> void:
    if not pending.is_empty():
        pending[-1].pos = p

## Drops inputs the host has processed; returns the position we predicted for `acked` (or null).
func ack(acked: int):
    var at = null
    while not pending.is_empty() and int(pending[0].seq) <= acked:
        var e = pending.pop_front()
        if int(e.seq) == acked:
            at = e.pos
    return at
