class_name Player
extends CharacterBody3D

const SPEED = 6.0
const JUMP_VELOCITY = 4.5
const SPEED_FALLOFF = 0.05
const TURN_SPEED = 3.0  # radians per second

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	# Rotate with left/right.
	var turn := Input.get_axis("ui_right", "ui_left")
	rotate_y(turn * TURN_SPEED * delta)

	# Move forward/back relative to the player's facing.
	var move_input := Input.get_axis("ui_up", "ui_down")
	var direction := (transform.basis * Vector3(0, 0, move_input)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * SPEED_FALLOFF)
		velocity.z = move_toward(velocity.z, 0, SPEED * SPEED_FALLOFF)

	move_and_slide()
	
	#Move CameraController to position
	$CameraController.position = lerp($CameraController.position,position,0.1)
	$CameraController.rotation.y = lerp_angle($CameraController.rotation.y, rotation.y, 0.1)
