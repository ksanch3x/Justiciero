extends CharacterBody2D

## Facción Policía (GDD games/justiciero/GDD.md, secciones 2.1/2.2/5.1) —
## primera versión: reacciona al Nivel de Alerta de FactionManager.gd en vez
## de perseguir al jugador por proximidad directa como Enemy.gd. Estructura
## de movimiento/telegraph calcada de Enemy.gd (mismo patrón de máquina de
## estados, mismo Fx.telegraph_attack) pero es un script propio porque el
## disparador de la persecución es otro: un nivel de alerta global, no
## distancia. Sin arresto/no-letal todavía (GDD 2.3) — por ahora ATTACK
## hace daño de contacto igual que un enemigo común.
enum State { PATROL, INVESTIGATE, PURSUE, ATTACK }

@export var speed: float = 85.0
@export var patrol_speed: float = 40.0
@export var max_health: int = 4
@export var contact_damage: int = 1
@export var contact_range: float = 22.0
@export var attack_interval: float = 1.0
@export var attack_telegraph_time: float = 0.3
@export var patrol_radius: float = 90.0
## Cuánto se queda "mirando alrededor" en el punto de ruido antes de
## rendirse y volver a PATROL, si el nivel de alerta no siguió subiendo.
@export var investigate_timeout: float = 4.0

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
	# aparte para diferenciarlo cuando haga falta (letal/no letal, GDD 2.3).
	add_to_group("enemy")
	add_to_group("police")
	_player = get_tree().get_first_node_in_group("player")
	_anim.play("walk")
	FactionManager.level_changed.connect(_on_alert_level_changed)

func _on_alert_level_changed(new_level: int, _old_level: int) -> void:
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

	var to_player: Vector2 = _player.global_position - global_position
	var dist_to_player: float = to_player.length()

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
	move_and_slide()

	# Mira hacia donde camina en PATROL/INVESTIGATE; hacia el jugador en
	# PURSUE/ATTACK, ya lo tiene detectado.
	var chasing: bool = _state == State.PURSUE or _state == State.ATTACK
	var facing: Vector2 = to_player if chasing else velocity
	if abs(facing.x) > 1.0:
		_anim.flip_h = facing.x < 0.0

	_attack_timer -= delta

	if _telegraphing:
		_telegraph_time_left -= delta
		if _telegraph_time_left <= 0.0:
			_telegraphing = false
			if dist_to_player <= contact_range and _player.has_method("take_damage"):
				_player.take_damage(contact_damage)
			_attack_timer = attack_interval
	elif _state == State.ATTACK and dist_to_player <= contact_range and _attack_timer <= 0.0 and contact_damage > 0:
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

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		health = 0
		health_changed.emit(health, max_health)
		died.emit()
		Fx.play_death(self, _anim)
		return
	health_changed.emit(health, max_health)
	Fx.flash_damage(_anim)
	# Un golpe por sorpresa alerta al policía de inmediato, igual que en
	# Enemy.gd — no depende de que el nivel de alerta global haya subido.
	if _state == State.PATROL or _state == State.INVESTIGATE:
		_state = State.PURSUE
