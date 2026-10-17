class_name VertexGrowth
extends MeshInstance3D
## Real-time vertex growth simulation.
##
## Every vertex keeps a persistent growth weight (0..1). Only vertices that are
## currently growing are updated each frame, so the cost scales with how much is
## changing rather than with mesh size. Weights reach the GPU through a float
## texture; the mesh itself is never modified.
##
## A vertex only grows while it is "fed": a neighbour is at or above the spread
## trigger, or it is a starting vertex that has not fully grown yet. Tools can
## push weights back down with reduce_vertex(); the vertex then regrows if it is
## still fed, and stays cleared if it is not.

## Time in seconds for a vertex with speed 0.5 to grow from 0 to 1.
@export var growth_duration := 1.0
## Neighbours start growing once a vertex has reached (1 - spread_threshold) of
## its growth. 0 = wait until fully grown, 1 = start together.
@export_range(0.0, 1.0) var spread_threshold := 0.5
## Global simulation speed. 0 = paused, 0.5 = half speed.
@export_range(0.0, 4.0, 0.01) var speed_scale := 1.0
## Index into the mesh's raw vertex array (NOT the Blender vertex index).
## Only used when autostart is enabled.
@export var start_vertex_index := 0
@export var autostart := true

## Vertices closer than 1 / WELD_PRECISION are treated as the same point.
const WELD_PRECISION := 10000.0
## Speed at or below this never grows.
const SPEED_EPSILON := 0.001
## Caps the rate multiplier so speed 1.0 means "very fast" instead of infinity.
const MAX_RATE_MULTIPLIER := 1000.0
const TEXTURE_WIDTH := 1024

# Connectivity (built once, on welded vertices: one per unique position).
var _raw_vertices := PackedVector3Array()
var _indices := PackedInt32Array()
var _vertex_to_welded := PackedInt32Array()
var _welded_positions := PackedVector3Array()
var _neighbors: Array[PackedInt32Array] = []
var _rate_multiplier := PackedFloat32Array() # per welded vertex, from the speed map
var _triangle_mesh: TriangleMesh             # for raycasts; face i = indices[3i .. 3i+2]

# Simulation state, per welded vertex.
var _weights := PackedFloat32Array() # padded to the weight texture size
var _is_active := PackedByteArray()  # 1 while the vertex is in _active
var _seed := PackedByteArray()       # 1 for starting vertices until fully grown
var _active := PackedInt32Array()    # vertices that may currently grow

# GPU side.
var _id_texture: ImageTexture        # raw vertex index -> welded vertex index (static)
var _weight_texture: ImageTexture    # welded vertex index -> weight (updated while changing)
var _weight_image: Image
var _weight_dims := Vector2i.ONE
var _material: ShaderMaterial


func _ready() -> void:
	set_process(false)
	add_to_group("growth_meshes")
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("VertexGrowth: node has no mesh surface to work with")
		return
	_prepare_mesh_data()
	_build_textures()
	if not _assign_material():
		return
	if autostart:
		start_growth(PackedInt32Array([start_vertex_index]))


func _process(delta: float) -> void:
	_step(delta * speed_scale)
	_upload_weights()
	if _active.is_empty():
		set_process(false) # nothing is changing, so cost nothing until woken again


## Starts growth from the given raw mesh vertex indices. Can be called repeatedly.
func start_growth(start_vertices: PackedInt32Array) -> void:
	if _vertex_to_welded.is_empty():
		return
	for v in start_vertices:
		var w := _vertex_to_welded[v]
		_seed[w] = 1
		if _wake(w):
			_active.append(w)
	set_process(not _active.is_empty())


## Clears all growth.
func reset_growth() -> void:
	_weights.fill(0.0)
	_is_active.fill(0)
	_seed.fill(0)
	_active.clear()
	_upload_weights()
	set_process(false)


## Returns the raw mesh vertex index closest to a point in this node's local space.
func find_nearest_vertex(local_point: Vector3) -> int:
	var best := 0
	var best_dist := INF
	for i in _raw_vertices.size():
		var d := _raw_vertices[i].distance_squared_to(local_point)
		if d < best_dist:
			best_dist = d
			best = i
	return best


