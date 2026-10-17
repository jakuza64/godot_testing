extends Control

@export var radius := 6.0
@export var thickness := 2.0
@export var color := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, color, thickness, true)
