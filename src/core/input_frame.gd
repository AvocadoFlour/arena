class_name InputFrame
extends RefCounted
## One tick of intent for a Hero. Produced by ANY input source
## (keyboard/mouse, future touch, bot AI, network). See INTERFACES.md section 1.

var move := Vector2.ZERO   ## x = strafe right, y = forward. Length <= 1.
var look := Vector2.ZERO   ## radians this tick: x = yaw delta (+ = turn left), y = pitch delta (+ = up)
var fire := false          ## held
var jump := false          ## edge (pressed this tick)
var reload := false        ## edge
var ability1 := false      ## edge (Kestrel: dash)
var ability2 := false      ## edge (Kestrel: ground slam)
var ultimate := false      ## edge
