## Turns raw pointer input over the board into two gestures:
##   tapped(cell)       - a short press and release (mouse click or touch tap)
##   long_pressed(cell) - holding still for LONG_PRESS seconds (shows details)
## Touch arrives as emulated mouse events, so one code path serves both.
## Knows nothing about combat.
extends Control

signal tapped(cell: Vector2i)
signal long_pressed(cell: Vector2i)

const LONG_PRESS := 0.45
const MOVE_TOLERANCE := 14.0

var cell_size: float = 60.0
var _down := false
var _down_pos := Vector2.ZERO
var _down_time := 0.0
var _long_fired := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func cell_at(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / cell_size), floori(local.y / cell_size))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			_down_pos = event.position
			_down_time = 0.0
			_long_fired = false
		elif _down:
			_down = false
			if not _long_fired and event.position.distance_to(_down_pos) <= MOVE_TOLERANCE:
				tapped.emit(cell_at(_down_pos))
		accept_event()
	elif event is InputEventMouseMotion and _down:
		if event.position.distance_to(_down_pos) > MOVE_TOLERANCE:
			_down = false


func _process(delta: float) -> void:
	if _down and not _long_fired:
		_down_time += delta
		if _down_time >= LONG_PRESS:
			_long_fired = true
			long_pressed.emit(cell_at(_down_pos))
