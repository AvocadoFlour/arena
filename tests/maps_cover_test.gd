extends "res://tests/test_base.gd"
## Destructible cover (queue item 2): HP, damage, breaking, removal, host authority, client apply, ids.

const MAPS := ["arena01.json", "arena02.json"]

func _build(f: String, auth := 1) -> Node3D:
    var m := MapLoader.build("res://src/maps/" + f, {"low_quality": false})
    m.get_node("Destruction").authority_override = auth
    return m

func _ids(d: Dictionary) -> Array:
    var out: Array = []
    for i in d.blocks.size():
        if MapLoader.is_destructible(d.blocks[i]):
            out.append(i)
    return out

func test_covers_from_data() -> void:
    for f in MAPS:
        var d: Dictionary = MapLoader.load_def("res://src/maps/" + f)
        var ids := _ids(d)
        check(ids.size() >= 2, "%s has destructible covers (%d)" % [f, ids.size()])
        var m := _build(f)
        var ds: MapDestruction = m.get_node("Destruction")
        check(ds.covers.keys() == ids, "%s registry ids = JSON block indices %s" % [f, ids])
        for id in ids:
            var c: DestructibleCover = m.get_node("cover_%02d" % id)
            check(c != null and c.block_id == id and c.get_meta("kind") == "cover", "%s cover_%02d is a cover block" % [f, id])
            check(c.is_in_group("destructible"), "group destructible")
            near(c.hp, float(d.blocks[id].hp), 0.001, "%s hp from JSON" % f)
            check(c.get_node_or_null("Outline") != null, "%s cover_%02d has own outline hull" % [f, id])
        m.free()

func test_damage_and_break() -> void:
    var m := _build("arena02.json")
    var ds: MapDestruction = m.get_node("Destruction")
    var id: int = ds.covers.keys()[0]
    var c: DestructibleCover = ds.covers[id]
    var evs: Array = []
    ds.cover_broken.connect(func(ev): evs.append(ev))
    near(c.apply_damage(100.0), 100.0, 0.001, "100 applied")
    near(ds.hp_of(id), 200.0, 0.001, "hp 200 left")
    near(c.take_damage(50.0, null, Vector3.ZERO, "primary"), 50.0, 0.001, "take_damage alias")
    check(evs.is_empty(), "not broken yet")
    near(c.apply_damage(1000.0), 150.0, 0.001, "overkill clamps to remaining hp")
    check(evs.size() == 1 and evs[0].block_id == id, "broken once: %s" % [evs])
    check(not ds.covers.has(id) and ds.broken_ids() == [id], "registry updated")
    check(c.apply_damage(10.0) == 0.0, "no damage after break")
    check(c.apply_damage(-5.0) == 0.0, "negative ignored")
    m.free()

func test_removal_collision_and_visuals() -> void:
    var m := _build("arena01.json")
    var ds: MapDestruction = m.get_node("Destruction")
    var id: int = ds.covers.keys()[1]
    var before: int = load("res://tests/maps_visual_test.gd").signature(m).size()
    var outlines_before: int = m.get_node("Outlines").get_meta("hull_count")
    var removed: Array = []
    ds.cover_removed.connect(func(i): removed.append(i))
    ds.covers[id].apply_damage(9999.0)
    check(m.get_node_or_null("cover_%02d" % id) == null, "node removed from map")
    check(load("res://tests/maps_visual_test.gd").signature(m).size() == before - 1, "exactly one collision shape gone")
    check(m.get_node("Outlines").get_meta("hull_count") == outlines_before, "merged outline mesh untouched (cover hull was its own)")
    check(removed == [id], "cover_removed emitted")
    m.free()

func test_removal_in_tree_is_immediate_for_physics() -> void:
    var m := _build("arena01.json")
    var ds: MapDestruction = m.get_node("Destruction")
    var holder := Node3D.new()
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.add_child(holder)
    holder.add_child(m)
    var id: int = ds.covers.keys()[0]
    var c: DestructibleCover = ds.covers[id]
    c.apply_damage(9999.0)
    check(c.collision_layer == 0 and not c.visible and c.is_queued_for_deletion(), "disabled+hidden now, queue_free'd")
    var cs: CollisionShape3D = c.find_children("*", "CollisionShape3D", false, false)[0]
    check(cs.disabled, "shape disabled")
    holder.free()

func test_only_host_decides() -> void:
    var m := _build("arena02.json", 0)   # client
    var ds: MapDestruction = m.get_node("Destruction")
    var evs: Array = []
    ds.cover_broken.connect(func(ev): evs.append(ev))
    for id in ds.covers.keys():
        check(ds.covers[id].apply_damage(9999.0) == 0.0, "client: damage ignored on %d" % id)
        check(ds.covers[id].take_damage(9999.0) == 0.0, "client: take_damage ignored on %d" % id)
    check(evs.is_empty() and ds.broken_ids().is_empty(), "client never breaks")
    m.free()

func test_client_applies_host_break() -> void:
    var host := _build("arena02.json", 1)
    var client := _build("arena02.json", 0)
    var hd: MapDestruction = host.get_node("Destruction")
    var cd: MapDestruction = client.get_node("Destruction")
    hd.cover_broken.connect(func(ev): cd.apply_break(ev.block_id))   # what core's RPC/event does
    var id: int = hd.covers.keys()[1]
    hd.covers[id].apply_damage(9999.0)
    check(client.get_node_or_null("cover_%02d" % id) == null, "client removed the same block id")
    check(cd.broken_ids() == hd.broken_ids(), "same broken set")
    check(load("res://tests/maps_visual_test.gd").signature(host) == load("res://tests/maps_visual_test.gd").signature(client), "host and client collision identical")
    check(cd.apply_break(id) == false and cd.apply_break(9999) == false, "apply_break idempotent / unknown id ignored")
    host.free()
    client.free()

func test_late_join_apply_broken() -> void:
    var host := _build("arena02.json", 1)
    var hd: MapDestruction = host.get_node("Destruction")
    for id in hd.covers.keys().slice(0, 2):
        hd.covers[id].apply_damage(9999.0)
    var late := _build("arena02.json", 0)
    var ld: MapDestruction = late.get_node("Destruction")
    ld.apply_broken(hd.broken_ids())
    check(ld.broken_ids() == hd.broken_ids() and ld.covers.keys() == hd.covers.keys(), "late joiner matches host")
    host.free()
    late.free()

func test_ids_deterministic() -> void:
    for f in MAPS:
        var a := _build(f)
        var b := _build(f)
        var pa: Array = []
        var pb: Array = []
        for id in a.get_node("Destruction").covers:
            pa.append([id, a.get_node("Destruction").covers[id].position])
        for id in b.get_node("Destruction").covers:
            pb.append([id, b.get_node("Destruction").covers[id].position])
        check(pa == pb and not pa.is_empty(), "%s ids/positions identical across builds" % f)
        a.free()
        b.free()

func test_low_quality_covers_work() -> void:
    var m := MapLoader.build("res://src/maps/arena02.json", {"low_quality": true})
    var ds: MapDestruction = m.get_node("Destruction")
    ds.authority_override = 1
    var n := ds.covers.size()
    check(n >= 2, "low_quality keeps destructible covers")
    ds.covers[ds.covers.keys()[0]].apply_damage(9999.0)
    check(ds.covers.size() == n - 1, "breaks in low quality")
    m.free()

func test_default_authority_offline() -> void:
    var m := MapLoader.build("res://src/maps/arena01.json", {"low_quality": true})
    check(m.get_node("Destruction").is_authority(), "offline (no Net / Net offline) = authority")
    m.free()
