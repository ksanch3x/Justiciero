extends CharacterBody2D

@export var speed: float = 220.0
@export var fire_rate: float = 0.2
@export var max_health: int = 5
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")

var bullet_damage: int = 1
var bullet_count: int = 1

var health: int
var fire_cooldown: float = 0.0

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

	velocity = input_vec * speed
	move_and_slide()

	if input_vec.length() > 0.1:
		if not _anim.is_playing():
			_anim.play("walk")
	else:
		_anim.stop()
		_anim.frame = 0

	var aim_dir := get_global_mouse_position() - global_position
	if abs(aim_dir.x) > 1.0:
		_anim.flip_h = aim_dir.x < 0.0

	_weapon_pivot.rotation = aim_dir.angle()
	_gun_sprite.flip_v = aim_dir.x < 0.0

	fire_cooldown -= delta
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0:
		_shoot()
		fire_cooldown = fire_rate

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
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0:
		died.emit()
		queue_free()
