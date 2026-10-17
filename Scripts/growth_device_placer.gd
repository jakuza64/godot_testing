class_name GrowthDevicePlacer
extends Node3D
## Press the "place_device" input action to drop a GrowthSuppressor where the
## crosshair points. Add this as a direct child of the Player node.

## Optional scene whose root is a GrowthSuppressor. Leave empty to use the
## built-in placeholder device.
@export var device_scene: PackedScene
## How far the player can place a device, in metres.
@export var max_range := 6.0
## When this many devices exist, placing another removes the oldest. 0 = no limit.
@export var max_devices := 3
## Prints to the Output panel whenever a press doesn't place a device, and why.
@export var debug_logging := false

var _exclude: Array[RID] = []
var _devices: Array[GrowthSuppressor] = []
var _place_requested := false


func _ready() -> void:
	# Keep the player's own collider from blocking the occlusion check.
	var body := get_parent() as CollisionObject3D
	if body != null:
		_exclude.append(body.get_rid())


# The press is caught as an event and remembered. Polling for "just pressed" in
# _physics_process can miss a press that lands between two physics ticks.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_device"):
		_place_requested = true
		_log("place_device pressed")


func _physics_process(_delta: float) -> void:
	if not _place_requested:
		return
	_place_requested = false

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_log("ignored: the mouse is not captured")
		return

	var hit := GrowthTargeting.from_camera(self, max_range, _exclude, debug_logging)
	if hit.is_empty():
		return
	_log("placing at %s" % hit["position"])
	_place(hit["position"])


func _place(world_position: Vector3) -> void:
	var device: GrowthSuppressor
	if device_scene != null:
		device = device_scene.instantiate() as GrowthSuppressor
	else:
		device = GrowthSuppressor.new()
	if device == null:
		push_error("GrowthDevicePlacer: the root of device_scene must be a GrowthSuppressor")
		return

	get_tree().current_scene.add_child(device)
	device.global_position = world_position
	_devices.append(device)

	if max_devices > 0 and _devices.size() > max_devices:
		var oldest: GrowthSuppressor = _devices.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _log(message: String) -> void:
	if debug_logging:
		print("GrowthDevicePlacer: ", message)
