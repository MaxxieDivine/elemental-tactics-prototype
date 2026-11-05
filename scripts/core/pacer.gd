## Simple back-and-forth pacing for an NPC between data-defined points (a map
## NPC's "pace": [[x, y], ...]). Plain data, no Nodes: the town view asks it
## for the next step on a timer and animates the move. Not a cutscene system.
##
## The route runs in straight 4-way lines from point to point (x first, then
## y), then turns back at the last point. When the next cell is blocked (the
## player, the player's path, anything standing there) the pacer turns around
## instead of waiting, so it never stands in anyone's way for long.
extends RefCounted

var route: Array = []  # every cell walked, in order
var stops: Array = []  # indices into route of the data points (pause there)
var index: int = 0
var dir: int = 1
var cell: Vector2i


## points: the data points; start: where the NPC stands now (snapped to the
## route's first cell when it is not on the route).
func _init(points: Array, start: Vector2i = Vector2i(-1, -1)) -> void:
	route = route_through(points)
	for p in points:
		var c := Vector2i(int(p[0]), int(p[1]))
		for i in route.size():
			if route[i] == c and not stops.has(i):
				stops.append(i)
				break
	index = maxi(0, route.find(start))
	cell = route[index] if not route.is_empty() else start


## Cells from point to point in straight lines (x first, then y).
static func route_through(points: Array) -> Array:
	var out: Array = []
	for p in points:
		var to := Vector2i(int(p[0]), int(p[1]))
		if out.is_empty():
			out.append(to)
			continue
		var c: Vector2i = out[-1]
		while c.x != to.x:
			c.x += signi(to.x - c.x)
			out.append(c)
		while c.y != to.y:
			c.y += signi(to.y - c.y)
			out.append(c)
	return out


## The cell the next step goes to (the current cell if the route is one cell).
func next_cell() -> Vector2i:
	if route.size() < 2:
		return cell
	var j := index + dir
	if j < 0 or j >= route.size():
		j = index - dir
	return route[j]


## Takes one step unless `blocked.call(cell) -> bool` says the next cell is
## taken, in which case it turns around. Returns true when it moved.
func step(blocked: Callable) -> bool:
	if route.size() < 2:
		return false
	if index + dir < 0 or index + dir >= route.size():
		dir = -dir
	var n: Vector2i = route[index + dir]
	if blocked.call(n):
		dir = -dir
		return false
	index += dir
	cell = n
	return true


## True when standing on one of the data points (the view pauses there).
func at_stop() -> bool:
	return stops.has(index)
