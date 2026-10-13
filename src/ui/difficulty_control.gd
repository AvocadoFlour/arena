class_name DifficultyControl
extends RefCounted
## Adapter for bot difficulty (easy / normal / hard) per team. Spec of the missing hooks: docs/requests/ui.md
## "Bot difficulty hook spec". Everything is checked with has_method / "in" first, so missing hooks
## mean "not available" and do nothing.
## Pre-match (GameConfig, INTERFACES §8): per-team `set_team_difficulty(team, level)` when core adds it;
##   until then only the existing global `GameConfig.bot_difficulty` exists, which UI drives from the
##   enemy-team (1) choice; the own-team (0) choice is saved but reported unavailable.
## Live (composition root main.gd, host/offline): `match_bot_difficulty()`, `set_bot_difficulty(team, level)`,
##   signal `bot_difficulty_changed(team, level)`. Clients can never set it.
signal changed

const LEVELS := ["easy", "normal", "hard"]
const LABELS := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
var cfg: Object   ## GameConfig (or a mock)
var src: Object   ## composition root (or a mock); null in the main menu
var net: Object

func _init(c: Object = null, s: Object = null, n: Object = null) -> void:
    var root: Node = Engine.get_main_loop().root
    cfg = c if c != null else root.get_node_or_null("GameConfig")
    src = s
    net = n if n != null else root.get_node_or_null("Net")
    if src != null and src.has_signal("bot_difficulty_changed"):
        src.connect("bot_difficulty_changed", func(_t = null, _l = null): changed.emit())

static func valid(level: String) -> bool:
    return LEVELS.has(level)

func is_client() -> bool:
    return net != null and net.has_method("is_client") and net.is_client()

# --- pre-match --------------------------------------------------------------------------
func per_team_prematch() -> bool:
    return cfg != null and cfg.has_method("set_team_difficulty")

func prematch_available(team: int) -> bool:
    if cfg == null:
        return false
    return per_team_prematch() or (team == 1 and "bot_difficulty" in cfg)

func apply_prematch(team: int, level: String) -> bool:
    if not valid(level) or not prematch_available(team):
        return false
    if per_team_prematch():
        return bool(cfg.set_team_difficulty(team, level))
    cfg.bot_difficulty = level
    return true

# --- live (in match) -----------------------------------------------------------------------
func live_available() -> bool:
    return src != null and is_instance_valid(src) and src.has_method("match_bot_difficulty") and src.has_method("set_bot_difficulty")

func can_set_live() -> bool:
    return live_available() and not is_client()

## {0: level, 1: level}; empty when the hook is missing.
func live_levels() -> Dictionary:
    return src.match_bot_difficulty() if live_available() else {}

func set_live(team: int, level: String) -> bool:
    if not valid(level) or not can_set_live():
        return false
    return bool(src.set_bot_difficulty(team, level))
