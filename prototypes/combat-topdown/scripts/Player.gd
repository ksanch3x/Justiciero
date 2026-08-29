extends CharacterBody2D

@export var speed: float = 220.0
@export var fire_rate: float = 0.2
@export var max_health: int = 5
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")

## Dash / esquiva (GDD 2.3: movilidad con costo, no i-frames infinitos).
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.7
@export var dash_invulnerable: bool = true

var bullet_damage: int = 1
var bullet_count: int = 1

var health: int
var fire_cooldown: float = 0.0

var is_dashing: bool = false
var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT
var _last_move_dir: Vector2 = Vector2.RIGHT
var is_invulnerable: bool = false

signal health_changed(current: int, max: int)
signal died

@onready var _anim: AnimatedSprite2D = $Visual
@onready var _weapon_pivot: Node2D = $WeaponPivot
@onready var _gun_sprite: Sprite2D = $WeaponPivot/Gun

func _ready() -> void:
	health = max_health
	add_to_group("player")

func _physics_process(delta: float) -> void:
	var input_vec := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	if input_vec.length() > 0.1:
		_last_move_dir = input_vec.normalized()

	dash_cooldown_left -= delta
	if is_dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			_end_dash()
	elif Input.is_action_just_pressed("dash") and dash_cooldown_left <= 0.0:
		_start_dash()

	if is_dashing:
		velocity = dash_direction * dash_speed
	else:
		velocity = input_vec * speed
	move_and_slide()

	# El disparo se deshabilita durante el dash: es una esquiva rápida,
	# no tendría sentido apuntar con precisión mientras se ejecuta.
	if input_vec.length() > 0.1 and not is_dashing:
		if not _anim.is_playing():
			_anim.play("walk")
	elif not is_dashing:
		_anim.stop()
		_anim.frame = 0

	var aim_dir := get_global_mouse_position() - global_position
	if abs(aim_dir.x) > 1.0:
		_anim.flip_h = aim_dir.x < 0.0

	_weapon_pivot.rotation = aim_dir.angle()
	_gun_sprite.flip_v = aim_dir.x < 0.0

	fire_cooldown -= delta
	if not is_dashing and Input.is_action_pressed("shoot") and fire_cooldown <= 0.0:
		_shoot()
		fire_cooldown = fire_rate

func _start_dash() -> void:
	var dir := _last_move_dir
	if dir.length() < 0.1:
		dir = (get_global_mouse_position() - global_position)
		if dir.length() < 0.1:
			dir = Vector2.RIGHT
	dash_direction = dir.normalized()

	is_dashing = true
	dash_time_left = dash_duration
	dash_cooldown_left = dash_cooldown
	if dash_invulnerable:
		is_invulnerable = true
	_anim.modulate.a = 0.5

func _end_dash() -> void:
	is_dashing = false
	is_invulnerable = false
	_anim.modulate.a = 1.0

func _shoot() -> void:
	var base_dir := (get_global_mouse_position() - global_position).normalized()
	var spread_deg := 8.0

	for i in range(bullet_count):
		var offset := 0.0
		if bullet_count > 1:
			offset = deg_to_rad(spread_deg) * (i - float(bullet_count - 1) / 2.0)
		var dir := base_dir.rotated(offset)

		var bullet := bullet_scene.instantiate()
		bullet.direction = dir
		bullet.shooter = self
		bullet.damage = bullet_damage
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = global_position

func heal_to_full() -> void:
	health = max_health
	health_changed.emit(health, max_health)

func take_damage(amount: int) -> void:
	if is_invulnerable:
		return
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0:
		died.emit()
		queue_free()
