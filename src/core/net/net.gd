extends Node
## Networking (autoload "Net"). Host-authoritative, Godot high-level multiplayer over ENet.
## Contract: docs/INTERFACES.md §10.
##   OFFLINE: single player, everything local (default, unchanged behaviour).
##   HOST:    simulates everything; receives client inputs; broadcasts snapshots (20 Hz), events, FX.
##   CLIENT:  sends inputs; predicts its own movement (reconciled); interpolates everyone else.

const DEFAULT_PORT := 24565
const MAX_HUMANS := 6
const SNAP_EVERY := 3            ## physics ticks between snapshots (60 / 3 = 20 Hz)
const INTERP_DELAY := 0.1        ## s, remote heroes are rendered this far in the past
const HISTORY := 60              ## ticks of position history for lag compensation (1 s)
const RECONCILE_EPS := 0.15      ## m, prediction error tolerated before replaying inputs
const EVENT_SIGNALS := {"damage_dealt": 1, "killed": 1, "respawned": 1, "ability_used": 3,
    "capture_progress": 1, "capture_completed": 1, "match_score": 1, "match_ended": 1}
const UNRELIABLE_EVENTS := ["capture_progress", "match_score"]
const SLOTS := ["ability1", "ability2", "ultimate"]
enum { OFFLINE, HOST, CLIENT }

signal welcomed(info: Dictionary)
signal hero_spawned(info: Dictionary)
signal hero_despawned(net_id: int)
signal peer_count_changed(n: int)
signal disconnected(reason: String)
signal public_ip_ready(ip: String)

var mode := OFFLINE
var port := DEFAULT_PORT
var tick := 0
var world = null                 ## composition root (src/main.gd): spawns heroes for peers
var entities := {}               ## net_id -> Node (heroes, props)
var _next_id := 1
var peers := {}                  ## HOST: peer_id -> {hero: Hero, name}
var history := {}                ## HOST: tick -> {net_id: Vector3}
var snap_log: Array = []         ## HOST: [[tick, {net_id: hp}]] recent (tests)
var my_net_id := -1              ## CLIENT: our hero
var server_tick := 0             ## CLIENT: newest snapshot tick
var last_snap_hp := {}           ## CLIENT: {net_id: hp} of newest snapshot
var reconciles := 0              ## CLIENT: corrections applied
var max_correction := 0.0       ## CLIENT: largest prediction error (m), respawn/teleport snaps excluded
var teleports := 0               ## CLIENT: respawn snaps (not counted as corrections)
var max_teleport := 0.0
var big_corrections: Array = []  ## CLIENT: [tick, err] for errors > 2 m (diagnostics, net test)
var public_ip := ""
## Skip all internet lookups (api.ipify.org). Set by tests, or `-- --net_offline`; headless runs default to it.
var offline := DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--net_offline")
var _clock_offset := 0.0
var _clock_init := false
var _interp := {}                ## CLIENT: net_id -> [[t, pos, yaw, pitch]]
var _props := {}                 ## CLIENT: net_id -> Node3D

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    for s in EVENT_SIGNALS:
        if EVENT_SIGNALS[s] == 3:
            Events.connect(s, func(a, b, c): _on_event(s, [a, b, c]))
        else:
            Events.connect(s, func(a): _on_event(s, [a]))
    Events.respawned.connect(func(h): if mode == HOST and h.input_source is RemoteInput: h.input_source.queue.clear())
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(func(): _fail("could not connect"))
    multiplayer.server_disconnected.connect(func(): _fail("host closed the connection"))

# ---------------------------------------------------------------- roles
func is_authority() -> bool:
    return mode != CLIENT

func is_host() -> bool:
    return mode == HOST

func is_client() -> bool:
    return mode == CLIENT

func is_online() -> bool:
    return mode != OFFLINE

func host(p: int = DEFAULT_PORT) -> int:
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(p, MAX_HUMANS - 1)
    if err != OK:
        return err
    multiplayer.multiplayer_peer = peer
    mode = HOST
    port = p
    return OK

func join(address: String, p: int = DEFAULT_PORT) -> int:
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_client(address, p)
    if err != OK:
        return err
    multiplayer.multiplayer_peer = peer
    mode = CLIENT
    port = p
    return OK

