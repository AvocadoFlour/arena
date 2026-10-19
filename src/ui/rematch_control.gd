class_name RematchControl
extends RefCounted
## Match-end adapter: which end-screen buttons apply, and the online rematch hook.
## Offline: "Play again" (MatchEndScreen.play_again -> main.gd reloads straight into a match).
## Online host: "Rematch" for everyone through the core hook `rematch()` on the composition root (main.gd) when it
## exists (requested in docs/requests/ui.md); until then the button is disabled with a note (graceful fallback).
## Online client: "Leave" (MatchEndScreen.main_menu -> main.gd closes Net and returns to the menu).
var root: Object   ## composition root (main.gd) or a test mock
var net: Object    ## Net autoload or a mock with is_online() / is_host() / is_client()

func _init(root_node: Object = null, net_obj: Object = null) -> void:
    root = root_node
    net = net_obj

func online() -> bool:
    return net != null and net.has_method("is_online") and net.is_online()

func is_client() -> bool:
    return online() and net.has_method("is_client") and net.is_client()

func is_host() -> bool:
    return online() and not is_client()

## Online host: is the core rematch hook there?
func available() -> bool:
    return root != null and is_instance_valid(root) and root.has_method("rematch")

## Host: start a rematch for everyone. False (no-op) if the hook is missing or we are not the host.
func start() -> bool:
    if not is_host() or not available():
        return false
    root.rematch()
    return true
