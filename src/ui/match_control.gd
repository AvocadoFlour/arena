class_name MatchControl
extends RefCounted
## Adapter between the Esc overlay's Match page and the match / Net hooks (spec: docs/requests/ui.md,
## "In-match controls hook spec"). `src` is the composition root (main.gd, the PauseMenu's parent);
## `net` defaults to the Net autoload. Every call checks has_method / has_signal first, so missing hooks
## just report "not available" and do nothing. Core can add them without UI changes.
signal swap_started(hero_id: String, delay: float)
signal swap_finished(hero_id: String)
signal swap_cancelled(reason: String)
signal state_changed

const MAX_BOTS := 5
var src: Object
var net: Object

func _init(s: Object = null, n: Object = null) -> void:
    src = s
    net = n if n != null else Engine.get_main_loop().root.get_node_or_null("Net")
    if src == null:
        return
    for pair in [["hero_swap_started", _on_started], ["hero_swap_finished", _on_finished],
            ["hero_swap_cancelled", _on_cancelled], ["bot_counts_changed", _on_state], ["team_changed", _on_state]]:
        if src.has_signal(pair[0]) and not src.is_connected(pair[0], pair[1]):
            src.connect(pair[0], pair[1])

func _has(m: String) -> bool:
    return src != null and is_instance_valid(src) and src.has_method(m)

func online() -> bool:
    return net != null and net.has_method("is_online") and net.is_online()

func is_client() -> bool:
    return net != null and net.has_method("is_client") and net.is_client()

## Offline and host may change bots; clients never.
func can_set_bots() -> bool:
    return not is_client()

func bots_available() -> bool:
    return _has("match_bot_counts") and _has("set_bot_count")

func hero_available() -> bool:
    return _has("request_hero_change")

func team_available() -> bool:
    return _has("request_team_change")

## {0: n, 1: n}; empty when the hook is missing.
func bot_counts() -> Dictionary:
    return src.match_bot_counts() if _has("match_bot_counts") else {}

func set_bot_count(team: int, n: int) -> bool:
    if not bots_available() or not can_set_bots():
        return false
    return bool(src.set_bot_count(team, clampi(n, 0, MAX_BOTS)))

func request_hero(hero_id: String) -> bool:
    return bool(src.request_hero_change(hero_id)) if hero_available() else false

func request_team(team: int) -> bool:
    return bool(src.request_team_change(team)) if team_available() else false

## Local player's team, or -1 when unknown.
func local_team() -> int:
    return int(src.local_team()) if _has("local_team") else -1

## Local player's net id, or -1 (then swap events are not filtered).
func local_net_id() -> int:
    return int(src.local_net_id()) if _has("local_net_id") else -1

func _mine(net_id: int) -> bool:
    var me := local_net_id()
    return me < 0 or net_id == me

func _on_started(net_id: int, hero_id: String, delay: float) -> void:
    if _mine(net_id):
        swap_started.emit(hero_id, delay)

func _on_finished(net_id: int, hero_id: String) -> void:
    if _mine(net_id):
        swap_finished.emit(hero_id)

func _on_cancelled(net_id: int, reason: String) -> void:
    if _mine(net_id):
        swap_cancelled.emit(reason)

func _on_state(_a = null, _b = null) -> void:
    state_changed.emit()