func close() -> void:
    if multiplayer.multiplayer_peer:
        multiplayer.multiplayer_peer.close()
    multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
    mode = OFFLINE
    entities.clear()
    peers.clear()
    history.clear()
    _interp.clear()
    _props.clear()
    my_net_id = -1
    server_tick = 0
    _clock_init = false

func _fail(reason: String) -> void:
    print("NET disconnected: ", reason)
    disconnected.emit(reason)

## Looks up the public IP for the host screen (HTTPS GET to api.ipify.org).
func fetch_public_ip() -> void:
    if offline:
        public_ip = ""
        public_ip_ready.emit.call_deferred("")
        return
    var req := HTTPRequest.new()
    req.timeout = 6.0
    add_child(req)
    req.request_completed.connect(func(result, code, _h, body):
        public_ip = body.get_string_from_utf8().strip_edges() if result == HTTPRequest.RESULT_SUCCESS and code == 200 else ""
        public_ip_ready.emit(public_ip)
        req.queue_free())
    if req.request("https://api.ipify.org") != OK:
        public_ip_ready.emit("")

static func lan_addresses() -> Array:
    var out: Array = []
    for a in IP.get_local_addresses():
        if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
            out.append(a)
    return out

# ---------------------------------------------------------------- registry
## HOST/OFFLINE: assigns a network id to a hero or prop.
func register(n: Node) -> int:
    if n.has_meta("net_id"):
        return int(n.get_meta("net_id"))
    var id := _next_id
    _next_id += 1
    register_as(n, id)
    return id

func register_as(n: Node, id: int) -> void:
    n.set_meta("net_id", id)
    if "net_id" in n:
        n.net_id = id
    entities[id] = n
    n.tree_exiting.connect(func(): if entities.get(id) == n: entities.erase(id))

func hero_info(h) -> Dictionary:
    return {"id": h.net_id, "hero_id": String(h.def.get("id", "")), "team": h.team,
        "name": String(h.get_meta("net_name", h.display_name)), "pos": h.global_position, "yaw": h.yaw,
        "peer": int(h.get_meta("peer", 0))}

func heroes() -> Array:
    var out: Array = []
    for id in entities:
        var n = entities[id]
        if is_instance_valid(n) and n is Hero:
            out.append(n)
    return out

# ---------------------------------------------------------------- host: peers
func _on_peer_connected(pid: int) -> void:
    if mode == HOST:
        print("NET peer connected ", pid)

func _on_peer_disconnected(pid: int) -> void:
    if mode != HOST or not peers.has(pid):
        return
    var h = peers[pid].hero
    peers.erase(pid)
    print("NET peer left ", pid)
    if is_instance_valid(h):
        despawn(h)
    if world and world.has_method("net_peer_left"):
        world.net_peer_left(pid)
    peer_count_changed.emit(peers.size())

## HOST: sends to every welcomed peer (peers that connected but have not said hello get nothing).
func _bcast(method: String, a: Array) -> void:
    for pid in peers:
        callv("rpc_id", [pid, method] + a)

## HOST: removes a networked node everywhere.
func despawn(n: Node) -> void:
    var id := int(n.get_meta("net_id", -1))
    n.queue_free()
    if mode == HOST and id >= 0:
        _bcast("_s_despawn", [id])

@rpc("any_peer", "reliable")
func _c_hello(hero_id: String, pname: String) -> void:
    if mode != HOST:
        return
    var pid := multiplayer.get_remote_sender_id()
    if peers.size() >= MAX_HUMANS - 1 or world == null or not world.has_method("net_spawn_human"):
        rpc_id(pid, "_s_reject", "server full")
        return
    var h = world.net_spawn_human(pid, hero_id, pname.left(16))
    peers[pid] = {"hero": h, "name": pname}
    var list: Array = []
    for x in heroes():
        list.append(hero_info(x))
    rpc_id(pid, "_s_welcome", {"map_id": GameConfig.map_id, "you": h.net_id, "tick": tick, "heroes": list})
    for other in peers:
        if other != pid:
            rpc_id(other, "_s_spawn", hero_info(h))
    peer_count_changed.emit(peers.size())

