extends CharacterBody2D

## Máquina de estados básica (GDD sección 5.1 / hoja de ruta Fase 2):
## Patrulla -> Alerta -> Persecución -> Ataque. Sin estado de Huida
## todavía — no lo pide ningún enemigo actual, se agrega cuando haga
## falta.
##
## Detección = cono de visión real (ángulo + rango + cobertura), no un
## círculo por distancia — GDD 5.1 lo marcaba como mejora post-MVP, pero
## sin esto no hay forma de PROBAR sigilo de verdad (todo lo que esté
## dentro del radio se detectaba, mirase donde mirase el enemigo). Se
## dibuja como debug visual (_draw(), ver al final del archivo) para
## poder ver el cono jugando: verde en PATROL, amarillo en ALERT, rojo en
## CHASE/ATTACK.
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
## Alcance máximo del cono de visión (PATROL -> ALERT). El ángulo lo pone
## `view_angle` y la cobertura la resuelve Player.is_hidden_from() — ver
## _can_see_player().
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
## Ancho total del cono de visión, en grados, centrado en hacia dónde
## mira/camina el enemigo.
@export var view_angle: float = 100.0

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
## Última dirección "hacia donde mira" conocida (se actualiza cada frame en
## _physics_process, igual que el flip_h del sprite) — el cono de visión
## se dibuja centrado en esto, no en la velocidad cruda (que es cero en
## varios estados parado).
var _facing: Vector2 = Vector2.DOWN

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

	_update_state(delta, dist_to_player, to_player)

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
	if facing.length() > 1.0:
		_facing = facing.normalized()
	if abs(facing.x) > 1.0:
		_anim.flip_h = facing.x < 0.0
	queue_redraw()

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
			if dist_to_player <= contact_range:
				_state = State.ATTACK
			elif dist_to_player > lose_track_range:
				_state = State.ALERT
				_alert_time_left = alert_time
		State.ATTACK:
			if dist_to_player > contact_range:
				_state = State.CHASE

## Cono de visión real: dentro de rango, dentro del ángulo de view_angle
## centrado en _facing, y sin cobertura bloqueando (GDD 2.3). Reemplaza el
## viejo chequeo puramente circular — un enemigo mirando para otro lado ya
## no detecta al jugador parado justo detrás suyo.
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

## Debug visual del cono de visión — verde en PATROL (todavía no vio nada),
## amarillo en ALERT (te vio, viene el "signo de exclamación"), rojo en
## CHASE/ATTACK (ya sabe dónde estás). Dibujado en espacio local del nodo
## (CharacterBody2D no rota, solo su sprite se flipea), así que el cono se
## arma con trigonometría simple sobre _facing en vez de depender de la
## rotación del nodo.
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
