class_name GrowthArea
extends RefCounted
## A set of vertices, possibly on several growth meshes, each with a strength from
## 0 to 1 (1 at the centre of a round area, 0 at its edge). Brushes and devices
## build one around a point and then reduce or block growth on it, so they share
## all of the vertex gathering and falloff logic.

class Entry:
	var growth: VertexGrowth
	var ids := PackedInt32Array()
	var strengths := PackedFloat32Array()

var _entries: Array[Entry] = []


## 1 at the centre of a round area, falling linearly to 0 at the radius.
static func linear_falloff(distance: float, radius: float) -> float:
	return clampf(1.0 - distance / radius, 0.0, 1.0)


## Vertices around a raycast hit, following the surface from the hit face. Only
## covers the mesh that was hit.
static func from_hit(growth: VertexGrowth, face: int, world_point: Vector3,
		radius: float) -> GrowthArea:
	var area := GrowthArea.new()
	area._add(growth, growth.get_vertices_in_radius(face, world_point, radius),
			world_point, radius)
	return area


## Vertices around any world point, on every growth mesh in range. Scans meshes
## linearly, so build it once and keep it rather than rebuilding every frame.
static func from_point(tree: SceneTree, world_point: Vector3, radius: float) -> GrowthArea:
	var area := GrowthArea.new()
	for node in tree.get_nodes_in_group("growth_meshes"):
		var growth := node as VertexGrowth
		if growth == null or not growth.is_near(world_point, radius):
			continue
		area._add(growth, growth.get_vertices_near_point(world_point, radius),
				world_point, radius)
	return area


func is_empty() -> bool:
	return _entries.is_empty()


## Removes rate * strength * delta of growth from every vertex.
func reduce(rate: float, delta: float) -> void:
	for entry: Entry in _entries:
		if not is_instance_valid(entry.growth):
			continue
		for i in entry.ids.size():
			entry.growth.reduce_vertex(entry.ids[i], rate * entry.strengths[i] * delta)


## Forbids growth on every vertex. Pair each block() with one unblock().
func block() -> void:
	for entry: Entry in _entries:
		if is_instance_valid(entry.growth):
			entry.growth.block_vertices(entry.ids)


func unblock() -> void:
	for entry: Entry in _entries:
		if is_instance_valid(entry.growth):
			entry.growth.unblock_vertices(entry.ids)


func _add(growth: VertexGrowth, ids: PackedInt32Array, center: Vector3, radius: float) -> void:
	if ids.is_empty():
		return
	var entry := Entry.new()
	entry.growth = growth
	entry.ids = ids
	entry.strengths.resize(ids.size())
	for i in ids.size():
		var distance := center.distance_to(growth.get_vertex_world_position(ids[i]))
		entry.strengths[i] = linear_falloff(distance, radius)
	_entries.append(entry)
