extends RefCounted
# NAV - the demon's map of where it can walk, and its path finding.
# Source: Godot's built-in AStarGrid2D class (A* path finding on a grid).
# The floor is cut into 0.5 m squares ("cells"). A cell is either free or
# solid. Walls, pews and columns are solid for ever; cells that a CLOSED
# chalk circle passes through become solid while that circle exists, so
# the demon plans its route around circles instead of walking into them.

const CELL := 0.5

var astar := AStarGrid2D.new()
var origin := Vector2.ZERO          # world position (x, z) of the grid's corner
var size := Vector2i.ZERO           # how many cells wide and deep
var static_solid := PackedByteArray()
var chalk_cells := {}               # cells made solid by chalk right now


func setup(world_rect: Rect2) -> void:
	origin = world_rect.position
	size = Vector2i(int(ceil(world_rect.size.x / CELL)), int(ceil(world_rect.size.y / CELL)))
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	static_solid.resize(size.x * size.y)
	static_solid.fill(1)            # everything starts as solid rock; rooms are carved out


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / CELL)), int(floor((p.y - origin.y) / CELL)))


func center_of(c: Vector2i) -> Vector2:
	return origin + (Vector2(c.x, c.y) + Vector2(0.5, 0.5)) * CELL


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func _index(c: Vector2i) -> int:
	return c.y * size.x + c.x


func _set_rect(rect: Rect2, value: int) -> void:
	var a = cell_of(rect.position)
	var b = cell_of(rect.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var c = Vector2i(x, y)
			if in_bounds(c) and rect.has_point(center_of(c)):
				static_solid[_index(c)] = value


# Make a rectangle of floor walkable.
func carve(rect: Rect2) -> void:
	_set_rect(rect, 0)


# Put an obstacle (pew, column, altar) on the floor. "grow" keeps the demon's
# body from brushing through the corners.
func block(rect: Rect2, grow: float = 0.3) -> void:
	_set_rect(rect.grow(grow), 1)


# Call once after all carve() and block() calls.
func commit() -> void:
	for y in range(size.y):
		for x in range(size.x):
			var c = Vector2i(x, y)
			astar.set_point_solid(c, static_solid[_index(c)] == 1)


# True if this spot is open floor (ignores chalk).
func is_free(p: Vector2) -> bool:
	var c = cell_of(p)
	return in_bounds(c) and static_solid[_index(c)] == 0


# Rebuild the chalk cells from the list of closed circles.
func set_chalk(loops: Array) -> void:
	for c in chalk_cells.keys():
		astar.set_point_solid(c, static_solid[_index(c)] == 1)
	chalk_cells.clear()
	for loop in loops:
		var pts = loop["pts"]
		var count = pts.size()
		for i in range(count):
			var a = pts[i]
			var b = pts[(i + 1) % count]
			var steps = int(ceil(a.distance_to(b) / 0.15)) + 1
			for k in range(steps + 1):
				var c = cell_of(a.lerp(b, float(k) / float(steps)))
				if in_bounds(c):
					chalk_cells[c] = true
					astar.set_point_solid(c, true)


# True if a straight walk from a to b stays on free cells.
func clear_line(a: Vector2, b: Vector2) -> bool:
	var steps = int(ceil(a.distance_to(b) / 0.15)) + 1
	for k in range(steps + 1):
		var c = cell_of(a.lerp(b, float(k) / float(steps)))
		if not in_bounds(c) or astar.is_point_solid(c):
			return false
	return true


# A shortcut is allowed only over free cells and never across a chalk line.
func _shortcut_ok(a: Vector2, b: Vector2, chalk) -> bool:
	if not clear_line(a, b):
		return false
	if chalk != null and chalk.segment_blocked(a, b):
		return false
	return true


# If p sits in a solid cell (for example pressed against a chalk line), find
# the nearest free cell on the same side of every circle. Returns null if none.
func _free_cell_near(p: Vector2, chalk):
	var c = cell_of(p)
	if in_bounds(c) and not astar.is_point_solid(c):
		return c
	var best = null
	var best_d = 999.0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var n = c + Vector2i(dx, dy)
			if not in_bounds(n) or astar.is_point_solid(n):
				continue
			var ctr = center_of(n)
			if chalk != null and chalk.is_separated(p, ctr):
				continue
			var d = ctr.distance_to(p)
			if d < best_d:
				best_d = d
				best = n
	return best


# The route from one spot to another as a list of points to walk through.
# An empty list means "no way there" (a wall or a chalk circle is in the way).
func find_path(from: Vector2, to: Vector2, chalk = null) -> Array:
	var a = _free_cell_near(from, chalk)
	var b = _free_cell_near(to, chalk)
	if a == null or b == null:
		return []
	var ids = astar.get_id_path(a, b)
	if ids.is_empty():
		return []
	var raw = []
	for k in range(1, ids.size()):
		raw.append(center_of(ids[k]))
	var to_cell = cell_of(to)
	if in_bounds(to_cell) and not astar.is_point_solid(to_cell):
		raw.append(to)
	if raw.is_empty():
		raw.append(center_of(b))
	# cut corners: skip ahead whenever a straight line is free (max 6 points)
	var out = []
	var anchor = from
	var i = 0
	while i < raw.size():
		var j = min(raw.size() - 1, i + 6)
		while j > i and not _shortcut_ok(anchor, raw[j], chalk):
			j -= 1
		out.append(raw[j])
		anchor = raw[j]
		i = j + 1
	return out


# When there is no way to "to", this finds the free spot closest to it that
# the demon CAN reach. That is where it stands and screams at you.
# Searches at most about max_dist metres around "from" (the whole map was too slow on big levels).
func closest_reachable(from: Vector2, to: Vector2, chalk = null, max_dist := 18.0) -> Vector2:
	var start = _free_cell_near(from, chalk)
	if start == null:
		return from
	var best = start
	var best_d = center_of(start).distance_squared_to(to)
	var seen = {start: true}
	var queue = [start]
	var head = 0
	var steps = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var limit := int(max_dist / CELL)
	while head < queue.size():
		var c = queue[head]
		head += 1
		var d = center_of(c).distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = c
		for s in steps:
			var n = c + s
			if absi(n.x - start.x) > limit or absi(n.y - start.y) > limit:
				continue
			if in_bounds(n) and not astar.is_point_solid(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return center_of(best)
