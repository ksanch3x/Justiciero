extends CharacterBody2D

## Facción Criminal (GDD games/justiciero/GDD.md, sección 2.1) — protege
## territorio: ataca al jugador si lo detecta (por distancia, igual que
## Enemy.gd) y pelea con Police.gd si se cruzan de cerca (interpretación
## simplificada de "ataca a la policía si es vista cometiendo un crimen
## frente a ellos" — acá directamente "policía cerca = zona hostil", sin
## sistema de testigos/crimen todavía). Ver Police.gd para el resto del
## Triángulo de Facciones — misma estructura, complemento simétrico.
##
## Regla clave (igual que en Police.gd): el daño entre IA nunca mata —
## a baja vida el que pierde HUYE (FLEE) en vez de morir, así el Triángulo
## no vacía la misión solo. Solo el jugador puede eliminar de verdad a un
## Criminal.
enum State { PATROL, DEFEND, FIGHT_RIVAL, FLEE }

@export var speed: float = 90.0
@export var patrol_speed: float = 40.0
@export var max_health: int = 6
@export var contact_damage: int = 2
@export var contact_range: float = 22.0
@export var attack_interval: float = 1.0
@export var attack_telegraph_time: float = 0.25
## Subido de 90 — ver comentario largo en Police.gd.
@export var patrol_radius: float = 170.0
@export var detection_range: float = 220.0
@export var lose_track_range: float = 300.0
## Radio "de encuentro" con un Policía — chico a propósito, ver comentario
## equivalente en Police.gd (encuentro oportunista, no imán de mapa entero).
@export var faction_detection_range: float = 130.0
@export var flee_speed: float = 130.0
@export var flee_time: float = 3.0
@export var flee_health_ratio: float = 0.3
## Cono de visión real (mismo criterio que Enemy.gd) para detectar al
## jugador — no aplica al encuentro con Policía, ese sigue siendo por
## radio de cercanía (FIGHT_RIVAL no es sigilo, es un choque de facciones).
@export var view_angle: float = 100.0

var health: int
var _player: Node2D
var _state: State = State.PATROL
var _spawn_position: Vector2
var _spawn_captured: bool = false
var _patrol_target: Vector2
var _facing: Vector2 = Vector2.DOWN
var _attack_timer: float = 0.0
var _telegraphing: bool = false
var _telegraph_time_left: float = 0.0
var _rival_target: Node2D = null
var _flee_timer: float = 0.0
var _flee_dir: Vector2 = Vector2.ZERO

signal died
signal health_changed(current: int, max_health: int)
## GDD 2.3, letal vs. no letal — ver comentario largo en Police.gd/Enemy.gd.
signal knocked_out

@onready var _anim: AnimatedSprite2D = $Visual

func _ready() -> void:
	health = max_health
	# "enemy" para que el melee/dash del jugador (que iteran
	# get_nodes_in_group("enemy")) funcionen sin tocar ese código, igual que
	# Police.gd — Main.gd no escanea ese grupo para las oleadas. "criminal"
	# aparte para que Police.gd la encuentre.
	add_to_group("enemy")
	add_to_group("criminal")
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

	if _state == State.FLEE:
		_process_flee(delta)
		return

	var to_player: Vector2 = _player.global_position - global_position
	var dist_to_player: float = to_player.length()

	# El jugador tiene prioridad: solo se busca un encuentro con Policía
	# si no está ya defendiéndose de/atacando al jugador.
	if _state != State.DEFEND:
		var rival := _find_nearby_rival()
		if rival != null:
			_state = State.FIGHT_RIVAL
			_rival_target = rival
	if _state == State.FIGHT_RIVAL:
		if not is_instance_valid(_rival_target) or global_position.distance_to(_rival_target.global_position) > faction_detection_range * 1.5:
			_rival_target = null
			_state = State.PATROL
			_pick_patrol_target()

	match _state:
		State.PATROL:
			if _can_see_player(dist_to_player, to_player):
				_state = State.DEFEND
			else:
				_process_patrol()
		State.DEFEND:
			if dist_to_player > lose_track_range:
				_state = State.PATROL
				_pick_patrol_target()
			else:
				velocity = to_player.normalized() * speed
		State.FIGHT_RIVAL:
			pass # velocity se fija abajo, según distancia al rival

	var target: Node2D = _rival_target if _state == State.FIGHT_RIVAL and is_instance_valid(_rival_target) else _player
	var to_target: Vector2 = target.global_position - global_position
	var dist_to_target: float = to_target.length()
	if _state == State.FIGHT_RIVAL:
		if dist_to_target <= contact_range:
			velocity = Vector2.ZERO
		else:
			velocity = to_target.normalized() * speed
	move_and_slide()

	var chasing: bool = _state == State.DEFEND or _state == State.FIGHT_RIVAL
	var facing: Vector2 = to_target if chasing else velocity
	if facing.length() > 1.0:
		_facing = facing.normalized()
	if abs(facing.x) > 1.0:
		_anim.flip_h = facing.x < 0.0
	queue_redraw()

	_attack_timer -= delta

	var attacking_state: bool = _state == State.DEFEND or (_state == State.FIGHT_RIVAL and dist_to_target <= contact_range)
	if _telegraphing:
		_telegraph_time_left -= delta
		if _telegraph_time_left <= 0.0:
			_telegraphing = false
			if is_instance_valid(target) and global_position.distance_to(target.global_position) <= contact_range:
				if target == _player:
					if _player.has_method("take_damage"):
						_player.take_damage(contact_damage)
				elif target.has_method("take_damage"):
					target.take_damage(contact_damage, true)
			_attack_timer = attack_interval
	elif attacking_state and dist_to_target <= contact_range and _attack_timer <= 0.0 and contact_damage > 0:
		_telegraphing = true
		_telegraph_time_left = attack_telegraph_time
		Fx.telegraph_attack(_anim, attack_telegraph_time)

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

