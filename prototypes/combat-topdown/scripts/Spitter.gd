extends CharacterBody2D

## Enemigo a distancia: se acerca lentamente al jugador y, dentro de
## shoot_range, dispara proyectiles con su propio cooldown. No mantiene
## distancia ni se repliega (kiting) — sigue acercándose incluso mientras
## dispara, según diseño confirmado.
@export var speed: float = 70.0
@export var max_health: int = 2
@export var contact_damage: int = 0
@export var contact_range: float = 20.0
@export var attack_interval: float = 1.0
@export var shoot_range: float = 220.0
@export var fire_rate: float = 1.4
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
@export var bullet_speed: float = 380.0
@export var bullet_damage: int = 1

## Layer física de las balas enemigas ("enemy_bullet"), separada de la
## layer=4 que usan las balas del jugador para no chocar entre sí.
const ENEMY_BULLET_LAYER: int = 16

var health: int
var _player: Node2D
var _attack_timer: float = 0.0
var _fire_timer: float = 0.0

signal died

@onready var _anim: AnimatedSprite2D = $Visual

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	_player = get_tree().get_first_node_in_group("player")
	_anim.play("walk")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return

	var to_player := _player.global_position - global_position
	velocity = to_player.normalized() * speed
	move_and_slide()

	if abs(to_player.x) > 1.0:
		_anim.flip_h = to_player.x < 0.0

	var dist := to_player.length()

	_attack_timer -= delta
	if dist <= contact_range and contact_damage > 0 and _attack_timer <= 0.0:
		if _player.has_method("take_damage"):
			_player.take_damage(contact_damage)
		_attack_timer = attack_interval

	_fire_timer -= delta
	if dist <= shoot_range and _fire_timer <= 0.0:
		_shoot(to_player.normalized())
		_fire_timer = fire_rate

func _shoot(dir: Vector2) -> void:
	var bullet := bullet_scene.instantiate()
	bullet.direction = dir
	bullet.shooter = self
	bullet.damage = bullet_damage
	bullet.speed = bullet_speed
	bullet.target_mask = 1
	bullet.collision_layer = ENEMY_BULLET_LAYER
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		died.emit()
		Fx.play_death(self, _anim)
		return
	Fx.flash_damage(_anim)
