extends Area3D

const ROT_SPEED = 120

func _process(delta: float) -> void:
	rotate_y(deg_to_rad(ROT_SPEED) * delta)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		Events.coin_collected.emit()
		queue_free()
