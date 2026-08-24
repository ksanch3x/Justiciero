extends Node2D

@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@export var spawn_interval: float = 2.5
@export var max_enemies: int = 12

var _spawn_timer: float = 0.0
var _kill_count: int = 0

@onready var _player: Node2D = $Player
@onready var _hud: Label = $HUD/Label
@onready var _spawn_points: Node2D = $SpawnPoints

func _ready() -> void:
	_player.health_changed.connect(_on_player_health_changed)
	_player.died.connect(_on_player_died)
	_update_hud()

func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and get_tree().get_nodes_in_group("enemy").size() < max_enemies:
		_spawn_enemy()
		_spawn_timer = spawn_interval

func _spawn_enemy() -> void:
	var points := _spawn_points.get_children()
	if points.is_empty():
		return
	var point: Node2D = points[randi() % points.size()]
	var enemy := enemy_scene.instantiate()
	add_child(enemy)
	enemy.global_position = point.global_position
	enemy.died.connect(_on_enemy_died)

func _on_enemy_died() -> void:
	_kill_count += 1
	_update_hud()

func _on_player_health_changed(current: int, max_hp: int) -> void:
	_update_hud()

func _on_player_died() -> void:
	_hud.text = "Muerto. Presiona R para reiniciar."
	set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()

func _update_hud() -> void:
	var hp := _player.health if is_instance_valid(_player) else 0
	_hud.text = "Vida: %d/%d   Enemigos eliminados: %d" % [hp, _player.max_health, _kill_count]