## HOST: announce a hero spawned after clients joined (e.g. re-filled bot).
func broadcast_spawn(h) -> void:
    if mode == HOST:
        _bcast("_s_spawn", [hero_info(h)])

@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _c_input(pkt: Array) -> void:
    if mode != HOST:
        return
    var pid := multiplayer.get_remote_sender_id()
    if peers.has(pid) and is_instance_valid(peers[pid].hero) and peers[pid].hero.input_source is RemoteInput:
        peers[pid].hero.input_source.push(pkt)

# ---------------------------------------------------------------- client: session
func _on_connected() -> void:
    rpc_id(1, "_c_hello", GameConfig.hero_id, String(GameConfig.get("player_name") if GameConfig.get("player_name") else "Player"))

@rpc("authority", "reliable")
func _s_reject(reason: String) -> void:
    _fail(reason)

@rpc("authority", "reliable")
func _s_welcome(info: Dictionary) -> void:
    my_net_id = int(info.you)
    server_tick = int(info.tick)
    tick = server_tick
    GameConfig.map_id = String(info.map_id)
    welcomed.emit(info)

@rpc("authority", "reliable")
func _s_spawn(info: Dictionary) -> void:
    if not entities.has(int(info.id)):
        hero_spawned.emit(info)

@rpc("authority", "reliable")
func _s_despawn(id: int) -> void:
    var n = entities.get(id)
    entities.erase(id)
    _interp.erase(id)
    if is_instance_valid(n):
        n.queue_free()
    hero_despawned.emit(id)

func send_input(pkt: Array) -> void:
    if mode == CLIENT:
        rpc_id(1, "_c_input", pkt)

# ---------------------------------------------------------------- events + fx replication
func _on_event(sig: String, args: Array) -> void:
    if mode != HOST:
        return
    var enc = encode(args)
    if sig in UNRELIABLE_EVENTS:
        _bcast("_s_event_u", [sig, enc])
    else:
        _bcast("_s_event", [sig, enc])

@rpc("authority", "reliable")
func _s_event(sig: String, args: Array) -> void:
    _emit_local(sig, args)

@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _s_event_u(sig: String, args: Array) -> void:
    _emit_local(sig, args)

func _emit_local(sig: String, args: Array) -> void:
    if mode != CLIENT:
        return
    Events.callv("emit_signal", [sig] + decode(args))

## Called by Fx on the host; clients replay the effect.
func send_fx(kind: String, args: Array) -> void:
    if mode == HOST:
        _bcast("_s_fx", [kind, args])

@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _s_fx(kind: String, args: Array) -> void:
    if mode != CLIENT or world == null:
        return
    match kind:
        "tracer": Fx.tracer(world, args[0], args[1], args[2])
        "ring": Fx.ring(world, args[0], args[1], args[2], args[3])

## Hero/prop references -> {"__h": net_id} (recursively), so payloads cross the wire.
func encode(v):
    if v is Object:
        return {"__h": int(v.get_meta("net_id"))} if is_instance_valid(v) and v.has_meta("net_id") else null
    if v is Dictionary:
        var d := {}
        for k in v:
            d[k] = encode(v[k])
        return d
    if v is Array:
        return v.map(func(x): return encode(x))
    return v

func decode(v):
    if v is Dictionary:
        if v.size() == 1 and v.has("__h"):
            var n = entities.get(int(v.__h))
            return n if is_instance_valid(n) else null
        var d := {}
        for k in v:
            d[k] = decode(v[k])
        return d
    if v is Array:
        return v.map(func(x): return decode(x))
    return v

# ---------------------------------------------------------------- lag compensation
## HOST: moves every other hero back to where `shooter`'s client saw it. Returns state for restore().
func rewind_for(shooter) -> Dictionary:
    if mode != HOST or not (shooter.input_source is RemoteInput):
        return {}
    var vt: int = clampi(shooter.input_source.view_tick, tick - HISTORY + 1, tick)
    return rewind_to(vt, shooter)

func rewind_to(vt: int, shooter) -> Dictionary:
    var past: Dictionary = history.get(vt, {})
    var saved := {}
    for h in heroes():
        if h == shooter or h.dead or not past.has(h.net_id):
            continue
        saved[h] = h.global_position
        h.global_position = past[h.net_id]
    return saved

