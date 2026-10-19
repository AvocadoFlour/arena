extends Node3D
## Replicated "who rides whom" link for the ride ability (net-prop visual hook, INTERFACES §10).
## kind = "mount:<rider net id>:<victim net id>". On the host the ride ability owns the node (and sets
## local_rider/local_victim); on clients Net builds it from the prop spawn via build_prop(). While it is in the
## tree it registers rider -> victim in a static table read by Hero.mounted_on(); leaving the tree (prop
## despawned when the ride ends) unregisters. Invisible: the rider's own model shows the ride.
const PATH := "res://src/abilities/mount_link.gd"
static var _links := {}        ## rider net id -> victim net id (clients and host)
static var _local := {}        ## rider instance id -> victim node (host / offline, works without net ids)
var rider_id := -1
var victim_id := -1
var local_rider = null
var local_victim = null

static func kind_for(rider, victim) -> String:
    return "mount:%d:%d" % [int(rider.net_id), int(victim.net_id)]

static func build_prop(kind: String, _size: Vector3, _color: Color) -> Node3D:
    var n = load(PATH).new()
    n.name = "MountLink"
    var parts := kind.split(":")
    if parts.size() == 3 and parts[0] == "mount":
        n.rider_id = int(parts[1])
        n.victim_id = int(parts[2])
    return n

func _enter_tree() -> void:
    if rider_id >= 0 and victim_id >= 0:
        _links[rider_id] = victim_id
    if local_rider != null:
        _local[local_rider.get_instance_id()] = local_victim

func _exit_tree() -> void:
    if rider_id >= 0 and _links.get(rider_id, -2) == victim_id:
        _links.erase(rider_id)
    if local_rider != null and is_instance_valid(local_rider) and _local.get(local_rider.get_instance_id()) == local_victim:
        _local.erase(local_rider.get_instance_id())

## Victim net id for a rider net id (-1 = not riding).
static func victim_id_of(rider_net_id: int) -> int:
    return int(_links.get(rider_net_id, -1))

## Victim node of `rider` (host: the local table; clients: net ids through Net.entities). null = not riding.
static func victim_of(rider):
    var v = _local.get(rider.get_instance_id())
    if v != null and is_instance_valid(v):
        return v
    if int(rider.net_id) < 0:
        return null
    var vid := victim_id_of(int(rider.net_id))
    if vid < 0:
        return null
    var n = Net.entities.get(vid)
    return n if is_instance_valid(n) else null
