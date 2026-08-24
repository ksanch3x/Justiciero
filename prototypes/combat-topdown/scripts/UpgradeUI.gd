extends CanvasLayer

signal chosen

var _player: CharacterBody2D

@onready var _buttons_container: VBoxContainer = $Panel/Root/VBoxContainer

func _ready() -> void:
	hide()

func show_choices(player: CharacterBody2D) -> void:
	_player = player

	for child in _buttons_container.get_children():
		child.queue_free()

	for upgrade in UpgradePool.roll(3):
		var btn := Button.new()
		btn.text = upgrade["name"]
		btn.custom_minimum_size = Vector2(280, 40)
		btn.pressed.connect(_on_upgrade_picked.bind(upgrade))
		_buttons_container.add_child(btn)

	show()

func _on_upgrade_picked(upgrade: Dictionary) -> void:
	upgrade["apply"].call(_player)
	hide()
	chosen.emit()
