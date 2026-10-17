class_name GrowthReverser
extends Node3D
## Hold the "reverse_growth" input action to push growth back where the
## crosshair points. Add this as a direct child of the Player node. The ray is
## cast from the active camera. Every vertex within brush_radius metres of the
## exact point being looked at is affected, with a linear falloff by distance.

## How far the player can reach, in metres.
@export var max_range := 6.0
## Radius in metres around the pointed spot. Every vertex within it is affected,
## with a linear falloff: full strength at the centre, none at the edge. On a
## 1 m grid, keep it above about 0.75 or some spots will have no vertex in range.
@export var brush_radius := 1.5
## Weight removed per second at a vertex the pointer is exactly on. Growth at
## normal speed adds 1 / growth_duration per second, so keep this higher.
@export var reverse_rate := 3.0

## A hit is ignored if a physics body (wall, prop) is more than this much closer.
const OCCLUSION_MARGIN := 0.1

var _exclude: Array[RID] = []


func _ready() -> void:
	# Keep the player's own collider from blocking the occlusion check.
	var body := get_parent() as CollisionObject3D
	if body != null:
		_exclude.append(body.get_rid())


func _physics_process(delta: float) -> void:
	if not Input.is_action_pressed("reverse_growth"):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z

	# Nearest hit across every growth mesh in range.
	var best_growth: VertexGrowth = null
	var best_hit := {}
	for node in get_tree().get_nodes_in_group("growth_meshes"):
		var growth := node as VertexGrowth
		if growth == null:
			continue
		var hit := growth.raycast(origin, direction, max_range)
		if hit.is_empty():
			continue
		if best_growth == null or hit["distance"] < best_hit["distance"]:
			best_growth = growth
			best_hit = hit

	if best_growth == null:
		return
	if _is_occluded(origin, direction, best_hit["distance"]):
		return
	_apply_brush(best_growth, best_hit, delta)


func _apply_brush(growth: VertexGrowth, hit: Dictionary, delta: float) -> void:
	var hit_position: Vector3 = hit["position"]
	var face: int = hit["face"]
	for vertex_id in growth.get_vertices_in_radius(face, hit_position, brush_radius):
		var distance := hit_position.distance_to(growth.get_vertex_world_position(vertex_id))
		# Linear: 1 at the centre, 0 at brush_radius away.
		var falloff := 1.0 - distance / brush_radius
		growth.reduce_vertex(vertex_id, reverse_rate * falloff * delta)


## True if a physics body sits between the camera and the growth hit.
func _is_occluded(origin: Vector3, direction: Vector3, hit_distance: float) -> bool:
	var end_distance := hit_distance - OCCLUSION_MARGIN
	if end_distance <= 0.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * end_distance)
	query.exclude = _exclude
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
