class_name MockCaptureSource
extends Node
## Stand-in for the Maps capture-point publisher until Events carries the real signals.
## Same signal shapes as proposed in docs/requests/ui.md. step(dt) advances one zone toward capture.
signal capture_progress(ev: Dictionary)
signal capture_completed(ev: Dictionary)
var zone_id := "A"
var team := 0
var rate := 0.25   ## progress per second
var progress := 0.0
var contested := false

func step(dt: float) -> void:
    if progress >= 1.0:
        return
    if not contested:
        progress = minf(1.0, progress + rate * dt)
    capture_progress.emit({"zone_id": zone_id, "team": team, "progress": progress, "contested": contested})
    if progress >= 1.0:
        capture_completed.emit({"zone_id": zone_id, "team": team})
