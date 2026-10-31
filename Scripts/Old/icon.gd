extends Sprite3D

const SPEED = 4
var counterClockwise

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_left"):
		counterClockwise = true
	elif Input.is_action_just_pressed("ui_right"):
		counterClockwise = false
	
	if counterClockwise:
		rotate_y(deg_to_rad(SPEED))
	else:
		rotate_y(deg_to_rad(-SPEED))
