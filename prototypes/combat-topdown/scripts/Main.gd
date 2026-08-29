extends Node2D

@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@export var spitter_scene: PackedScene = preload("res://scenes/Spitter.tscn")
@export var runner_scene: PackedScene = preload("res://scenes/Runner.tscn")
@export var base_enemies_per_wave: int = 4
@export var enemies_increment_per_wave: int = 2
@export var enemy_health_scale_per_wave: float = 0.15
## Escalado leve adicional del Grunt por oleada: velocidad (+3%/oleada,
## compuesto) y daño de contacto (+1 cada 4 oleadas). Deliberadamente más
## suave que el escalado de vida para no volver la curva injugable.
@export var enemy_speed_scale_per_wave: float = 0.03
@export var enemy_contact_damage_per_waves: int = 4
@export var time_between_spawns: float = 0.4

## Oleada desde la que cada tipo puede empezar a aparecer. Antes de eso
## solo spawnea el Grunt (comportamiento original).
const RUNNER_MIN_WAVE: int = 2
const SPITTER_MIN_WAVE: int = 3

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

## Elige qué escena spawnear esta vez. Pesos simples por oleada: el Grunt
## domina al principio y la proporción de Runner/Spitter crece con las
## oleadas, cada uno solo una vez habilitado (ver *_MIN_WAVE).
## Oleada 1:      Grunt 100
## Oleada 2-2:    Grunt 70 / Runner 30
## Oleada 3-4:    Grunt 55 / Runner 25 / Spitter 20
## Oleada 5+:     Grunt 40 / Runner 30 / Spitter 30
func _pick_enemy_scene() -> PackedScene:
	var runner_enabled := wave_number >= RUNNER_MIN_WAVE
	var spitter_enabled := wave_number >= SPITTER_MIN_WAVE

	if not runner_enabled and not spitter_enabled:
		return enemy_scene

	var grunt_weight := 70
	var runner_weight := 30 if runner_enabled else 0
	var spitter_weight := 0
	if spitter_enabled:
		if wave_number >= 5:
			grunt_weight = 40
			runner_weight = 30
			spitter_weight = 30
		else:
			grunt_weight = 55
			runner_weight = 25
			spitter_weight = 20

	var total := grunt_weight + runner_weight + spitter_weight
	var roll := randi() % total
	if roll < grunt_weight:
		return enemy_scene
	roll -= grunt_weight
	if roll < runner_weight:
		return runner_scene
	return spitter_scene

func _spawn_enemy() -> void:
	var points := _spawn_points.get_children()
	if points.is_empty():
		return
	var point: Node2D = points[randi() % points.size()]

	var scene := _pick_enemy_scene()
	var enemy := scene.instantiate()

	var health_scale := 1.0 + float(wave_number - 1) * enemy_health_scale_per_wave
	enemy.max_health = int(ceil(enemy.max_health * health_scale))

	# El escalado de speed/contact_damage solo aplica al Grunt (Enemy.gd);
	# Runner y Spitter ya tienen su propia curva de dificultad por diseño
	# (más rápido/más débil, o a distancia) y no se re-escalan acá.
	if scene == enemy_scene:
		var speed_scale := pow(1.0 + enemy_speed_scale_per_wave, wave_number - 1)
		enemy.speed = enemy.speed * speed_scale
		enemy.contact_damage = enemy.contact_damage + int(floor(float(wave_number - 1) / float(enemy_contact_damage_per_waves)))

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

	var ammo_text := ""
	if is_instance_valid(_player) and _player.has_ranged_weapon():
		if _player.is_reloading:
			ammo_text = "   Munición: recargando..."
		else:
			ammo_text = "   Munición: %d/%d" % [_player.current_ammo, _player.current_mag_size]

	_hud.text = "Oleada: %d   Vida: %d/%d   Enemigos restantes: %d%s" % [wave_number, hp, max_hp, alive_or_pending, ammo_text]
