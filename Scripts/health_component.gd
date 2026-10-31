class_name HealthComponent
extends Node
## Owns a character's health and nothing else. Anything that can take damage has
## one as a child, and everything else (UI, death handling, damage sources) talks
## to it only through its methods and signals.
##
## Built to be server-authoritative: only the server ever changes health. Offline
## counts as being the server, so single player just works. Later, clients get
## `health` through a MultiplayerSynchronizer, and the setter below fires the same
## signals on every peer, so the HUD and death handling need no extra code.

## Emitted on every peer whenever health changes.
signal health_changed(new_health: float, old_health: float)
## Emitted on the server only, when damage is applied. This is the hook for
## cosmetic feedback to the damaged player (hit flash, damage direction) later.
signal damaged(amount: float, type: StringName, source_peer: int)
## Emitted on every peer when health reaches zero, and when it comes back.
signal died
signal revived

@export var max_health := 100.0

var health := 0.0:
	set(value):
		var old := health
		health = clampf(value, 0.0, max_health)
		if is_equal_approx(health, old):
			return
		health_changed.emit(health, old)
		if health <= 0.0 and not _dead:
			_dead = true
			died.emit()
		elif health > 0.0 and _dead:
			_dead = false
			revived.emit()

var is_alive: bool:
	get:
		return health > 0.0

var _dead := false


## True on the server, and when playing offline.
static func has_server_authority(node: Node) -> bool:
	return node.multiplayer.multiplayer_peer == null or node.multiplayer.is_server()


## Returns the HealthComponent that is a direct child of node, or null.
## Lets damage sources hurt "whatever this is" without knowing its type.
static func find_on(node: Node) -> HealthComponent:
	for child in node.get_children():
		if child is HealthComponent:
			return child
	return null


func _ready() -> void:
	if has_server_authority(self):
		health = max_health


## Server only. Arguments are plain values (no node references) so they can be
## sent over the network unchanged. type names the cause, for example &"growth".
## source_peer is the peer that caused it, or 0 for the environment.
func apply_damage(amount: float, type: StringName = &"generic", source_peer: int = 0) -> void:
	if not has_server_authority(self) or amount <= 0.0 or not is_alive:
		return
	health -= amount
	damaged.emit(amount, type, source_peer)


func heal(amount: float) -> void:
	if not has_server_authority(self) or amount <= 0.0 or not is_alive:
		return
	health += amount


func kill() -> void:
	if has_server_authority(self):
		health = 0.0


## Brings a dead character back. Pass a negative value for full health.
func revive(restore_to := -1.0) -> void:
	if has_server_authority(self):
		health = max_health if restore_to < 0.0 else restore_to
