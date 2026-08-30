extends CharacterBody2D

@export var speed: float = 90.0
@export var max_health: int = 3
@export var contact_damage: int = 1
@export var contact_range: float = 24.0
@export var attack_interval: float = 1.0
## Aviso visual (pulso amarillo, ver Fx.telegraph_attack) antes de que el
## golpe de contacto conecte de verdad — antes el daño era instantáneo al
## tocar, sin ningún aviso para poder esquivar.
@export var attack_telegraph_time: float = 0.25

var health: int
var _player: Node2D
var _attack_timer: float = 0.0
var _telegraphing: bool = false
var _telegraph_time_left: float = 0.0

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

	_attack_timer -= delta

	if _telegraphing:
		_telegraph_time_left -= delta
		if _telegraph_time_left <= 0.0:
			_telegraphing = false
			# El jugador pudo haberse alejado durante el windup — recién acá
			# se chequea el rango de verdad, el telegraph no garantiza el hit.
			if to_player.length() <= contact_range and _player.has_method("take_damage"):
				_player.take_damage(contact_damage)
			_attack_timer = attack_interval
	elif to_player.length() <= contact_range and _attack_timer <= 0.0 and contact_damage > 0:
		_telegraphing = true
		_telegraph_time_left = attack_telegraph_time
		Fx.telegraph_attack(_anim, attack_telegraph_time)

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		died.emit()
		Fx.play_death(self, _anim)
		return
	Fx.flash_damage(_anim)
