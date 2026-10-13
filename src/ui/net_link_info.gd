class_name NetLinkInfo
extends RefCounted
## Read-only connection info for the HUD, using only the documented Net interface (INTERFACES §10).
## `src` defaults to the Net autoload; tests pass a mock with the same members.
## Not yet in Net (requested in docs/requests/ui.md): `ping_ms() -> int` and `last_packet_age() -> float`
## (seconds since the last packet/snapshot from the host). Until they exist both report -1 (unknown).
var src: Object

func _init(s: Object = null) -> void:
    src = s if s != null else Engine.get_main_loop().root.get_node_or_null("Net")

func online() -> bool:
    return src != null and src.has_method("is_online") and src.is_online()

func is_client() -> bool:
    return src != null and src.has_method("is_client") and src.is_client()

## Round-trip time in ms, or -1 when Net doesn't expose it.
func ping_ms() -> int:
    return int(src.ping_ms()) if src != null and src.has_method("ping_ms") else -1

## Seconds since the last packet from the other side, or -1 when unknown.
func last_packet_age() -> float:
    return float(src.last_packet_age()) if src != null and src.has_method("last_packet_age") else -1.0
