class_name UiSfx
extends Node
## UI/feedback sounds, synthesised at runtime (no audio assets, so no licences). Plays on the "SFX"
## bus. Owned by the Settings autoload (`Settings.sfx`), so menus and HUD share one instance.
## Sounds: hit (hit marker), kill (kill confirm), click (menu button), ready (ability ready).
const RATE := 22050
const BUS := "SFX"
const POOL := 6
## Shortest gap between two plays of the same sound (rapid fire must not stack into noise).
const MIN_GAP := {"hit": 0.045, "kill": 0.08, "click": 0.03, "ready": 0.1}
## name -> [segments]; segment = [freq_start, freq_end, seconds, volume]; square-ish tones with decay.
const SPECS := {
    "hit":   [[1900.0, 1500.0, 0.035, 0.55]],
    "kill":  [[880.0, 880.0, 0.06, 0.6], [1320.0, 1760.0, 0.12, 0.65]],
    "click": [[1200.0, 900.0, 0.022, 0.4]],
    "ready": [[660.0, 660.0, 0.07, 0.45], [990.0, 990.0, 0.13, 0.5]],
}
var streams := {}
var players: Array = []
var last_play := {}
var play_count := {}   ## name -> times actually played (tests / debugging)
var _next := 0

static func synth(segments: Array) -> AudioStreamWAV:
    var data := PackedByteArray()
    for seg in segments:
        var n := int(RATE * float(seg[2]))
        var phase := 0.0
        for i in n:
            var t: float = float(i) / max(1, n - 1)
            var f: float = lerpf(seg[0], seg[1], t)
            phase += f / RATE
            var s: float = sin(TAU * phase) * 0.7 + (0.3 if fmod(phase, 1.0) < 0.5 else -0.3)
            var env: float = minf(1.0, float(i) / (RATE * 0.002)) * pow(1.0 - t, 2.0)   # 2 ms attack, decay
            var v := int(clampf(s * env * float(seg[3]), -1.0, 1.0) * 32767.0)
            data.append(v & 0xFF)
            data.append((v >> 8) & 0xFF)
    var w := AudioStreamWAV.new()
    w.format = AudioStreamWAV.FORMAT_16_BITS
    w.mix_rate = RATE
    w.stereo = false
    w.data = data
    return w

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS   # menu clicks while paused
    for k in SPECS:
        streams[k] = synth(SPECS[k])
    for i in POOL:
        var p := AudioStreamPlayer.new()
        p.bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else "Master"
        add_child(p)
        players.append(p)

## Returns true if the sound started (false: unknown name or rate-limited).
func play(sound: String) -> bool:
    if not streams.has(sound) or players.is_empty():
        return false
    var now := Time.get_ticks_msec() / 1000.0
    if now - float(last_play.get(sound, -10.0)) < float(MIN_GAP.get(sound, 0.0)):
        return false
    last_play[sound] = now
    var p: AudioStreamPlayer = players[_next]
    _next = (_next + 1) % players.size()
    p.stream = streams[sound]
    p.play()
    play_count[sound] = int(play_count.get(sound, 0)) + 1
    return true
