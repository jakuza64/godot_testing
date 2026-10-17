class_name GrowthTargeting
extends RefCounted
## Finds the growth surface the camera is looking at. Shared by every tool that
## aims at growth, so the ray and the occlusion logic live in one place.

## A hit is ignored if a physics body (wall, prop) is more than this much closer.
const OCCLUSION_MARGIN := 0.1


## Casts a ray from the centre of the active camera. Returns {} if nothing is
## hit, otherwise:
## { "growth": VertexGrowth, "face": int, "position": Vector3 (world), "distance": float }
## Call this from _physics_process, because it queries the physics space.
## Pass the RIDs of bodies that shouldn't block the view (usually the player).
## With debug on, it prints why a cast found nothing.
static func from_camera(caller: Node3D, max_range: float, exclude: Array[RID],
		debug := false) -> Dictionary:
	var camera := caller.get_viewport().get_camera_3d()
	if camera == null:
		if debug:
			print("GrowthTargeting: no active Camera3D")
		return {}
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z

	# Nearest hit across every growth mesh in range.
	var meshes := caller.get_tree().get_nodes_in_group("growth_meshes")
	var best := {}
	for node in meshes:
		var growth := node as VertexGrowth
		if growth == null:
			continue
		var hit := growth.raycast(origin, direction, max_range)
		if hit.is_empty():
			continue
		if best.is_empty() or hit["distance"] < best["distance"]:
			best = hit
			best["growth"] = growth

	if best.is_empty():
		if debug:
			print("GrowthTargeting: ray hit no growth mesh (%d in group, range %.1f m)"
					% [meshes.size(), max_range])
		return {}

	var blocker := _find_occluder(caller, origin, direction, best["distance"], exclude)
	if blocker != null:
		if debug:
			print("GrowthTargeting: growth surface at %.2f m is blocked by %s"
					% [best["distance"], _describe(blocker)])
		return {}
	return best


## Returns the physics body between the camera and the growth hit, or null.
static func _find_occluder(caller: Node3D, origin: Vector3, direction: Vector3,
		hit_distance: float, exclude: Array[RID]) -> Object:
	var end_distance := hit_distance - OCCLUSION_MARGIN
	if end_distance <= 0.0:
		return null
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * end_distance)
	query.exclude = exclude
	var result := caller.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return result["collider"]


static func _describe(blocker: Object) -> String:
	var node := blocker as Node
	return str(node.get_path()) if node != null else str(blocker)
