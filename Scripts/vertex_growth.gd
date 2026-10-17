class_name VertexGrowth
extends MeshInstance3D
## Port of the Blender "spreading growth" geometry nodes setup.
## Finds the shortest path cost from the start vertices to every vertex across
## the mesh surface, then animates a per-vertex weight (0..1) over time and
## writes it into the alpha channel of the mesh's vertex colors.

## Time in seconds for a single vertex to go from 0 to 1.
@export var growth_duration := 1.0
## Neighbours start growing once a vertex has reached (1 - spread_threshold)
## of its growth. 0 = wait until fully grown, 1 = all vertices start together.
@export_range(0.0, 1.0) var spread_threshold := 0.75
## Index into the mesh's raw vertex array (NOT the Blender vertex index).
## Only used when autostart is enabled.
@export var start_vertex_index := 0
@export var autostart := true

## Vertices closer than 1 / WELD_PRECISION are treated as the same point.
const WELD_PRECISION := 10000.0
## Average edge speed at or below this counts as zero (infinite cost).
const SPEED_EPSILON := 0.001

var _material: Material
var _working_mesh := ArrayMesh.new()
var _arrays: Array
var _colors: PackedColorArray

# Imported meshes duplicate vertices along UV seams and hard edges, so
# connectivity is built on "welded" vertices (one per unique position).
var _vertex_to_welded := PackedInt32Array()
var _welded_positions := PackedVector3Array()
var _neighbors: Array[PackedInt32Array] = []

var _total_cost := PackedFloat32Array()   # per welded vertex
var _start_weights := PackedFloat32Array() # per welded vertex
var _welded_speed := PackedFloat32Array()  # per welded vertex, 0..1 (0.5 = unchanged)
var _max_cost := 0.0
var _elapsed := 0.0


func _ready() -> void:
	set_process(false)
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("VertexGrowth: node has no mesh surface to work with")
		return
	_prepare_mesh()
	if autostart:
		start_growth(PackedInt32Array([start_vertex_index]))


func _process(delta: float) -> void:
	_elapsed += delta
	_update_weights()
	if _elapsed >= _total_duration():
		set_process(false)


## Starts (or restarts) the growth from the given raw mesh vertex indices.
func start_growth(start_vertices: PackedInt32Array) -> void:
	if _vertex_to_welded.is_empty():
		return

	_start_weights.resize(_welded_positions.size())
	_start_weights.fill(0.0)

	var welded_starts := PackedInt32Array()
	for v in start_vertices:
		var w := _vertex_to_welded[v]
		welded_starts.append(w)
		_start_weights[w] = 1.0 # Blender: max(startGroup, animated value)

	_compute_total_costs(welded_starts)
	_elapsed = 0.0
	set_process(true)


## Returns the raw mesh vertex index closest to a point in this node's local space.
func find_nearest_vertex(local_point: Vector3) -> int:
	var vertices: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	var best := 0
	var best_dist := INF
	for i in vertices.size():
		var d := vertices[i].distance_squared_to(local_point)
		if d < best_dist:
			best_dist = d
			best = i
	return best


# --- Setup -------------------------------------------------------------------

func _prepare_mesh() -> void:
	# Grab the material first: swapping the mesh below resets surface overrides.
	_material = get_active_material(0)
	_arrays = mesh.surface_get_arrays(0)

	var vertices: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]

	var indices: PackedInt32Array
	if _arrays[Mesh.ARRAY_INDEX] == null:
		indices = PackedInt32Array(range(vertices.size()))
	else:
		indices = _arrays[Mesh.ARRAY_INDEX]

	var has_vertex_colors: bool = _arrays[Mesh.ARRAY_COLOR] != null
	if not has_vertex_colors:
		_colors = PackedColorArray()
		_colors.resize(vertices.size())
		_colors.fill(Color(1, 1, 1, 0))
	else:
		_colors = _arrays[Mesh.ARRAY_COLOR]

	# Weld vertices by position.
	var weld_lookup := {}
	_vertex_to_welded.resize(vertices.size())
	for i in vertices.size():
		var key := Vector3i((vertices[i] * WELD_PRECISION).round())
		if not weld_lookup.has(key):
			weld_lookup[key] = _welded_positions.size()
			_welded_positions.append(vertices[i])
		var welded_id: int = weld_lookup[key]
		_vertex_to_welded[i] = welded_id

	# Build adjacency from triangle edges.
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

	# Speed map: red channel of the vertex colors, averaged over every raw vertex
	# that shares a welded position. Without vertex colors, fall back to 0.5
	# (unchanged cost).
	_welded_speed.resize(_welded_positions.size())
	if has_vertex_colors:
		var sums := PackedFloat32Array()
		sums.resize(_welded_speed.size())
		sums.fill(0.0)
		var counts := PackedInt32Array()
		counts.resize(_welded_speed.size())
		counts.fill(0)
		for i in _colors.size():
			var w := _vertex_to_welded[i]
			sums[w] += _colors[i].r
			counts[w] += 1
		for w in _welded_speed.size():
			_welded_speed[w] = sums[w] / counts[w]
	else:
		_welded_speed.fill(0.5)

	# Start with everything at weight 0.
	for i in _colors.size():
		var c := _colors[i]
		c.a = 0.0
		_colors[i] = c

	mesh = _working_mesh
	_apply_colors()


