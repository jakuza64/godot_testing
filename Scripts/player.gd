class_name Player
extends CharacterBody3D

const SPEED = 6.0
const JUMP_VELOCITY = 4.5
const SPEED_FALLOFF = 0.05
const MOUSE_SENSITIVITY = 0.0025  # radians per pixel of mouse movement
const MAX_PITCH_DEGREES = 89.0

## Placeholder until respawning is designed: reload the scene after dying.
@export var reload_scene_on_death := true
@export var respawn_delay := 3.0

@onready var head: Node3D = $Head
@onready var health: HealthComponent = $HealthComponent


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)


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

	# A dead player still falls and slides to a stop, but gets no input.
	var alive := health.is_alive

	# Handle jump.
	if alive and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Move relative to where the player is facing (forward is -Z).
	var input_dir := Vector2.ZERO
	if alive:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * SPEED_FALLOFF)
		velocity.z = move_toward(velocity.z, 0, SPEED * SPEED_FALLOFF)

	move_and_slide()


func _on_died() -> void:
	_set_controls_enabled(false)
	if reload_scene_on_death:
		await get_tree().create_timer(respawn_delay).timeout
		get_tree().reload_current_scene()


func _on_revived() -> void:
	_set_controls_enabled(true)


## Looking, and every child tool in the "player_tool" group (the brush and the
## device placer), only react to input while the player is alive.
func _set_controls_enabled(enabled: bool) -> void:
	set_process_unhandled_input(enabled)
	for child in get_children():
		if child.is_in_group("player_tool"):
			child.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
