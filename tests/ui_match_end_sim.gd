extends Node
## Match-end screen laid out for real (frames, not the 2x2 host viewport): FFA + Control, win + defeat, at
## 1280x720, 1920x1080, 3840x2160 (unscaled and with the game's canvas_items stretch from 1280x720), 1280x800 and 21:9 (2560x1080 ->
## 1707x720 canvas, aspect expand). The canvas is never smaller than 1280x720 (stretch expand), so that is the floor.
## Award-card labels must have real width (the Windows bug: 1 px, one character per line), and banner, summary
## area, cards and buttons must be inside the viewport. Helpers: tests/ui_round21_test.gd.
var results: Array = []
var done := false
var T
var lobbies := {}
var queue := []
var cur = null
var frames := 0

func _rec(n: String, ok: bool, info := "") -> void:
    results.append([n, ok, info])

func _ready() -> void:
    T = load("res://tests/ui_round21_test.gd").new()
    T.tree = get_tree()
    for mode in ["ffa", "control"]:
        lobbies[mode] = T._lobby(mode)
        for spec in [[Vector2i(1280, 720), Vector2i.ZERO], [Vector2i(1920, 1080), Vector2i.ZERO], [Vector2i(3840, 2160), Vector2i.ZERO],
                [Vector2i(1920, 1080), Vector2i(1280, 720)], [Vector2i(3840, 2160), Vector2i(1280, 720)], [Vector2i(1280, 800), Vector2i.ZERO],
                [Vector2i(2560, 1080), Vector2i(1707, 720)]]:
            for winner in [0, 1]:
                queue.append([mode, spec[0], spec[1], winner])

func _process(_dt: float) -> void:
    if done:
        return
    if cur == null:
        if queue.is_empty():
            for mode in lobbies:
                T._free(lobbies[mode])
            done = true
            return
        var q = queue.pop_front()
        var sv: Array = T._screen_in(q[1], q[2])
        var me: MatchEndScreen = sv[1]
        me.set_control(RematchControl.new(null, null))
        var l: Array = lobbies[q[0]]
        me.show_results({"winner_team": q[3], "reason": "score", "mode": q[0]}, l[0], l[1])
        cur = [q, sv]
        frames = 0
        return
    frames += 1
    if frames < 3:
        return
    var q = cur[0]
    var vp: SubViewport = cur[1][0]
    var me: MatchEndScreen = cur[1][1]
    var area := Rect2(Vector2.ZERO, Vector2(q[2] if q[2] != Vector2i.ZERO else q[1]))
    var what := "%s_%s_%dx%d%s" % [q[0], me.outcome.to_lower(), q[1].x, q[1].y, "_scaled" if q[2] != Vector2i.ZERO else ""]
    T.errors = []
    T._check_fits(me, area, what)
    _rec(what + "_fits", T.errors.is_empty() and me.outcome == ("VICTORY" if q[3] == 0 else "DEFEAT"), str(T.errors.slice(0, 4)))
    vp.free()
    cur = null