func _add_neighbor(a: int, b: int) -> void:
	var list := _neighbors[a]
	if not list.has(b):
		list.append(b)
		_neighbors[a] = list


# --- Shortest Edge Paths -----------------------------------------------------

## Cost of travelling along the edge between two welded vertices.
## Driven by the speed map (red channel of the vertex colors):
## speed 0.5 -> cost 1 (unchanged), speed 1 -> cost 0, speed 0 -> infinite.
func _edge_cost(a: int, b: int) -> float:
	# Blender evaluates the field per edge, so the two vertex values are averaged first.
	var speed := (_welded_speed[a] + _welded_speed[b]) * 0.5
	if absf(speed) <= SPEED_EPSILON:
		return INF
	return maxf((1.0 - speed) / speed, 0.0)


## Multi-source Dijkstra: total cost from every vertex to its nearest start vertex.
## Unreachable vertices keep a cost of INF.
func _compute_total_costs(welded_starts: PackedInt32Array) -> void:
	_total_cost.resize(_welded_positions.size())
	_total_cost.fill(INF)

	var heap := MinHeap.new()
	for s in welded_starts:
		_total_cost[s] = 0.0
		heap.push(0.0, s)

	while not heap.is_empty():
		var v := heap.pop()
		var cost := heap.popped_cost
		if cost > _total_cost[v]:
			continue # stale heap entry
		for n in _neighbors[v]:
			var new_cost := cost + _edge_cost(v, n)
			if new_cost < _total_cost[n]:
				_total_cost[n] = new_cost
				heap.push(new_cost, n)

	_max_cost = 0.0
	for c in _total_cost:
		if not is_inf(c):
			_max_cost = maxf(_max_cost, c)


# --- Animation ---------------------------------------------------------------

func _total_duration() -> float:
	var duration := maxf(growth_duration, 0.001)
	return _max_cost * duration * (1.0 - spread_threshold) + duration


func _update_weights() -> void:
	var duration := maxf(growth_duration, 0.001)
	var weights := PackedFloat32Array()
	weights.resize(_welded_positions.size())

	for w in weights.size():
		var progress := 0.0
		var cost := _total_cost[w]
		if not is_inf(cost):
			# Spread Threshold: when this vertex is allowed to start growing.
			var delay := cost * duration * (1.0 - spread_threshold)
			# Animation: (time - delay) / growthDuration, clamped to 0..1.
			progress = clampf((_elapsed - delay) / duration, 0.0, 1.0)
		# Weight = max(startGroup, animated value)
		weights[w] = maxf(progress, _start_weights[w])

	for i in _colors.size():
		var c := _colors[i]
		c.a = weights[_vertex_to_welded[i]]
		_colors[i] = c

	_apply_colors()


func _apply_colors() -> void:
	_arrays[Mesh.ARRAY_COLOR] = _colors
	_working_mesh.clear_surfaces()
	_working_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	_working_mesh.surface_set_material(0, _material)


# --- Priority queue ----------------------------------------------------------

## Minimal binary min-heap of (cost, item) pairs for Dijkstra.
class MinHeap:
	var costs := PackedFloat32Array()
	var items := PackedInt32Array()
	var popped_cost := 0.0

	func is_empty() -> bool:
		return items.is_empty()

	func push(cost: float, item: int) -> void:
		costs.append(cost)
		items.append(item)
		var i := items.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if costs[parent] <= costs[i]:
				break
			_swap(i, parent)
			i = parent

	## Removes and returns the cheapest item; its cost is left in popped_cost.
	func pop() -> int:
		var top := items[0]
		popped_cost = costs[0]
		var last := items.size() - 1
		items[0] = items[last]
		costs[0] = costs[last]
		items.resize(last)
		costs.resize(last)

		var i := 0
		while true:
			var left := 2 * i + 1
			var right := left + 1
			var smallest := i
			if left < last and costs[left] < costs[smallest]:
				smallest = left
			if right < last and costs[right] < costs[smallest]:
				smallest = right
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var tmp_cost := costs[a]
		costs[a] = costs[b]
		costs[b] = tmp_cost
		var tmp_item := items[a]
		items[a] = items[b]
		items[b] = tmp_item
