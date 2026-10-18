class_name MapGrid
extends RefCounted
## Walkability grid built analytically from map JSON blocks (no physics needed).
## Nodes are standable surfaces (cell, height); edges join 4-neighbours whose height
## differs by <= STEP going up, or <= DROP going down. Used by tests and future bot nav.

const STEP := 0.6
const DROP := 5.0
const HEADROOM := 1.8

var cell: float
var origin: Vector2
var nx: int
var nz: int
var columns: Array = []   ## index -> Array[float] of standable heights (ascending)
var _obbs: Array = []

static func from_def(d: Dictionary, cell_size := 0.5) -> MapGrid:
    var g := MapGrid.new()
    g.cell = cell_size
    for b in d.get("blocks", []):
        var rot: Array = b.get("rot_deg", [0, 0, 0])
        var basis := Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2])), EULER_ORDER_YXZ)
        g._obbs.append({"c": Vector3(b.pos[0], b.pos[1], b.pos[2]), "b": basis,
            "e": Vector3(b.size[0], b.size[1], b.size[2]) * 0.5})
    var mn := Vector2(INF, INF)
    var mx := Vector2(-INF, -INF)
    for o in g._obbs:
        var r: float = o.e.length()
        mn = Vector2(minf(mn.x, o.c.x - r), minf(mn.y, o.c.z - r))
        mx = Vector2(maxf(mx.x, o.c.x + r), maxf(mx.y, o.c.z + r))
    g.origin = mn
    g.nx = int(ceil((mx.x - mn.x) / cell_size)) + 1
    g.nz = int(ceil((mx.y - mn.y) / cell_size)) + 1
    for iz in g.nz:
        for ix in g.nx:
            g.columns.append(g._column(g.cell_pos(ix, iz)))
    return g

func cell_pos(ix: int, iz: int) -> Vector2:
    return origin + Vector2(ix, iz) * cell

## Vertical line through (x,z): list of [enter_y (top), exit_y (bottom)] per box.
func _intervals(p: Vector2) -> Array:
    var out: Array = []
    for o in _obbs:
        var bt: Basis = o.b.transposed()
        var lo: Vector3 = bt * (Vector3(p.x, 0.0, p.y) - o.c)
        var ld: Vector3 = bt * Vector3.UP
        var t0 := -INF
        var t1 := INF
        var ok := true
        for a in 3:
            if absf(ld[a]) < 1e-9:
                if absf(lo[a]) > o.e[a]:
                    ok = false
                    break
            else:
                var ta: float = (-o.e[a] - lo[a]) / ld[a]
                var tb: float = (o.e[a] - lo[a]) / ld[a]
                t0 = maxf(t0, minf(ta, tb))
                t1 = minf(t1, maxf(ta, tb))
        if ok and t1 > t0:
            out.append([t1, t0])
    return out

func _column(p: Vector2) -> Array:
    var iv := _intervals(p)
    var hs: Array = []
    for i in iv:
        var h: float = i[0]
        var free := true
        for j in iv:
            if j[0] > h + 0.05 and j[1] < h + HEADROOM:
                free = false
                break
        if free:
            hs.append(h)
    hs.sort()
    return hs

## Node id = column index * 16 + level index.
func node_at(pos: Vector3, tol := 0.6) -> int:
    var ix := int(round((pos.x - origin.x) / cell))
    var iz := int(round((pos.z - origin.y) / cell))
    if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
        return -1
    var col: Array = columns[iz * nx + ix]
    var best := -1
    var bd := INF
    for li in col.size():
        var dh: float = pos.y - col[li]
        if dh > -0.3 and dh < tol + 0.3 and absf(dh) < bd:
            bd = absf(dh)
            best = li
    return -1 if best < 0 else (iz * nx + ix) * 16 + best

func node_pos(n: int) -> Vector3:
    var ci := n >> 4
    var p := cell_pos(ci % nx, ci / nx)
    return Vector3(p.x, columns[ci][n & 15], p.y)

## Breadth-first flood from a node; returns Dictionary of reached node ids.
## blocked (optional): Callable(pos: Vector3) -> bool; nodes for which it returns true are never entered
## (e.g. enemy spawn-room keep-out volumes, SpawnRooms.owner_at).
func flood(start: int, blocked := Callable()) -> Dictionary:
    var seen := {start: true}
    var q: Array = [start]
    var head := 0
    while head < q.size():
        var n: int = q[head]
        head += 1
        var ci := n >> 4
        var ix := ci % nx
        var iz := ci / nx
        var h: float = columns[ci][n & 15]
        for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
            var jx: int = ix + d.x
            var jz: int = iz + d.y
            if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
                continue
            var cj := jz * nx + jx
            var col: Array = columns[cj]
            for li in col.size():
                var dh: float = col[li] - h
                if dh <= STEP and dh >= -DROP:
                    var m := cj * 16 + li
                    if not seen.has(m):
                        if blocked.is_valid() and blocked.call(Vector3(cell_pos(jx, jz).x, col[li], cell_pos(jx, jz).y)):
                            continue
                        seen[m] = true
                        q.append(m)
    return seen

static func reaches_box(reached: Dictionary, g: MapGrid, center: Vector3, size: Vector3) -> bool:
    var aabb := AABB(center - size * 0.5, size)
    for n in reached:
        if aabb.has_point(g.node_pos(n) + Vector3(0, 0.05, 0)):
            return true
    return false
