class_name HealthBar
extends ProgressBar
## Shows a HealthComponent. In single player it finds the player through the
## "player" group. In multiplayer, call bind() with the local player's health
## instead (for example from whatever spawns the local player).

var _health: HealthComponent


func _ready() -> void:
	show_percentage = true
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		bind(HealthComponent.find_on(player))


func bind(health: HealthComponent) -> void:
	if _health != null:
		_health.health_changed.disconnect(_on_health_changed)
	_health = health
	if _health == null:
		return
	max_value = _health.max_health
	value = _health.health
	_health.health_changed.connect(_on_health_changed)


func _on_health_changed(new_health: float, _old_health: float) -> void:
	value = new_health
