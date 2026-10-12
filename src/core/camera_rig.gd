class_name CameraRig
extends Node3D
## Over-the-shoulder camera. Child of the Hero (inherits yaw); applies pitch.
## SpringArm3D pulls the camera in when geometry is between hero and camera.

var hero
var arm: SpringArm3D
var cam: Camera3D

func setup(h) -> void:
    hero = h
    position = Vector3(0, 1.55, 0)
    arm = SpringArm3D.new()
    arm.spring_length = 3.2
    arm.margin = 0.08
    var s := SphereShape3D.new()
    s.radius = 0.25
    arm.shape = s
    arm.position = Vector3(0.7, 0.15, 0)
    add_child(arm)
    arm.add_excluded_object(h.get_rid())
    cam = Camera3D.new()
    cam.fov = Settings.fov   # base FOV comes from Settings (UI applies changes); any future zoom/sprint FOV must start from it
    cam.near = 0.05
    arm.add_child(cam)
    cam.current = true

func _process(_dt: float) -> void:
    if hero:
        rotation.x = hero.pitch
