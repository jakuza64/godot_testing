extends AudioStreamPlayer3D


func _ready() -> void:
	Events.coin_collected.connect(play)
