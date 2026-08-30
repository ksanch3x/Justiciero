extends CharacterBody2D

## Facción Policía (GDD games/justiciero/GDD.md, secciones 2.1/2.2/5.1) —
## reacciona al Nivel de Alerta de FactionManager.gd para perseguir al
## jugador (no por proximidad directa como Enemy.gd), Y además pelea con
## Criminal.gd si se cruzan de cerca (Triángulo de Facciones, GDD 2.1).
## Estructura de movimiento/telegraph calcada de Enemy.gd.
##
## Regla clave para que el Triángulo no se coma solo la misión (feedback
## directo del usuario: "hay que regular que no se maten fácilmente sino me
## quedo sin misión"): el daño entre IA (Policía↔Criminal, `from_ai=true`
## en take_damage()) JAMÁS mata — a baja vida el que pierde HUYE (estado
## FLEE) en vez de morir. Solo el jugador puede eliminar de verdad a un
## Policía o un Criminal. Esto evita que el triángulo vacíe el mapa antes
## de que el jugador llegue a interactuar con nada.
enum State { PATROL, INVESTIGATE, PURSUE, ATTACK, FIGHT_RIVAL, FLEE }

@export var speed: float = 95.0
@export var patrol_speed: float = 40.0
## Bastante más duro que un Grunt base (max_health=3): un policía debería
## sentirse como una amenaza real, no como un enemigo de oleada más — el
## jugador puede reducir Alerta rompiendo línea de visión en vez de tener
## que pelear siempre.
@export var max_health: int = 15
@export var contact_damage: int = 3
@export var contact_range: float = 22.0
@export var attack_interval: float = 0.85
@export var attack_telegraph_time: float = 0.3
@export var patrol_radius: float = 90.0
## Cuánto se queda "mirando alrededor" en el punto de ruido antes de
## rendirse y volver a PATROL, si el nivel de alerta no siguió subiendo.
@export var investigate_timeout: float = 4.0
## Radio "de encuentro" con un Criminal — a propósito chico: esto es un
## cruce oportunista al patrullar/perseguir, no un imán que busca criminales
## por todo el mapa (eso volvería la pelea entre facciones demasiado
## frecuente y competiría con perseguir al jugador).
@export var faction_detection_range: float = 90.0
@export var flee_speed: float = 130.0
@export var flee_time: float = 3.0
## Por debajo de este % de vida MÁXIMA, un golpe de otra IA hace huir en
## vez de seguir peleando (nunca morir, ver comentario de arriba).
@export var flee_health_ratio: float = 0.3

var health: int
var _player: Node2D
var _state: State = State.PATROL
var _spawn_position: Vector2
var _spawn_captured: bool = false
var _patrol_target: Vector2
var _investigate_timer: float = 0.0
var _attack_timer: float = 0.0
var _telegraphing: bool = false
var _telegraph_time_left: float = 0.0
var _rival_target: Node2D = null
var _flee_timer: float = 0.0
var _flee_dir: Vector2 = Vector2.ZERO

signal died
signal health_changed(current: int, max_health: int)

@onready var _anim: AnimatedSprite2D = $Visual

func _ready() -> void:
	health = max_health
	# Grupo "enemy" a propósito: así el melee/dash-push del jugador
	# (Player._melee_attack()/_apply_dash_area_effect(), que iteran
	# get_nodes_in_group("enemy")) funcionan contra la policía sin tocar
	# ese código — Main.gd no escanea ese grupo para las oleadas, así que no
	# hay riesgo de que un policía cuente como enemigo de oleada. "police"
	# aparte para que Criminal.gd la encuentre con get_nodes_in_group.
	add_to_group("enemy")
	add_to_group("police")
	_player = get_tree().get_first_node_in_group("player")
	_anim.play("walk")
	FactionManager.level_changed.connect(_on_alert_level_changed)

