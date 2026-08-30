extends CharacterBody2D

## Máquina de estados básica (GDD sección 5.1 / hoja de ruta Fase 2):
## Patrulla -> Alerta -> Persecución -> Ataque. Detección circular por
## distancia (GDD 5.1: "Área2D circular para el MVP"; cono de visión real
## con raycasts queda para después). Sin estado de Huida todavía — no lo
## pide ningún enemigo actual, se agrega cuando haga falta.
enum State { PATROL, ALERT, CHASE, ATTACK }

@export var speed: float = 90.0
@export var patrol_speed: float = 45.0
@export var max_health: int = 3
@export var contact_damage: int = 1
@export var contact_range: float = 24.0
@export var attack_interval: float = 1.0
## Aviso visual (pulso amarillo, ver Fx.telegraph_attack) antes de que el
## golpe de contacto conecte de verdad — antes el daño era instantáneo al
## tocar, sin ningún aviso para poder esquivar.
@export var attack_telegraph_time: float = 0.25
## Radio de detección circular (PATROL -> ALERT). Ver comentario del enum:
## esta ES la detección "Área2D circular" del GDD, implementada por
## distancia porque no hay Area2D/raycast todavía.
@export var detection_range: float = 260.0
## Si el jugador se aleja más que esto durante CHASE/ALERT, se pierde el
## rastro y vuelve a PATROL/ALERT. A propósito mayor que detection_range
## (histéresis) para que no oscile entrando/saliendo de CHASE justo en el
## borde del radio de detección.
@export var lose_track_range: float = 340.0
## Radio de paseo alrededor del punto de spawn mientras está en PATROL.
@export var patrol_radius: float = 80.0
## Demora entre detectar al jugador (PATROL) y arrancar la persecución de
## verdad (CHASE) — el "signo de exclamación" de la alerta.
@export var alert_time: float = 0.4

var health: int
var _player: Node2D
var _attack_timer: float = 0.0
var _telegraphing: bool = false
var _telegraph_time_left: float = 0.0

var _state: State = State.PATROL
var _spawn_position: Vector2
var _spawn_captured: bool = false
var _patrol_target: Vector2
var _alert_time_left: float = 0.0

signal died
## Emitida en take_damage() (tanto en daño normal como en el golpe que mata,
## con health ya clampeado a 0) para que quien quiera una barra de vida
## (el jefe, ver Main._spawn_boss()) no tenga que leer `health` por polling.
signal health_changed(current: int, max_health: int)
## GDD 2.3, letal vs. no letal: knockout() (llamado por Player._process_
## takedown()) emite ESTA señal en vez de `died` — a propósito distinta,
## para que nada que dependa de "murió de verdad" (como SaveManager.
## add_police_kill en Police.gd) se dispare con un noqueo.
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
	# Capturamos el punto de patrulla acá, en el primer frame de física, que
	# corre después de que la posición ya quedó bien puesta.
	if not _spawn_captured:
		_spawn_captured = true
		_spawn_position = global_position
		_pick_patrol_target()

	var to_player: Vector2 = _player.global_position - global_position
	var dist_to_player: float = to_player.length()

	_update_state(delta, dist_to_player)

	match _state:
		State.PATROL:
			_process_patrol()
		State.ALERT, State.ATTACK:
			velocity = Vector2.ZERO
		State.CHASE:
			velocity = to_player.normalized() * speed
	move_and_slide()

	# Mientras patrulla mira hacia donde camina; en cualquier otro estado ya
	# detectó al jugador y mira hacia él (incluso parado en ALERT/ATTACK).
	var facing: Vector2 = velocity if _state == State.PATROL else to_player
	if abs(facing.x) > 1.0:
		_anim.flip_h = facing.x < 0.0

	_attack_timer -= delta

	if _telegraphing:
		_telegraph_time_left -= delta
		if _telegraph_time_left <= 0.0:
			_telegraphing = false
			# El jugador pudo haberse alejado durante el windup — recién acá
			# se chequea el rango de verdad, el telegraph no garantiza el hit.
			if dist_to_player <= contact_range and _player.has_method("take_damage"):
				_player.take_damage(contact_damage)
			_attack_timer = attack_interval
	elif _state == State.ATTACK and dist_to_player <= contact_range and _attack_timer <= 0.0 and contact_damage > 0:
		_telegraphing = true
		_telegraph_time_left = attack_telegraph_time
		Fx.telegraph_attack(_anim, attack_telegraph_time)

## Transiciones de la máquina de estados. Separado de _physics_process para
## que el chequeo de estado no se mezcle con el movimiento/telegraph.
func _update_state(delta: float, dist_to_player: float) -> void:
	match _state:
		State.PATROL:
			# GDD 2.3, cobertura activa: si el jugador está escondido detrás de
			# un obstáculo real (Player.is_hidden_from), no se detecta aunque
			# esté dentro del radio. has_method por las dudas si algún día
			# _player no es un Player.gd de verdad.
			var hidden: bool = _player.has_method("is_hidden_from") and _player.is_hidden_from(global_position)
			if dist_to_player <= detection_range and not hidden:
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
			if dist_to_player <= contact_range:
				_state = State.ATTACK
			elif dist_to_player > lose_track_range:
				_state = State.ALERT
				_alert_time_left = alert_time
		State.ATTACK:
			if dist_to_player > contact_range:
				_state = State.CHASE

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
	# Recibir daño alerta de inmediato aunque todavía esté en PATROL/ALERT
	# fuera del radio de detección (p.ej. golpeado por sorpresa desde atrás).
	if _state == State.PATROL or _state == State.ALERT:
		_state = State.CHASE

## GDD 2.3: neutraliza sin matar (ver comentario de la señal knocked_out).
## Simplificación de prototipo: visualmente es el mismo Fx.play_death y el
## nodo desaparece igual que al morir — la diferencia es 100% semántica
## (qué señal se emite), no hay cuerpo persistente "noqueado" todavía.
func knockout() -> void:
	if health <= 0:
		return
	health = 0
	health_changed.emit(health, max_health)
	knocked_out.emit()
	Fx.play_death(self, _anim)
