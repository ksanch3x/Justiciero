extends CanvasLayer

signal chosen

var _player: CharacterBody2D

@onready var _buttons_container: VBoxContainer = $Panel/Root/VBoxContainer

func _ready() -> void:
	hide()

## Muestra el panel de selección con hasta 3 mejoras del árbol disponibles
## para el progreso actual de `player`. Si no hay ninguna disponible, no
## muestra el panel: aplica directamente el "sin elección" avisando a Main
## vía la señal `chosen`, igual que si el jugador hubiese elegido algo.
func show_choices(player: CharacterBody2D) -> void:
	_player = player

	for child in _buttons_container.get_children():
		child.queue_free()

	var choices := UpgradeTree.roll(player.taken_upgrades, 3)
	if choices.is_empty():
		chosen.emit()
		return

	for upgrade in choices:
		var btn := Button.new()
		btn.text = "%s — %s" % [upgrade["name"], upgrade["desc"]]
		btn.custom_minimum_size = Vector2(280, 40)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_upgrade_picked.bind(upgrade))
		_buttons_container.add_child(btn)

	show()

func _on_upgrade_picked(upgrade: Dictionary) -> void:
	upgrade["apply"].call(_player)
	_player.taken_upgrades.append(upgrade["id"])
	hide()
	chosen.emit()
