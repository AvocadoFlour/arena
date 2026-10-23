class_name RemoteInput
extends RefCounted
## HOST side input source for a remote human (INTERFACES.md §10).
## Packets: [seq, view_tick, yaw, pitch, move: Vector2, fire: bool, counters: [jump, reload, a1, a2, ult, a3]].
## Buttons are cumulative press counters, so a lost/merged packet never loses or doubles an edge.
const MAX_QUEUE := 8
var queue: Array = []
var last = null
var counters := [0, 0, 0, 0, 0, 0]
var acked := -1           ## newest seq consumed (sent back in snapshots for reconciliation)
var view_tick := -1       ## server tick the client was rendering (lag compensation)
var received := 0

func push(pkt: Array) -> void:
    if pkt.size() < 7 or int(pkt[0]) <= acked:
        return
    received += 1
    queue.append(pkt)
    while queue.size() > MAX_QUEUE:
        queue.pop_front()

func poll(h) -> InputFrame:
    var f := InputFrame.new()
    var p = queue.pop_front() if not queue.is_empty() else last
    if p == null:
        return f
    last = p
    acked = maxi(acked, int(p[0]))
    view_tick = int(p[1])
    var yaw := float(p[2])
    var pitch := clampf(float(p[3]), -1.3, 1.3)        # host validates
    f.look = Vector2(wrapf(yaw - h.yaw, -PI, PI), pitch - h.pitch)
    var mv: Vector2 = p[4] if p[4] is Vector2 else Vector2.ZERO
    f.move = mv.limit_length(1.0)
    f.fire = bool(p[5])
    var c: Array = p[6]
    if c.size() == 5 or c.size() == 6:   # 5 = older client without ability3
        f.jump = int(c[0]) > counters[0]
        f.reload = int(c[1]) > counters[1]
        f.ability1 = int(c[2]) > counters[2]
        f.ability2 = int(c[3]) > counters[3]
        f.ultimate = int(c[4]) > counters[4]
        if c.size() == 6:
            f.ability3 = int(c[5]) > counters[5]
        for i in c.size():
            counters[i] = maxi(counters[i], int(c[i]))
    return f
