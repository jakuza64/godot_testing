class_name GrowthSuppressor
extends Node3D
## A placed device that keeps growth out of a radius. Every vertex in range can't
## grow, and growth already on it drains away, strongest at the device and fading
## linearly toward the edge (the same falloff as the brush). Passive and static:
## the affected vertices are found once, then each physics tick only walks that
## cached list.

## Radius in metres. Applies on every growth mesh in range, including
## neighbouring rooms.
@export var radius := 3.0
## Weight removed per second at a vertex right next to the device. Vertices
## near the edge drain more slowly, but are blocked from growing regardless.
@export var reverse_rate := 3.0
## Shows a translucent sphere the size of the effect.
@export var show_debug_sphere := true
## Adds a simple cylinder so the device is visible. Turn off if your own scene
## provides the visuals.
@export var show_placeholder_mesh := true

var _area: GrowthArea
var _sphere := RadiusDebugSphere.new(Color(0.2, 0.8, 1.0, 0.2))


func _ready() -> void:
	if show_placeholder_mesh:
		add_child(_make_placeholder_mesh())
	add_child(_sphere)
	# Deferred, so the position is final and every growth mesh has finished its
	# own setup, whether the device was placed in the editor or spawned at runtime.
	refresh.call_deferred()


func _physics_process(delta: float) -> void:
	if _area != null:
		_area.reduce(reverse_rate, delta)


func _exit_tree() -> void:
	if _area != null:
		_area.unblock() # release the vertices so growth can return
		_area = null


## Rebuilds the affected vertices. Call it after moving the device or changing
## its radius at runtime.
func refresh() -> void:
	if not is_inside_tree():
		return
	if _area != null:
		_area.unblock()
	_area = GrowthArea.from_point(get_tree(), global_position, radius)
	_area.block()

	if show_debug_sphere:
		_sphere.show_at(global_position, radius)
	else:
		_sphere.hide()


func _make_placeholder_mesh() -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.15
	cylinder.bottom_radius = 0.15
	cylinder.height = 0.4
	cylinder.material = material

	var instance := MeshInstance3D.new()
	instance.mesh = cylinder
	instance.position.y = 0.2 # sit on the surface instead of sinking into it
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return instance