## El punto de patrulla se clampea al área jugable de la sala ACTIVA
## (Arena.clamp_point, autoload) — sin esto un spawn cerca de un borde
## podía elegir un destino detrás de la pared y el bot quedaba
## empujando contra ella sin llegar nunca. Antes el clamp era una
## constante local con el rectángulo viejo; ahora las salas tienen
## formas y tamaños distintos (ver RoomData.gd), así que los límites
## los publica Main en cada transición.
func _pick_patrol_target() -> void:
	var offset := Vector2(randf_range(-patrol_radius, patrol_radius), randf_range(-patrol_radius, patrol_radius))
	_patrol_target = Arena.clamp_point(_spawn_position + offset)

## Busca el Policía vivo más cercano dentro de faction_detection_range.
func _find_nearby_rival() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = faction_detection_range
	for node in get_tree().get_nodes_in_group("police"):
		if not is_instance_valid(node) or node.health <= 0:
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d <= nearest_dist:
			nearest = node
			nearest_dist = d
	return nearest

func _process_flee(delta: float) -> void:
	_flee_timer -= delta
	velocity = _flee_dir * flee_speed
	move_and_slide()
	queue_redraw()  # _draw() no pinta nada en FLEE, pero hay que refrescar
	# para que el cono de antes de huir no quede pegado en pantalla.
	if _flee_timer <= 0.0:
		_state = State.PATROL
		_pick_patrol_target()

func _start_flee(threat_position: Vector2) -> void:
	_state = State.FLEE
	_flee_timer = flee_time
	_rival_target = null
	var away: Vector2 = global_position - threat_position
	_flee_dir = away.normalized() if away.length() > 1.0 else Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

## `from_ai=true` es daño de Police.gd — nunca mata, a baja vida hace huir
## (ver comentario grande al principio del archivo). Player._melee_attack()
## y Bullet.gd no pasan ese parámetro, así que el jugador siempre puede
## matar de verdad.
func take_damage(amount: int, from_ai: bool = false) -> void:
	health -= amount
	if from_ai:
		if health <= int(float(max_health) * flee_health_ratio):
			health = max(1, health)
			health_changed.emit(health, max_health)
			Fx.flash_damage(_anim)
			var threat_pos: Vector2 = _rival_target.global_position if is_instance_valid(_rival_target) else global_position
			_start_flee(threat_pos)
			return
		health_changed.emit(health, max_health)
		Fx.flash_damage(_anim)
		return
	if health <= 0:
		health = 0
		health_changed.emit(health, max_health)
		died.emit()
		Fx.play_death(self, _anim)
		return
	health_changed.emit(health, max_health)
	Fx.flash_damage(_anim)
	if _state == State.PATROL:
		_state = State.DEFEND

## GDD 2.3: neutraliza sin matar — ver comentario de la señal knocked_out.
func knockout() -> void:
	if health <= 0:
		return
	health = 0
	health_changed.emit(health, max_health)
	knocked_out.emit()
	Fx.play_death(self, _anim)

## Debug visual del cono de visión — ver comentario largo en Enemy.gd.
## Naranja/rojizo en vez del verde/amarillo/rojo de Enemy.gd para que se
## distinga a simple vista de qué facción es el cono (Criminal vs Grunt).
func _draw() -> void:
	var color: Color
	match _state:
		State.PATROL:
			color = Color(1.0, 0.6, 0.2, 0.13)
		State.DEFEND, State.FIGHT_RIVAL:
			color = Color(1.0, 0.2, 0.2, 0.18)
		_:
			return
	var dir: Vector2 = _facing if _facing.length() > 0.01 else Vector2.DOWN
	var base_angle: float = dir.angle()
	var half: float = deg_to_rad(view_angle / 2.0)
	var steps: int = 14
	var points: PackedVector2Array = [Vector2.ZERO]
	for i in range(steps + 1):
		var a: float = base_angle - half + (2.0 * half) * (float(i) / float(steps))
		points.append(Vector2(cos(a), sin(a)) * detection_range)
	draw_colored_polygon(points, color)
