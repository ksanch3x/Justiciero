extends Node2D

@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@export var base_enemies_per_wave: int = 4
@export var enemies_increment_per_wave: int = 2
@export var enemy_health_scale_per_wave: float = 0.15
@export var time_between_spawns: float = 0.4

var wave_number: int = 0
var enemies_to_spawn: int = 0
var enemies_alive: int = 0
var _spawn_timer: float = 0.0
var _choosing_upgrade: bool = false

@onready var _player: CharacterBody2D = $Player
@onready var _hud: Label = $HUD/Label
@onready var _spawn_points: Node2D = $SpawnPoints
@onready var _upgrade_ui: CanvasLayer = $UpgradeUI

func _ready() -> void:
	_player.health_changed.connect(_on_player_health_changed)
	_player.died.connect(_on_player_died)
	_upgrade_ui.chosen.connect(_on_upgrade_chosen)
	_start_next_wave()

func _process(delta: float) -> void:
	if _choosing_upgrade:
		return

	if enemies_to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_enemy()
			enemies_to_spawn -= 1
			_spawn_timer = time_between_spawns
	elif enemies_alive <= 0:
		_show_upgrade_selection()

	_update_hud()

func _start_next_wave() -> void:
	wave_number += 1
	enemies_to_spawn = base_enemies_per_wave + (wave_number - 1) * enemies_increment_per_wave
	enemies_alive = 0
	_spawn_timer = 0.0

func _spawn_enemy() -> void:
	var points := _spawn_points.get_children()
	if points.is_empty():
		return
	var point: Node2D = points[randi() % points.size()]

	var enemy := enemy_scene.instantiate()
	var scale_factor := 1.0 + float(wave_number - 1) * enemy_health_scale_per_wave
	enemy.max_health = int(ceil(enemy.max_health * scale_factor))
	enemy.died.connect(_on_enemy_died)

	add_child(enemy)
	enemy.global_position = point.global_position
	enemies_alive += 1

func _on_enemy_died() -> void:
	enemies_alive -= 1

func _show_upgrade_selection() -> void:
	if _player.has_wave_regen and _player.health < _player.max_health:
		_player.health = min(_player.max_health, _player.health + 1)
		_player.health_changed.emit(_player.health, _player.max_health)
	_choosing_upgrade = true
	_upgrade_ui.show_choices(_player)

func _on_upgrade_chosen() -> void:
	_choosing_upgrade = false
	_start_next_wave()

func _on_player_health_changed(_current: int, _max_hp: int) -> void:
	_update_hud()

func _on_player_died() -> void:
	_hud.text = "Muerto en oleada %d. Presiona R para reiniciar." % wave_number
	set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()

func _update_hud() -> void:
	var hp: int = 0
	var max_hp: int = 0
	if is_instance_valid(_player):
		hp = _player.health
		max_hp = _player.max_health
	var alive_or_pending := enemies_alive + enemies_to_spawn
	_hud.text = "Oleada: %d   Vida: %d/%d   Enemigos restantes: %d" % [wave_number, hp, max_hp, alive_or_pending]
