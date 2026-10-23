extends Node
## Graphics/input settings (autoload "Settings"), persisted to user://settings.cfg.
const PATH := "user://settings.cfg"
const MODES := ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
const RESOLUTIONS := [
    Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
    Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 800), Vector2i(1920, 1200),
    Vector2i(2560, 1080), Vector2i(3440, 1440),
]
var window_mode := "Windowed"
var resolution := Vector2i(1280, 720)
var sensitivity := 1.0
var skip_apply := false
## FOV (degrees) for the player camera; applied by UI to the current Camera3D (CameraRig default 75).
const FOV_MIN := 60.0
const FOV_MAX := 110.0
var fov := 75.0
## Match speed. 1 = normal, 0.75 = 75%. Applied as Engine.time_scale (movement, cooldowns, fire).
const SPEED_MIN := 0.5
const SPEED_MAX := 1.0
var game_speed := 1.0
## Volumes 0..1 per bus name. Applied to an AudioServer bus only if one with that name exists
## (today only "Master"); otherwise just persisted for when audio arrives.
const AUDIO_BUSES := ["Master", "Music", "SFX"]
var volumes := {"Master": 1.0, "Music": 0.8, "SFX": 1.0}
## Low-quality mode for other modules (Maps: fewer decorations/shadows, etc.). Read
## `Settings.low_quality`; connect `low_quality_changed(on)` to react live. Emitted only on change.
signal low_quality_changed(on: bool)
var low_quality := false
## HUD floating damage numbers (Settings page toggle "Damage numbers"), default on.
var damage_numbers := true
## First-time controls hint (ControlsHint): true once dismissed with "Don't show again" on.
## Settings > "Show controls hint" clears it.
var controls_hint_seen := false
var bot_difficulty := {0: "normal", 1: "normal"}   ## last pre-match bot difficulty per team (main menu)

func set_low_quality(on: bool) -> void:
    if on == low_quality:
        return
    low_quality = on
    low_quality_changed.emit(on)

var sfx: UiSfx   ## shared UI sound player (hit / kill / click / ready), SFX bus

func _ready() -> void:
    sfx = UiSfx.new()
    add_child(sfx)
    load_from(PATH)
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--screenshot") or a.begins_with("--smoke") or a.begins_with("--demo"):
            skip_apply = true
    Keybinds.load_saved()   # user key rebinds on top of Actions defaults
    if not skip_apply:
        apply()

func load_from(path: String) -> bool:
    var cfg := ConfigFile.new()
    if cfg.load(path) != OK:
        return false
    window_mode = cfg.get_value("video", "window_mode", window_mode)
    resolution = cfg.get_value("video", "resolution", resolution)
    sensitivity = cfg.get_value("input", "sensitivity", sensitivity)
    fov = clampf(float(cfg.get_value("video", "fov", fov)), FOV_MIN, FOV_MAX)
    game_speed = clampf(float(cfg.get_value("game", "speed", game_speed)), SPEED_MIN, SPEED_MAX)
    set_low_quality(bool(cfg.get_value("video", "low_quality", low_quality)))
    damage_numbers = bool(cfg.get_value("hud", "damage_numbers", damage_numbers))
    controls_hint_seen = bool(cfg.get_value("hud", "controls_hint_seen", controls_hint_seen))
    for t in [0, 1]:
        var lv := String(cfg.get_value("match", "bot_difficulty_%d" % t, bot_difficulty[t]))
        bot_difficulty[t] = lv if lv in ["easy", "normal", "hard"] else "normal"
    for b in AUDIO_BUSES:
        volumes[b] = clampf(float(cfg.get_value("audio", b, volumes[b])), 0.0, 1.0)
    return true

func save(path := PATH) -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("video", "window_mode", window_mode)
    cfg.set_value("video", "resolution", resolution)
    cfg.set_value("input", "sensitivity", sensitivity)
    cfg.set_value("video", "fov", fov)
    cfg.set_value("game", "speed", game_speed)
    cfg.set_value("video", "low_quality", low_quality)
    cfg.set_value("hud", "damage_numbers", damage_numbers)
    cfg.set_value("hud", "controls_hint_seen", controls_hint_seen)
    for t in [0, 1]:
        cfg.set_value("match", "bot_difficulty_%d" % t, bot_difficulty[t])
    for b in AUDIO_BUSES:
        cfg.set_value("audio", b, volumes[b])
    cfg.save(path)

## Windowed: resolution = window size. Fullscreen: desktop size; resolution sets 3D render scale.
func volume(bus: String) -> float:
    return volumes.get(bus, 1.0)

## Returns true if a real audio bus was changed (false = stored only).
func set_volume(bus: String, v: float) -> bool:
    volumes[bus] = clampf(v, 0.0, 1.0)
    var i := AudioServer.get_bus_index(bus)
    if i < 0:
        return false
    AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volumes[bus], 0.0001)))
    AudioServer.set_bus_mute(i, volumes[bus] <= 0.0)
    return true

func apply_audio() -> void:
    for b in AUDIO_BUSES:
        set_volume(b, volumes[b])

## Sets the camera FOV (view-only, not gameplay state). No-op without a camera.
func apply_fov(cam: Camera3D) -> void:
    if cam:
        cam.fov = clampf(fov, FOV_MIN, FOV_MAX)

func apply() -> void:
    Actions.mouse_sensitivity = 0.0025 * sensitivity
    apply_audio()
    Engine.time_scale = clampf(game_speed, SPEED_MIN, SPEED_MAX)
    if is_inside_tree():
        apply_fov(get_viewport().get_camera_3d())
    if DisplayServer.get_name() == "headless":
        return
    match window_mode:
        "Borderless Fullscreen":
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        "Exclusive Fullscreen":
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
        _:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
            DisplayServer.window_set_size(resolution)
            var scr := DisplayServer.window_get_current_screen()
            var pos := DisplayServer.screen_get_position(scr) + (DisplayServer.screen_get_size(scr) - resolution) / 2
            DisplayServer.window_set_position(pos)
    var vp := get_tree().root
    if window_mode == "Windowed":
        vp.scaling_3d_scale = 1.0
    else:
        var scr_size := DisplayServer.screen_get_size()
        vp.scaling_3d_scale = clampf(float(resolution.y) / float(max(1, scr_size.y)), 0.25, 1.0)
