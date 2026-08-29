extends CharacterBody2D

@export var speed: float = 220.0
@export var fire_rate: float = 0.2
@export var max_health: int = 5
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")

## Dash / esquiva (GDD 2.3: movilidad con costo, no i-frames infinitos).
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.7
@export var dash_invulnerable: bool = true
@export var bullet_spread_deg: float = 8.0
## Radio (px) usado por las mejoras de dash que interactúan con enemigos
## cercanos al final del dash (empuje de mov_t2_armored, daño de mov_t3_juggernaut).
@export var dash_impact_radius: float = 40.0
## Desplazamiento instantáneo (px) aplicado a los enemigos empujados por
## mov_t2_armored al terminar el dash.
@export var dash_push_impulse: float = 50.0
@export var dash_damage: int = 1

var bullet_damage: int = 1
var bullet_count: int = 1

var health: int
var fire_cooldown: float = 0.0

var is_dashing: bool = false
var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT
var _last_move_dir: Vector2 = Vector2.RIGHT
var is_invulnerable: bool = false

## Progreso del árbol de mejoras de ESTA corrida (id -> tomado). Se resetea
## solo porque Main.reload_current_scene() recrea todo el árbol de nodos.
var taken_upgrades: Array[String] = []

## --- mov_t2_chain: "Dash Encadenado" ---
var has_chain_dash: bool = false
var dash_charges_max: int = 1
var dash_charges: int = 1
var _chain_double_cooldown_pending: bool = false

## --- mov_t2_armored / mov_t3_juggernaut: efectos al terminar el dash ---
var has_dash_push: bool = false
var has_dash_damage: bool = false

## --- mov_t3_phantom: disparar durante el dash ---
var can_shoot_while_dashing: bool = false

## --- sur_t1_regen: cura al superar oleada (leído/aplicado desde Main.gd) ---
var has_wave_regen: bool = false

## --- sur_t2_lifesteal ---
var has_lifesteal: bool = false
var bullet_hits_landed: int = 0

## --- sur_t3_secondwind ---
var has_second_wind_available: bool = false

## --- sur_t3_adrenaline (efecto dinámico, ver _physics_process) ---
var has_adrenaline: bool = false

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

	if input_vec.length() > 0.1:
		_last_move_dir = input_vec.normalized()

	# Con mov_t2_chain (dash_charges_max == 2) hay hasta 2 cargas de dash
	# disponibles sin esperar cooldown; el cooldown solo corre mientras
	# falten cargas por recuperar.
	if dash_charges < dash_charges_max:
		dash_cooldown_left -= delta
		if dash_cooldown_left <= 0.0:
			dash_charges = dash_charges_max

	if is_dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			_end_dash()
	elif Input.is_action_just_pressed("dash") and dash_charges > 0:
		_start_dash()

	if is_dashing:
		velocity = dash_direction * dash_speed
	else:
		velocity = _get_effective_speed() * input_vec
	move_and_slide()

	# El disparo se deshabilita durante el dash: es una esquiva rápida,
	# no tendría sentido apuntar con precisión mientras se ejecuta
	# (salvo con mov_t3_phantom, que habilita disparar en dash).
	if input_vec.length() > 0.1 and not is_dashing:
		if not _anim.is_playing():
			_anim.play("walk")
	elif not is_dashing:
		_anim.stop()
		_anim.frame = 0

	var aim_dir := get_global_mouse_position() - global_position
	if abs(aim_dir.x) > 1.0:
		_anim.flip_h = aim_dir.x < 0.0

	_weapon_pivot.rotation = aim_dir.angle()
	_gun_sprite.flip_v = aim_dir.x < 0.0

	fire_cooldown -= delta
	var shoot_allowed := not is_dashing or can_shoot_while_dashing
	if shoot_allowed and Input.is_action_pressed("shoot") and fire_cooldown <= 0.0:
		_shoot()
		fire_cooldown = _get_effective_fire_rate()

## sur_t3_adrenaline: mientras la vida esté por debajo del 30% del máximo,
## +25% de velocidad y cadencia x0.8. Se calcula por-frame (no se aplica una
## sola vez) para que se active/desactive según la vida actual.
func _is_adrenaline_active() -> bool:
	return has_adrenaline and max_health > 0 and float(health) / float(max_health) < 0.3

func _get_effective_speed() -> float:
	if _is_adrenaline_active():
		return speed * 1.25
	return speed

func _get_effective_fire_rate() -> float:
	if _is_adrenaline_active():
		return fire_rate * 0.8
	return fire_rate

func _start_dash() -> void:
	var dir := _last_move_dir
	if dir.length() < 0.1:
		dir = (get_global_mouse_position() - global_position)
		if dir.length() < 0.1:
			dir = Vector2.RIGHT
	dash_direction = dir.normalized()

	# mov_t2_chain: si esta carga es la última disponible (se llega a 0 con
	# más de 1 carga máxima), es un dash "encadenado" inmediato y el próximo
	# cooldown se duplica una vez.
	if has_chain_dash and dash_charges_max > 1 and dash_charges == 1:
		_chain_double_cooldown_pending = true
	dash_charges -= 1
	if dash_charges <= 0:
		dash_cooldown_left = dash_cooldown * (2.0 if _chain_double_cooldown_pending else 1.0)
		_chain_double_cooldown_pending = false

	is_dashing = true
	dash_time_left = dash_duration
	if dash_invulnerable:
		is_invulnerable = true
	_anim.modulate.a = 0.5

func _end_dash() -> void:
	is_dashing = false
	is_invulnerable = false
	_anim.modulate.a = 1.0

	if has_dash_push or has_dash_damage:
		_apply_dash_area_effect()

## mov_t2_armored: empuja enemigos cercanos al terminar el dash.
## mov_t3_juggernaut: daña (en vez de empujar) a los enemigos cercanos al
## terminar el dash, reusando la misma detección por radio/grupo.
func _apply_dash_area_effect() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > dash_impact_radius:
			continue
		if has_dash_damage and enemy.has_method("take_damage"):
			enemy.take_damage(dash_damage)
		elif has_dash_push and enemy is Node2D:
			# Enemy.gd recalcula `velocity` desde cero todos los frames antes
			# de move_and_slide(), así que un impulso en `velocity` se
			# perdería en el siguiente tick del enemigo. En vez de eso se
			# aplica un empujón directo de posición (simple pero efectivo).
			var push_dir := to_enemy.normalized()
			if push_dir.length() < 0.1:
				push_dir = Vector2.RIGHT
			enemy.global_position += push_dir * dash_push_impulse

func _shoot() -> void:
	var base_dir := (get_global_mouse_position() - global_position).normalized()

	for i in range(bullet_count):
		var offset := 0.0
		if bullet_count > 1:
			offset = deg_to_rad(bullet_spread_deg) * (i - float(bullet_count - 1) / 2.0)
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

## sur_t2_lifesteal: llamado por Bullet.gd cuando una bala del jugador
## impacta. Cada 10 impactos acumulados cura 1 de vida.
func _on_bullet_hit() -> void:
	if not has_lifesteal:
		return
	bullet_hits_landed += 1
	if bullet_hits_landed >= 10:
		bullet_hits_landed = 0
		if health < max_health:
			health += 1
			health_changed.emit(health, max_health)

func take_damage(amount: int) -> void:
	if is_invulnerable:
		return
	health -= amount
	if health <= 0 and has_second_wind_available:
		has_second_wind_available = false
		health = 1
		health_changed.emit(health, max_health)
		return
	health_changed.emit(health, max_health)
	if health <= 0:
		died.emit()
		queue_free()