func restore(saved: Dictionary) -> void:
    for h in saved:
        if is_instance_valid(h):
            h.global_position = saved[h]

# ---------------------------------------------------------------- tick
func _physics_process(_dt: float) -> void:
    tick += 1
    if mode == OFFLINE:
        return
    if mode == HOST:
        var pos := {}
        for h in heroes():
            pos[h.net_id] = h.global_position
        history[tick] = pos
        history.erase(tick - HISTORY)
        if tick % SNAP_EVERY == 0 and not peers.is_empty():
            _send_snapshot()

func _hero_state(h) -> Array:
    var cds: Array = []
    for s in SLOTS:
        cds.append(h.abilities[s].cooldown.remaining if h.abilities.has(s) else 0.0)
    var acked: int = h.input_source.acked if h.input_source is RemoteInput else -1
    return [h.net_id, h.global_position, h.velocity, h.yaw, h.pitch, h.health.hp, h.dead, h.visible,
        h.weapon.ammo, h.weapon.reloading(), h.ult.charge, cds, h.overheal, h.respawn_left, acked, h.team,
        h.combo_step, h.dash_time]

func _send_snapshot() -> void:
    var hs: Array = []
    var hp := {}
    for h in heroes():
        hs.append(_hero_state(h))
        hp[h.net_id] = h.health.hp
    var props: Array = []
    for p in get_tree().get_nodes_in_group("net_props"):
        if not is_instance_valid(p) or p.is_queued_for_deletion():
            continue
        var id := register(p)
        props.append([id, String(p.get_meta("net_kind", "")), p.global_position, p.global_rotation.y,
            p.get_meta("net_size", Vector3.ONE * 0.3), p.get_meta("net_color", Color.WHITE)])
    snap_log.append([tick, hp])
    while snap_log.size() > 400:
        snap_log.pop_front()
    _bcast("_s_snap", [tick, hs, props])

@rpc("authority", "unreliable_ordered", "call_remote", 1)
func _s_snap(t: int, hs: Array, props: Array) -> void:
    if mode != CLIENT or t <= server_tick:
        return
    server_tick = t
    var now := Time.get_ticks_msec() / 1000.0
    var off := now - float(t) / Engine.physics_ticks_per_second
    if not _clock_init or off < _clock_offset:
        _clock_offset = off
        _clock_init = true
    else:
        _clock_offset = lerpf(_clock_offset, off, 0.02)
    last_snap_hp = {}
    for s in hs:
        var h = entities.get(int(s[0]))
        if not is_instance_valid(h):
            continue
        _apply_state(h, s)
        last_snap_hp[int(s[0])] = float(s[5])
        if int(s[0]) == my_net_id:
            _reconcile(h, s)
        else:
            var buf: Array = _interp.get(int(s[0]), [])
            buf.append([float(t) / Engine.physics_ticks_per_second, s[1], float(s[3]), float(s[4])])
            while buf.size() > 30:
                buf.pop_front()
            _interp[int(s[0])] = buf
    _sync_props(props)

func _apply_state(h, s: Array) -> void:
    h.health.hp = float(s[5])
    var was_dead: bool = h.dead
    h.dead = bool(s[6])
    h.visible = bool(s[7])
    h.collision_layer = 0 if h.dead else 1
    h.weapon.ammo = int(s[8])
    h.weapon._reload_left = 0.01 if bool(s[9]) else 0.0
    h.ult.charge = float(s[10])
    for i in SLOTS.size():
        if h.abilities.has(SLOTS[i]):
            h.abilities[SLOTS[i]].cooldown.remaining = float(s[11][i])
    h.overheal = float(s[12])
    h.respawn_left = float(s[13])
    if s.size() > 17:   # visual-only (remote attack/dash animation)
        h.combo_step = int(s[16])
        h.dash_time = float(s[17])
    if h.team != int(s[15]):
        h.set_team(int(s[15]))
    if was_dead and not h.dead:
        if h.input_source is ClientInput:
            max_teleport = maxf(max_teleport, h.global_position.distance_to(s[1]))   # death spot -> spawn
        h.global_position = s[1]   # respawn teleport
        _interp.erase(h.net_id)
        if h.input_source is ClientInput:   # inputs sent before death predicted from the death spot: drop them
            h.input_source.pending.clear()
            h.input_source.respawn_seq = h.input_source.seq

