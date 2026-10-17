extends CanvasLayer

@onready var label: Label = $MarginContainer/Label

var collected := 0
var total := 0

func _ready() -> void:
	total = get_tree().get_nodes_in_group("coins").size()
	Events.coin_collected.connect(_on_coin_collected)
	_update_label()

func _on_coin_collected() -> void:
	collected += 1
	_update_label()

func _update_label() -> void:
	label.text = "Coins: %d / %d" % [collected,total]
