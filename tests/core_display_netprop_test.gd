extends "res://tests/test_base.gd"
## HeroModel.create_display (display-only hero) + Net.make_prop visual hook (R9).

func test_create_display_every_hero() -> void:
    for hid in GameConfig.hero_ids():
        var n := HeroModel.create_display(hid)
        check(n != null, "%s display built" % hid)
        if n == null:
            continue
        check(n.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s display has no physics bodies" % hid)
        check(n.find_children("*", "MeshInstance3D", true, false).size() > 0, "%s display has meshes" % hid)
        check(not n is Hero, "%s display is not a Hero" % hid)
        n.free()
    check(HeroModel.create_display("no_such_hero") == null, "unknown id -> null")

func test_make_prop_fallback_and_visual() -> void:
    var w := Net.make_prop("wall", Vector3(4, 2, 0.3), Color.RED, "")
    check(w is StaticBody3D, "plain wall is a body")
    w.free()
    var s := Net.make_prop("shot", Vector3.ONE * 0.2, Color.RED, "res://does/not/exist.tscn")
    check(s is MeshInstance3D, "bad visual -> plain sphere")
    s.free()
    var ps := PackedScene.new()
    var root := Node3D.new()
    root.name = "FancyShot"
    ps.pack(root)
    root.free()
    ResourceSaver.save(ps, "user://_fancy_shot.tscn")
    var v := Net.make_prop("shot", Vector3.ONE * 0.2, Color.RED, "user://_fancy_shot.tscn")
    check(v != null and v.name == "FancyShot", "scene visual used for shots")
    v.free()
    var vw := Net.make_prop("wall", Vector3(4, 2, 0.3), Color.RED, "user://_fancy_shot.tscn")
    check(vw is StaticBody3D and vw.get_node_or_null("FancyShot") != null and vw.find_children("*", "CollisionShape3D", true, false).size() == 1, "wall visual keeps collision box")
    vw.free()

func test_prop_info() -> void:
    var n := Node3D.new()
    n.set_meta("net_kind", "shot")
    n.set_meta("net_visual", "res://x.tscn")
    var i := Net.prop_info(n, 7)
    check(i.id == 7 and i.kind == "shot" and i.visual == "res://x.tscn", "prop_info carries visual id")
    n.free()

func test_damage_event_src_pos_survives_encode() -> void:
    var ev := {"source": null, "target": null, "amount": 5.0, "pos": Vector3(1, 1, 1), "src_pos": Vector3(4, 0, -2)}
    var dec: Array = Net.decode(Net.encode([ev]))
    check(dec[0].src_pos == Vector3(4, 0, -2), "damage_dealt src_pos replicates (R10)")

func test_map_object_events_replicated() -> void:
    check(Events.has_signal("pickup_changed") and Events.has_signal("pad_launched"), "Events has pickup_changed / pad_launched")
    check(Net.EVENT_SIGNALS.get("pickup_changed") == 1 and Net.EVENT_SIGNALS.get("pad_launched") == 1, "both in EVENT_SIGNALS")
    check(not ("pickup_changed" in Net.UNRELIABLE_EVENTS) and not ("pad_launched" in Net.UNRELIABLE_EVENTS), "both reliable")
    check(Net.predict_pad(Vector3.ZERO, Vector3(1, 0, 0)) == Vector3(1, 0, 0), "predict_pad without a map is identity")