## Own hero: drop acknowledged inputs; if our prediction at that input differs from the host, snap and replay.
func _reconcile(h, s: Array) -> void:
    var ci = h.input_source
    if not (ci is ClientInput):
        return
    var predicted = ci.ack(int(s[14]))
    var server_pos: Vector3 = s[1]
    if h.dead:
        h.global_position = server_pos
        return
    if ci.respawn_seq >= 0 and int(s[14]) <= ci.respawn_seq:
        # host is still acking pre-death inputs: the server position is the respawn point, not a prediction miss
        if predicted != null:
            max_teleport = maxf(max_teleport, (predicted as Vector3).distance_to(server_pos))
        teleports += 1
        h.global_position = server_pos
        return
    var err: float = INF if predicted == null else (predicted as Vector3).distance_to(server_pos)
    if err <= RECONCILE_EPS:
        return
    reconciles += 1
    if err < INF:
        max_correction = maxf(max_correction, err)
        if err > 2.0:
            big_corrections.append([server_tick, snappedf(err, 0.01)])
    h.global_position = server_pos
    h.velocity = s[2]
    var dt := 1.0 / Engine.physics_ticks_per_second
    for e in ci.pending:
        var wish := Basis(Vector3.UP, float(e.yaw)) * Vector3(e.move.x, 0, -e.move.y)
        h.velocity = Motion.step_velocity(h.velocity, wish, h.is_on_floor(), bool(e.jump), h.effective_move_cfg(), dt)
        h.move_and_slide()
        e.pos = h.global_position

func _sync_props(props: Array) -> void:
    var seen := {}
    for p in props:
        var id := int(p[0])
        seen[id] = true
        var n = _props.get(id)
        if not is_instance_valid(n):
            n = _make_prop(String(p[1]), p[4], p[5])
            if world == null:
                continue
            world.add_child(n)
            _props[id] = n
        n.global_position = p[2]
        n.rotation.y = float(p[3])
    for id in _props.keys():
        if not seen.has(id):
            if is_instance_valid(_props[id]):
                _props[id].queue_free()
            _props.erase(id)

static func _make_prop(kind: String, size: Vector3, color: Color) -> Node3D:
    var mi := MeshInstance3D.new()
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    if kind == "wall":
        var body := StaticBody3D.new()   # solid on the client too, so prediction collides with it
        var cs := CollisionShape3D.new()
        var bs := BoxShape3D.new()
        bs.size = size
        cs.shape = bs
        body.add_child(cs)
        var bm := BoxMesh.new()
        bm.size = size
        mi.mesh = bm
        m.albedo_color = Color(color.r, color.g, color.b, 0.45)
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mi.material_override = m
        body.add_child(mi)
        return body
    var sm := SphereMesh.new()
    sm.radius = size.x
    sm.height = size.x * 2.0
    mi.mesh = sm
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mi.material_override = m
    return mi

func _process(_dt: float) -> void:
    if mode != CLIENT or not _clock_init:
        return
    var rt := Time.get_ticks_msec() / 1000.0 - _clock_offset - INTERP_DELAY
    for id in _interp:
        var h = entities.get(id)
        var buf: Array = _interp[id]
        if not is_instance_valid(h) or buf.is_empty():
            continue
        var a = buf[0]
        var b = buf[-1]
        for i in range(buf.size() - 1):
            if float(buf[i][0]) <= rt and rt < float(buf[i + 1][0]):
                a = buf[i]
                b = buf[i + 1]
                break
        var w := 1.0
        if b != a and float(b[0]) > float(a[0]):
            w = clampf((rt - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
        elif rt < float(buf[0][0]):
            w = 0.0
            b = a
        var np: Vector3 = (a[1] as Vector3).lerp(b[1], w)
        if _dt > 0.0:
            h.velocity = (np - h.global_position) / _dt   # visual only: drives the Visual run/lean animation
        h.global_position = np
        h.yaw = lerp_angle(float(a[2]), float(b[2]), w)
        h.rotation.y = h.yaw
        h.pitch = lerpf(float(a[3]), float(b[3]), w)
