class_name GrowthExposure
extends Node3D
## A damage source: hurts a character that stands in or near growth. It only
## decides how much damage to deal and hands it to a HealthComponent, which
## decides what that means. Add it as a child of the Player, at the player's feet.
##
## Exposure is the strongest growth weight among the vertices within `radius`.
## Damage runs only on the server, a few times per second rather than every
## frame, so it stays cheap.

signal exposure_changed(exposure: float)

## The health to damage. Left empty, it uses the HealthComponent on its parent.
@export var health: HealthComponent
## How close growth has to be to count, in metres. On a 1 m grid, keep it near
## 1.0 so there is always a vertex in range.
@export var radius := 1.0
## Exposure below this does no damage. Damage scales from 0 here up to the
## maximum at full exposure.
@export_range(0.0, 0.99) var min_exposure := 0.2
## Damage per second at full exposure.
@export var max_damage_per_second := 20.0
## Seconds between samples.
@export var tick_interval := 0.1

## 0 to 1. Also useful for effects (screen tint, heartbeat) on the local player.
var exposure := 0.0

var _elapsed := 0.0


func _ready() -> void:
	if health == null:
		health = HealthComponent.find_on(get_parent())
	if health == null:
		push_error("GrowthExposure: no HealthComponent found. Assign one or add it to the parent.")
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < tick_interval:
		return
	var elapsed := _elapsed
	_elapsed = 0.0

	if not HealthComponent.has_server_authority(self):
		return
	if not health.is_alive:
		_set_exposure(0.0)
		return

	var area := GrowthArea.from_point(get_tree(), global_position, radius)
	_set_exposure(area.peak_weight())

	if exposure > min_exposure:
		var severity := (exposure - min_exposure) / (1.0 - min_exposure)
		health.apply_damage(max_damage_per_second * severity * elapsed, &"growth")


func _set_exposure(value: float) -> void:
	if is_equal_approx(value, exposure):
		return
	exposure = value
	exposure_changed.emit(exposure)
