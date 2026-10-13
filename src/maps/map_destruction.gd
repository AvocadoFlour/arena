class_name MapDestruction
extends Node
## Destructible cover manager, one per map (map root child "Destruction").
## Host/offline: DestructibleCover.apply_damage → on 0 HP `cover_broken({block_id, pos, map})` is emitted here
## (and on `Events.cover_broken` when core provides that signal, which Net replicates to clients).
## Clients: never decide; they call `apply_break(block_id)` (or `apply_broken(ids)` for late join).
## Removal = collision off + hidden immediately, then queue_free (INTERFACES §6 destructible rule).

signal cover_broken(ev: Dictionary)   ## host/offline: a cover was destroyed (decided here)
signal cover_removed(block_id: int)   ## any peer: a cover node was removed locally

var map_name := ""
var covers := {}          ## block_id -> DestructibleCover (still standing)
var broken: Array = []    ## block ids removed, in order
var authority_override := -1   ## tests: -1 = ask Net, 0 = client, 1 = host

func is_authority() -> bool:
    if authority_override >= 0:
        return authority_override == 1
    var ml := Engine.get_main_loop()
    if ml is SceneTree:
        var net: Node = (ml as SceneTree).root.get_node_or_null("Net")
        if net != null and net.has_method("is_authority"):
            return bool(net.is_authority())
    return true

func _ready() -> void:
    var ev := _events()
    if ev != null and ev.has_signal("cover_broken"):
        ev.connect("cover_broken", _on_bus_broken)

func _events() -> Node:
    var ml := Engine.get_main_loop()
    if ml is SceneTree:
        return (ml as SceneTree).root.get_node_or_null("Events")
    return null

func register(c: DestructibleCover) -> void:
    covers[c.block_id] = c
    c.destruction = self

func _break(c: DestructibleCover, source = null) -> void:
    var ev := {"block_id": c.block_id, "pos": c.global_position if c.is_inside_tree() else c.position, "map": map_name}
    _remove(c.block_id)
    cover_broken.emit(ev)
    var bus := _events()
    if bus != null and bus.has_signal("cover_broken"):
        bus.emit_signal("cover_broken", ev)
    if source != null:
        pass   # attribution kept for later (score/feeds); not part of the payload yet

## Client entry point (also safe on the host; idempotent). Returns true if a node was removed.
func apply_break(block_id: int) -> bool:
    return _remove(block_id)

## Late join: apply every id the host reports in broken_ids().
func apply_broken(ids: Array) -> void:
    for id in ids:
        _remove(int(id))

func broken_ids() -> Array:
    return broken.duplicate()

func hp_of(block_id: int) -> float:
    return covers[block_id].hp if covers.has(block_id) else 0.0

func _remove(block_id: int) -> bool:
    if not covers.has(block_id):
        return false
    var c: DestructibleCover = covers[block_id]
    covers.erase(block_id)
    broken.append(block_id)
    c.hp = 0.0
    c.collision_layer = 0
    c.collision_mask = 0
    for s in c.get_children():
        if s is CollisionShape3D:
            s.disabled = true
    c.visible = false
    if not c.is_inside_tree() and c.get_parent() != null:
        c.get_parent().remove_child(c)   # detached maps (tests/tools): drop it from the map now
    c.queue_free()                       # deferred: safe even when called from the cover's own apply_damage
    cover_removed.emit(block_id)
    return true

func _on_bus_broken(ev: Dictionary) -> void:
    if not is_authority():
        apply_break(int(ev.get("block_id", -1)))
