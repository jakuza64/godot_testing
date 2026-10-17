class_name GrowthReverser
extends Node3D
## Hold the "reverse_growth" input action to push growth back where the
## crosshair points. Add this as a direct child of the Player node. Every vertex
## within brush_radius metres of the exact point being looked at is affected,
## with a linear falloff by distance.

## How far the player can reach, in metres.
@export var max_range := 6.0
## Radius in metres around the pointed spot. Every vertex within it is affected,
## with a linear falloff: full strength at the centre, none at the edge. On a
## 1 m grid, keep it above about 0.75 or some spots will have no vertex in range.
@export var brush_radius := 1.5
## Weight removed per second at a vertex the pointer is exactly on. Growth at
## normal speed adds 1 / growth_duration per second, so keep this higher.
@export var reverse_rate := 3.0
## Shows a translucent sphere the size of the brush while it is active.
@export var show_debug_sphere := true

var _exclude: Array[RID] = []
var _sphere := RadiusDebugSphere.new()


func _ready() -> void:
	# Keep the player's own collider from blocking the occlusion check.
	var body := get_parent() as CollisionObject3D
	if body != null:
		_exclude.append(body.get_rid())
	add_child(_sphere)


func _physics_process(delta: float) -> void:
	_sphere.hide()
	if not Input.is_action_pressed("reverse_growth"):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var hit := GrowthTargeting.from_camera(self, max_range, _exclude)
	if hit.is_empty():
		return

	var growth: VertexGrowth = hit["growth"]
	var point: Vector3 = hit["position"]
	var area := GrowthArea.from_hit(growth, hit["face"], point, brush_radius)
	area.reduce(reverse_rate, delta)

	if show_debug_sphere:
		_sphere.show_at(point, brush_radius)