## Casts a world-space ray against this mesh's triangles. Returns {} on a miss,
## otherwise { "distance": float, "position": Vector3 (world), "face": int }.
func raycast(world_origin: Vector3, world_direction: Vector3, max_distance: float) -> Dictionary:
	if _triangle_mesh == null:
		return {}
	var to_local := global_transform.affine_inverse()
	var local_begin := to_local * world_origin
	var local_end := to_local * (world_origin + world_direction.normalized() * max_distance)
	var hit := _triangle_mesh.intersect_segment(local_begin, local_end)
	if hit.is_empty():
		return {}
	var local_position: Vector3 = hit["position"]
	var world_position := global_transform * local_position
	return {
		"distance": world_origin.distance_to(world_position),
		"position": world_position,
		"face": hit["face_index"],
	}


## Returns the three vertex ids of a face from raycast(). Use these ids with
## get_vertex_world_position() and reduce_vertex().
func get_face_vertex_ids(face: int) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for corner in 3:
		ids.append(_vertex_to_welded[_indices[face * 3 + corner]])
	return ids


func get_vertex_world_position(vertex_id: int) -> Vector3:
	return global_transform * _welded_positions[vertex_id]


## Returns every vertex within radius metres (world space) of world_point,
## starting from the face a raycast hit. It walks the mesh edges outward, so it
## stays on the connected surface and never reaches through a wall to geometry
## that is only close in space. The cost depends on how many vertices are in
## range, not on the size of the mesh.
func get_vertices_in_radius(face: int, world_point: Vector3, radius: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	var queue := get_face_vertex_ids(face)
	var seed_count := queue.size()
	var visited := {}
	for vertex in queue:
		visited[vertex] = true

	var i := 0
	while i < queue.size():
		var vertex := queue[i]
		var inside := get_vertex_world_position(vertex).distance_to(world_point) <= radius
		if inside:
			found.append(vertex)
		# The face's own vertices always expand, so a long thin triangle can't
		# hide vertices that are in range. Everything else only expands from
		# inside the radius.
		if inside or i < seed_count:
			for neighbor in _neighbors[vertex]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		i += 1
	return found


## Removes growth from a vertex. It is woken so it can grow back if it is still fed.
func reduce_vertex(vertex_id: int, amount: float) -> void:
	if amount <= 0.0 or _weights[vertex_id] <= 0.0:
		return
	_weights[vertex_id] = maxf(_weights[vertex_id] - amount, 0.0)
	if _wake(vertex_id):
		_active.append(vertex_id)
	set_process(true)


# --- Simulation --------------------------------------------------------------

func _step(delta: float) -> void:
	var duration := maxf(growth_duration, 0.001)
	var trigger := maxf(1.0 - spread_threshold, 0.0001)
	var next_active := PackedInt32Array()

	for v in _active:
		# No longer fed (for example a neighbour was reversed): stop growing until
		# a neighbour crosses the trigger again.
		if not _is_fed(v, trigger):
			_is_active[v] = 0
			continue

		var before := _weights[v]
		_weights[v] = minf(before + _rate_multiplier[v] * delta / duration, 1.0)
		var after := _weights[v] # read back so comparisons use the stored value

		# Crossing the trigger wakes the neighbours.
		if before < trigger and after >= trigger:
			for n in _neighbors[v]:
				if _wake(n):
					next_active.append(n)

		if after < 1.0:
			next_active.append(v)
		else:
			# Fully grown vertices drop out of the active set.
			_is_active[v] = 0
			_seed[v] = 0

	_active = next_active


func _is_fed(v: int, trigger: float) -> bool:
	if _seed[v] != 0:
		return true
	for n in _neighbors[v]:
		if _weights[n] >= trigger:
			return true
	return false


## Adds a vertex to the active set. Returns false if it is already active, can't
## grow, or is already fully grown.
func _wake(v: int) -> bool:
	if _is_active[v] != 0 or _rate_multiplier[v] <= 0.0 or _weights[v] >= 1.0:
		return false
	_is_active[v] = 1
	return true


## Speed map value -> growth rate multiplier. 0.5 -> 1x, 1.0 -> very fast, 0 -> never.
## This is the inverse of the old edge cost (1 - speed) / speed.
func _speed_to_rate_multiplier(speed: float) -> float:
	if speed <= SPEED_EPSILON:
		return 0.0
	return minf(speed / maxf(1.0 - speed, 0.001), MAX_RATE_MULTIPLIER)


# --- Setup -------------------------------------------------------------------

func _prepare_mesh_data() -> void:
	var arrays := mesh.surface_get_arrays(0)
	_raw_vertices = arrays[Mesh.ARRAY_VERTEX]

	var indices: PackedInt32Array
	if arrays[Mesh.ARRAY_INDEX] == null:
		indices = PackedInt32Array(range(_raw_vertices.size()))
	else:
		indices = arrays[Mesh.ARRAY_INDEX]
	_indices = indices

	# Triangle BVH for raycasts. Built from our own index order, so a hit's
	# face_index is exactly the triangle at indices[3 * face .. 3 * face + 2].
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = _raw_vertices[indices[i]]
	_triangle_mesh = TriangleMesh.new()
	_triangle_mesh.create_from_faces(faces)

	# Weld vertices by position (imported meshes duplicate them along seams).
	var weld_lookup := {}
	_vertex_to_welded.resize(_raw_vertices.size())
	for i in _raw_vertices.size():
		var key := Vector3i((_raw_vertices[i] * WELD_PRECISION).round())
		if not weld_lookup.has(key):
			weld_lookup[key] = _welded_positions.size()
			_welded_positions.append(_raw_vertices[i])
		var welded_id: int = weld_lookup[key]
		_vertex_to_welded[i] = welded_id

	# Adjacency from triangle edges.
	_neighbors.resize(_welded_positions.size())
	for i in _neighbors.size():
		_neighbors[i] = PackedInt32Array()

	for t in range(0, indices.size() - 2, 3):
		for corner in 3:
			var a := _vertex_to_welded[indices[t + corner]]
			var b := _vertex_to_welded[indices[t + (corner + 1) % 3]]
			if a == b:
				continue
			_add_neighbor(a, b)
			_add_neighbor(b, a)

	# Speed map: red channel of the vertex colors, averaged per welded vertex.
	# Without vertex colors, fall back to 0.5 (unchanged speed).
	var speeds := PackedFloat32Array()
	speeds.resize(_welded_positions.size())
	if arrays[Mesh.ARRAY_COLOR] == null:
		speeds.fill(0.5)
	else:
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var sums := PackedFloat32Array()
		sums.resize(speeds.size())
		sums.fill(0.0)
		var counts := PackedInt32Array()
		counts.resize(speeds.size())
		counts.fill(0)
		for i in colors.size():
			var w := _vertex_to_welded[i]
			sums[w] += colors[i].r
			counts[w] += 1
		for w in speeds.size():
			speeds[w] = sums[w] / counts[w]

	_rate_multiplier.resize(speeds.size())
	for w in speeds.size():
		_rate_multiplier[w] = _speed_to_rate_multiplier(speeds[w])

	_is_active.resize(_welded_positions.size())
	_is_active.fill(0)
	_seed.resize(_welded_positions.size())
	_seed.fill(0)


func _add_neighbor(a: int, b: int) -> void:
	var list := _neighbors[a]
	if not list.has(b):
		list.append(b)
		_neighbors[a] = list


func _texture_dims(count: int) -> Vector2i:
	var width := clampi(count, 1, TEXTURE_WIDTH)
	var height := maxi(ceili(float(count) / width), 1)
	return Vector2i(width, height)


func _build_textures() -> void:
	# Static: raw vertex index -> welded vertex index. The shader reads this with
	# VERTEX_ID, so the mesh itself never needs extra attributes.
	var raw_count := _vertex_to_welded.size()
	var id_dims := _texture_dims(raw_count)
	var id_floats := PackedFloat32Array()
	id_floats.resize(id_dims.x * id_dims.y)
	for i in raw_count:
		id_floats[i] = _vertex_to_welded[i]
	var id_image := Image.create_from_data(
		id_dims.x, id_dims.y, false, Image.FORMAT_RF, id_floats.to_byte_array())
	_id_texture = ImageTexture.create_from_image(id_image)

	# Dynamic: welded vertex index -> weight.
	_weight_dims = _texture_dims(_welded_positions.size())
	_weights.resize(_weight_dims.x * _weight_dims.y)
	_weights.fill(0.0)
	_weight_image = Image.create_from_data(
		_weight_dims.x, _weight_dims.y, false, Image.FORMAT_RF, _weights.to_byte_array())
	_weight_texture = ImageTexture.create_from_image(_weight_image)


func _assign_material() -> bool:
	var source := get_active_material(0) as ShaderMaterial
	if source == null:
		push_error("VertexGrowth: assign a ShaderMaterial that uses growth_debug.gdshader")
		return false
	# Each growing mesh needs its own textures, so give it its own material copy.
	_material = source.duplicate() as ShaderMaterial
	_material.set_shader_parameter("welded_ids", _id_texture)
	_material.set_shader_parameter("growth_weights", _weight_texture)
	material_override = _material
	return true


func _upload_weights() -> void:
	_weight_image.set_data(
		_weight_dims.x, _weight_dims.y, false, Image.FORMAT_RF, _weights.to_byte_array())
	_weight_texture.update(_weight_image)