func _on_alert_level_changed(new_level: int, _old_level: int) -> void:
	# Una pelea contra un Criminal (o huyendo de una) no se interrumpe por
	# un cambio de Alerta — se retoma el rastreo del jugador después.
	if _state == State.FIGHT_RIVAL or _state == State.FLEE:
		return
	if new_level == FactionManager.AlertLevel.IGNORED:
		if _state != State.PATROL:
			_state = State.PATROL
			_pick_patrol_target()
		return
	if new_level >= FactionManager.AlertLevel.CHASE:
		_state = State.PURSUE
		return
	# SUSPICION: solo interrumpe una patrulla tranquila — si ya está
	# investigando/persiguiendo, ese estado decide cuándo bajar de nivel.
	if _state == State.PATROL:
		_state = State.INVESTIGATE
		_investigate_timer = investigate_timeout

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

	# Encuentro oportunista con un Criminal cercano — no interrumpe una
	# persecución activa del jugador (PURSUE/ATTACK), sí una patrulla o
	# investigación tranquila.
	if _state != State.PURSUE and _state != State.ATTACK:
		var rival := _find_nearby_rival()
		if rival != null:
			_state = State.FIGHT_RIVAL
			_rival_target = rival
	if _state == State.FIGHT_RIVAL:
		if not is_instance_valid(_rival_target) or global_position.distance_to(_rival_target.global_position) > faction_detection_range * 1.5:
			_rival_target = null
			_resume_after_distraction()

	var to_player: Vector2 = _player.global_position - global_position
	var dist_to_player: float = to_player.length()

	var target: Node2D = _rival_target if _state == State.FIGHT_RIVAL and is_instance_valid(_rival_target) else _player
	var to_target: Vector2 = target.global_position - global_position
	var dist_to_target: float = to_target.length()

	match _state:
		State.PATROL:
			_process_patrol()
		State.INVESTIGATE:
			_process_investigate(delta)
		State.PURSUE:
			if dist_to_player <= contact_range:
				_state = State.ATTACK
			else:
				velocity = to_player.normalized() * speed
		State.ATTACK:
			velocity = Vector2.ZERO
			if dist_to_player > contact_range:
				_state = State.PURSUE
		State.FIGHT_RIVAL:
			if dist_to_target <= contact_range:
				velocity = Vector2.ZERO
			else:
				velocity = to_target.normalized() * speed
	move_and_slide()

	var chasing: bool = _state == State.PURSUE or _state == State.ATTACK or _state == State.FIGHT_RIVAL
	var facing: Vector2 = to_target if chasing else velocity
	if abs(facing.x) > 1.0:
		_anim.flip_h = facing.x < 0.0

	_attack_timer -= delta

	var attacking_state: bool = _state == State.ATTACK or (_state == State.FIGHT_RIVAL and dist_to_target <= contact_range)
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
	elif attacking_state and _attack_timer <= 0.0 and contact_damage > 0:
		_telegraphing = true
		_telegraph_time_left = attack_telegraph_time
		Fx.telegraph_attack(_anim, attack_telegraph_time)

func _process_patrol() -> void:
	var to_target: Vector2 = _patrol_target - global_position
	if to_target.length() <= 6.0:
		_pick_patrol_target()
		velocity = Vector2.ZERO
		return
	velocity = to_target.normalized() * patrol_speed

## Camina hacia last_noise_position y se queda ahí `investigate_timeout`
## segundos "mirando alrededor" antes de rendirse — el nivel de alerta
## puede escalar a CHASE en cualquier momento vía _on_alert_level_changed,
## que corta esto de inmediato.
func _process_investigate(delta: float) -> void:
	var target: Vector2 = FactionManager.last_noise_position
	var to_target: Vector2 = target - global_position
	if to_target.length() <= 10.0:
		velocity = Vector2.ZERO
		_investigate_timer -= delta
		if _investigate_timer <= 0.0:
			_state = State.PATROL
			_pick_patrol_target()
		return
	velocity = to_target.normalized() * speed

func _pick_patrol_target() -> void:
	var offset := Vector2(randf_range(-patrol_radius, patrol_radius), randf_range(-patrol_radius, patrol_radius))
	_patrol_target = _spawn_position + offset

## Busca el Criminal vivo más cercano dentro de faction_detection_range.
func _find_nearby_rival() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = faction_detection_range
	for node in get_tree().get_nodes_in_group("criminal"):
		if not is_instance_valid(node) or node.health <= 0:
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d <= nearest_dist:
			nearest = node
			nearest_dist = d
	return nearest

## Después de que termina una pelea con un Criminal (huyó/murió/se alejó) o
## de terminar de huir, retoma el comportamiento que le corresponde según
## el Nivel de Alerta actual — no simplemente PATROL, porque el nivel pudo
## haber subido mientras estaba distraído peleando.
func _resume_after_distraction() -> void:
	var lvl: int = FactionManager.level
	if lvl >= FactionManager.AlertLevel.CHASE:
		_state = State.PURSUE
	elif lvl == FactionManager.AlertLevel.SUSPICION:
		_state = State.INVESTIGATE
		_investigate_timer = investigate_timeout
	else:
		_state = State.PATROL
		_pick_patrol_target()

func _process_flee(delta: float) -> void:
	_flee_timer -= delta
	velocity = _flee_dir * flee_speed
	move_and_slide()
	if _flee_timer <= 0.0:
		_resume_after_distraction()

func _start_flee(threat_position: Vector2) -> void:
	_state = State.FLEE
	_flee_timer = flee_time
	_rival_target = null
	var away: Vector2 = global_position - threat_position
	_flee_dir = away.normalized() if away.length() > 1.0 else Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

## `from_ai=true` es daño de otra IA (Criminal.gd) — nunca mata, a baja
## vida hace huir (ver comentario grande al principio del archivo). Los
## demás llamadores (Player._melee_attack(), Bullet.gd) no pasan ese
## parámetro, así que el jugador siempre puede matar de verdad.
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
	# Un golpe por sorpresa del jugador alerta al policía de inmediato,
	# igual que en Enemy.gd — no depende de que el nivel de alerta global
	# haya subido.
	if _state == State.PATROL or _state == State.INVESTIGATE:
		_state = State.PURSUE
