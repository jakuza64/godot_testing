class_name Player
extends CharacterBody3D

const SPEED = 6.0
const JUMP_VELOCITY = 4.5
const SPEED_FALLOFF = 0.05
const MOUSE_SENSITIVITY = 0.0025  # radians per pixel of mouse movement
const MAX_PITCH_DEGREES = 89.0

@onready var head: Node3D = $Head


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			_look(event as InputEventMouseMotion)
		elif event.is_action_pressed("ui_cancel"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _look(motion: InputEventMouseMotion) -> void:
	# Yaw turns the whole body; pitch tilts only the head.
	rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
	var pitch_limit := deg_to_rad(MAX_PITCH_DEGREES)
	head.rotation.x = clampf(
		head.rotation.x - motion.relative.y * MOUSE_SENSITIVITY,
		-pitch_limit,
		pitch_limit
	)


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Move relative to where the player is facing (forward is -Z).
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * SPEED_FALLOFF)
		velocity.z = move_toward(velocity.z, 0, SPEED * SPEED_FALLOFF)

	move_and_slide()
