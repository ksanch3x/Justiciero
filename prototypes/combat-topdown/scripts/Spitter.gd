extends CharacterBody2D

## Enemigo a distancia: se acerca lentamente al jugador y, dentro de
## shoot_range, dispara proyectiles con su propio cooldown. No mantiene
## distancia ni se repliega (kiting) — sigue acercándose incluso mientras
## dispara, según diseño confirmado.
##
## Misma máquina de estados PATROL/ALERT/CHASE que Enemy.gd (Fase 2 del GDD,
## ver STATUS.md) — antes perseguía/disparaba desde el instante en que
## spawneaba, quedó desalineado cuando se agregó la máquina de estados a
## Enemy.gd/Runner.gd. Sin estado ATTACK propio: CHASE ya incluye el
## disparo a distancia (shoot_range), no hace falta un estado aparte.
enum State { PATROL, ALERT, CHASE }

@export var speed: float = 70.0
@export var patrol_speed: float = 35.0
@export var max_health: int = 2
@export var contact_damage: int = 0
@export var contact_range: float = 20.0
@export var attack_interval: float = 1.0
@export var shoot_range: float = 220.0
@export var fire_rate: float = 1.4
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
@export var bullet_speed: float = 380.0
@export var bullet_damage: int = 1
## Cono de visión real (mismo criterio que Enemy.gd) en vez de círculo por
## distancia — ver _can_see_player().
@export var detection_range: float = 260.0
@export var lose_track_range: float = 340.0
@export var patrol_radius: float = 80.0
@export var alert_time: float = 0.4
@export var view_angle: float = 100.0

## Layer física de las balas enemigas ("enemy_bullet"), separada de la
## layer=4 que usan las balas del jugador para no chocar entre sí.
const ENEMY_BULLET_LAYER: int = 16

var health: int
var _player: Node2D
var _attack_timer: float = 0.0
var _fire_timer: float = 0.0

var _state: State = State.PATROL
var _spawn_position: Vector2
var _spawn_captured: bool = false
var _patrol_target: Vector2
var _alert_time_left: float = 0.0
var _facing: Vector2 = Vector2.DOWN

signal died
## GDD 2.3, letal vs. no letal — ver comentario largo en Enemy.gd.
signal knocked_out

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

	# global_position todavía es (0,0) durante _ready() — Main.gd la fija
	# recién DESPUÉS de add_child() (cuidado técnico #3 de STATUS.md).
	if not _spawn_captured:
		_spawn_captured = true
		_spawn_position = global_position
		_pick_patrol_target()

	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()

	_update_state(delta, dist, to_player)

	match _state:
		State.PATROL:
			_process_patrol()
		State.ALERT:
			velocity = Vector2.ZERO
		State.CHASE:
			velocity = to_player.normalized() * speed
	move_and_slide()

	var facing: Vector2 = velocity if _state == State.PATROL else to_player
	if facing.length() > 1.0:
		_facing = facing.normalized()
	if abs(facing.x) > 1.0:
		_anim.flip_h = facing.x < 0.0
	queue_redraw()

	if _state != State.CHASE:
		return

	_attack_timer -= delta
	if dist <= contact_range and contact_damage > 0 and _attack_timer <= 0.0:
		if _player.has_method("take_damage"):
			_player.take_damage(contact_damage)
		_attack_timer = attack_interval

	_fire_timer -= delta
	if dist <= shoot_range and _fire_timer <= 0.0:
		_shoot(to_player.normalized())
		_fire_timer = fire_rate

func _update_state(delta: float, dist_to_player: float, to_player: Vector2) -> void:
	match _state:
		State.PATROL:
			if _can_see_player(dist_to_player, to_player):
				_state = State.ALERT
				_alert_time_left = alert_time
		State.ALERT:
			_alert_time_left -= delta
			if dist_to_player > lose_track_range:
				_state = State.PATROL
				_pick_patrol_target()
			elif _alert_time_left <= 0.0:
				_state = State.CHASE
		State.CHASE:
			if dist_to_player > lose_track_range:
				_state = State.ALERT
				_alert_time_left = alert_time

## Cono de visión real — ver comentario largo en Enemy.gd.
func _can_see_player(dist_to_player: float, to_player: Vector2) -> bool:
	if dist_to_player > detection_range:
		return false
	if _player.has_method("is_hidden_from") and _player.is_hidden_from(global_position):
		return false
	if dist_to_player < 1.0:
		return true
	var half_angle: float = deg_to_rad(view_angle / 2.0)
	return abs(_facing.angle_to(to_player)) <= half_angle

func _process_patrol() -> void:
	var to_target: Vector2 = _patrol_target - global_position
	if to_target.length() <= 6.0:
		_pick_patrol_target()
		velocity = Vector2.ZERO
		return
	velocity = to_target.normalized() * patrol_speed

func _pick_patrol_target() -> void:
	var offset := Vector2(randf_range(-patrol_radius, patrol_radius), randf_range(-patrol_radius, patrol_radius))
	_patrol_target = _spawn_position + offset

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
	# Golpe por sorpresa alerta de inmediato, igual que en Enemy.gd/Police.gd.
	if _state == State.PATROL or _state == State.ALERT:
		_state = State.CHASE

## GDD 2.3: neutraliza sin matar — ver comentario largo en Enemy.gd.
func knockout() -> void:
	if health <= 0:
		return
	health = 0
	knocked_out.emit()
	Fx.play_death(self, _anim)

## Debug visual del cono de visión — ver comentario largo en Enemy.gd.
func _draw() -> void:
	var color: Color
	match _state:
		State.PATROL:
			color = Color(0.3, 1.0, 0.3, 0.13)
		State.ALERT:
			color = Color(1.0, 0.9, 0.2, 0.16)
		_:
			color = Color(1.0, 0.2, 0.2, 0.18)
	var dir: Vector2 = _facing if _facing.length() > 0.01 else Vector2.DOWN
	var base_angle: float = dir.angle()
	var half: float = deg_to_rad(view_angle / 2.0)
	var steps: int = 14
	var points: PackedVector2Array = [Vector2.ZERO]
	for i in range(steps + 1):
		var a: float = base_angle - half + (2.0 * half) * (float(i) / float(steps))
		points.append(Vector2(cos(a), sin(a)) * detection_range)
	draw_colored_polygon(points, color)
