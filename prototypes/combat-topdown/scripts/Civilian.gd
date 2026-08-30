extends CharacterBody2D

## Testigo civil (GDD games/justiciero/GDD.md, secciones 2.2 y 2.5).
##
## No pelea ni hace daño: existe para que la violencia tenga TESTIGOS. Sus
## dos funciones de diseño:
##  1. Matarlo sube la Notoriedad persistente — el GDD 2.5 decidió que
##     cuenta "matar policías Y testigos civiles" (no criminales). Noquear
##     no la sube, igual que con la policía.
##  2. Ver violencia lo hace gritar: reporta ruido a FactionManager, así
##     que matar delante de un civil alerta a la policía aunque el golpe
##     en sí sea silencioso. Es lo que hace que el melee "silencioso" deje
##     de ser gratis en una sala poblada.
##
## Estados: WANDER (pasea tranquilo) / FLEE (corre lejos del peligro).
## No tiene cono de visión propio — para "ver" violencia le alcanza con
## estar dentro de `witness_range` del ruido, porque un grito no depende
## de estar mirando en la dirección correcta.
enum State { WANDER, FLEE }

@export var wander_speed: float = 55.0
@export var flee_speed: float = 145.0
@export var max_health: int = 2
@export var wander_radius: float = 120.0
## Si un ruido fuerte (ver FactionManager.NOISE_*) ocurre a menos de esto,
## el civil entra en pánico y huye.
@export var witness_range: float = 260.0
@export var flee_time: float = 4.0
## Ruido que genera un civil aterrado (gritos). Más que un golpe cuerpo a
## cuerpo pero menos que un disparo — lo suficiente para escalar la Alerta
## si hay varios civiles gritando a la vez.
@export var scream_noise: float = 22.0
## Magnitud mínima de ruido que hace entrar en pánico. A propósito por
## ENCIMA de `scream_noise`: si no, el grito de un civil haría gritar al de
## al lado y se realimentaría en cadena sin fin. Un disparo (30) y un
## asesinato (70) sí lo cruzan; un golpe melee (6) no — que es justo la
## distinción de sigilo que pide el GDD 2.2.
@export var panic_noise_threshold: float = 25.0

var health: int
var _player: Node2D
var _state: State = State.WANDER
var _spawn_position: Vector2
var _spawn_captured: bool = false
var _wander_target: Vector2
var _flee_timer: float = 0.0
var _flee_dir: Vector2 = Vector2.ZERO
## Evita que un mismo evento de ruido dispare un grito por frame mientras
## el civil sigue dentro del radio.
var _scream_cooldown: float = 0.0

signal died
signal knocked_out

@onready var _anim: AnimatedSprite2D = $Visual

func _ready() -> void:
	health = max_health
	# A propósito NO está en el grupo "enemy": el melee y el empujón de
	# área del dash del jugador iteran ese grupo, y no queremos que barrer
	# el arma mate civiles sin querer. Al civil hay que apuntarle: solo le
	# pegan las balas (por layer física) o un takedown explícito, que sí
	# lo busca por el grupo "civilian".
	add_to_group("civilian")
	_player = get_tree().get_first_node_in_group("player")
	_anim.play("walk")
	FactionManager.level_changed.connect(_on_alert_level_changed)
	FactionManager.noise_reported.connect(_on_noise_reported)

## Si la Alerta escala a Persecución o más, todos los civiles entran en
## pánico — a esa altura ya hay tiros o cuerpos, nadie se queda paseando.
func _on_alert_level_changed(new_level: int, _old_level: int) -> void:
	if new_level >= FactionManager.AlertLevel.CHASE:
		_panic(FactionManager.last_noise_position)

## Reacción al ruido puntual, independiente del nivel de Alerta agregado.
## Escuchar la señal (en vez de que Player/Main avisen a mano) hace que
## funcione con CUALQUIER forma de matar —bala, melee, dash— sin hooks
## repartidos por los scripts de ataque.
func _on_noise_reported(position: Vector2, amount: float) -> void:
	if amount < panic_noise_threshold:
		return
	_panic(position)

func _physics_process(delta: float) -> void:
	# global_position todavía es (0,0) durante _ready() — Main.gd la fija
	# recién DESPUÉS de add_child() (cuidado técnico #3 de STATUS.md).
	if not _spawn_captured:
		_spawn_captured = true
		_spawn_position = global_position
		_pick_wander_target()

	_scream_cooldown = max(0.0, _scream_cooldown - delta)

	match _state:
		State.WANDER:
			_process_wander()
		State.FLEE:
			_flee_timer -= delta
			velocity = _flee_dir * flee_speed
			if _flee_timer <= 0.0:
				_state = State.WANDER
				_pick_wander_target()
	move_and_slide()

	if abs(velocity.x) > 1.0:
		_anim.flip_h = velocity.x < 0.0

func _process_wander() -> void:
	var to_target: Vector2 = _wander_target - global_position
	if to_target.length() <= 6.0:
		_pick_wander_target()
		velocity = Vector2.ZERO
		return
	velocity = to_target.normalized() * wander_speed

func _pick_wander_target() -> void:
	var offset := Vector2(randf_range(-wander_radius, wander_radius), randf_range(-wander_radius, wander_radius))
	_wander_target = Arena.clamp_point(_spawn_position + offset)

## Entra en pánico: huye en línea recta lejos de `threat_position` y grita
## (reporta ruido), que es la razón de ser del civil como testigo.
func _panic(threat_position: Vector2) -> void:
	if global_position.distance_to(threat_position) > witness_range:
		return
	_state = State.FLEE
	_flee_timer = flee_time
	var away: Vector2 = global_position - threat_position
	if away.length() > 1.0:
		_flee_dir = away.normalized()
	else:
		_flee_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

	if _scream_cooldown <= 0.0:
		_scream_cooldown = 1.5
		FactionManager.report_noise(scream_noise, global_position)

func take_damage(amount: int, _from_ai: bool = false) -> void:
	health -= amount
	# Recibir un tiro es motivo de pánico aunque no haya ruido ambiente.
	_panic(_player.global_position if is_instance_valid(_player) else global_position)
	if health <= 0:
		health = 0
		died.emit()
		Fx.play_death(self, _anim)
		return
	Fx.flash_damage(_anim)

## GDD 2.3/2.5: noquear a un testigo NO sube Notoriedad — misma señal
## separada que en Enemy/Police/Criminal, para que lo que escucha `died`
## (SaveManager) no se dispare acá.
func knockout() -> void:
	if health <= 0:
		return
	health = 0
	knocked_out.emit()
	Fx.play_death(self, _anim)
