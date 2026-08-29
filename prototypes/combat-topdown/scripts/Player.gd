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

## --- Sistema de armas: melee inicial + SMG/Escopeta desbloqueables ---
enum Weapon { MELEE, SMG, SHOTGUN }
var current_weapon: int = Weapon.MELEE

@export var melee_damage: int = 2
@export var melee_range: float = 36.0
@export var melee_attack_rate: float = 0.35
## Empuje instantáneo (px) aplicado al enemigo golpeado, para que el jugador
## no quede pegado intercambiando daño con el enemigo (ver _melee_attack).
@export var melee_knockback: float = 46.0

## La SMG reusa `fire_rate`/`bullet_damage`/`bullet_count` (las mismas
## variables que hoy modifican off_t1_rate/off_t1_dmg/off_t2_burst/etc), así
## que cualquier mejora tomada mientras el jugador todavía usa el cuchillo
## queda guardada y ya viene aplicada en cuanto se consigue la SMG.
@export var smg_mag_size: int = 20
@export var smg_reload_time: float = 1.2

## La escopeta tiene su propia cadencia (no la toca off_t1_rate) y sus
## propios bonus de proyectiles/daño por disparo, sumados sobre
## bullet_count/bullet_damage vigentes en el momento de disparar.
@export var shotgun_fire_rate: float = 0.9
@export var shotgun_mag_size: int = 6
@export var shotgun_reload_time: float = 1.8
@export var shotgun_bullet_count_bonus: int = 5
@export var shotgun_damage_bonus: int = 1
@export var shotgun_spread_deg: float = 28.0

@export var melee_texture: Texture2D = preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0008.png")
@export var ranged_texture: Texture2D = preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0000.png")

var current_ammo: int = 0
var current_mag_size: int = 0
var is_reloading: bool = false
var reload_time_left: float = 0.0
var _gun_base_pos: Vector2 = Vector2.ZERO

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
	_gun_base_pos = _gun_sprite.position
	_apply_weapon_visual()

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

	if is_reloading:
		reload_time_left -= delta
		if reload_time_left <= 0.0:
			is_reloading = false
			current_ammo = current_mag_size

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
	var base_rate: float = fire_rate
	match current_weapon:
		Weapon.MELEE:
			base_rate = melee_attack_rate
		Weapon.SHOTGUN:
			base_rate = shotgun_fire_rate
		_:
			base_rate = fire_rate
	if _is_adrenaline_active():
		return base_rate * 0.8
	return base_rate

## off_t1_smg: cambia el arma equipada de melee a SMG.
func equip_smg() -> void:
	current_weapon = Weapon.SMG
	current_mag_size = smg_mag_size
	current_ammo = smg_mag_size
	is_reloading = false
	reload_time_left = 0.0
	_apply_weapon_visual()

## off_t2_shotgun: cambia el arma equipada a la escopeta.
func equip_shotgun() -> void:
	current_weapon = Weapon.SHOTGUN
	current_mag_size = shotgun_mag_size
	current_ammo = shotgun_mag_size
	is_reloading = false
	reload_time_left = 0.0
	_apply_weapon_visual()

func has_ranged_weapon() -> bool:
	return current_weapon != Weapon.MELEE

## Actualiza el sprite de WeaponPivot/Gun según el arma equipada: el cuchillo
## se muestra completo (sin recorte) y el arma a distancia reusa el recorte
## de pistola ya existente en la escena.
func _apply_weapon_visual() -> void:
	match current_weapon:
		Weapon.MELEE:
			_gun_sprite.texture = melee_texture
			_gun_sprite.region_enabled = false
			_gun_sprite.scale = Vector2(1.0, 1.0)
		_:
			_gun_sprite.texture = ranged_texture
			_gun_sprite.region_enabled = true
			_gun_sprite.region_rect = Rect2(8, 8, 9, 8)
			_gun_sprite.scale = Vector2(1.8, 1.8)

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
	match current_weapon:
		Weapon.MELEE:
			_melee_attack()
		_:
			_shoot_ranged()

## Golpe cuerpo a cuerpo: daño instantáneo a todo enemigo dentro de
## `melee_range` (sin chequeo de ángulo, simplificación deliberada). Sin
## munición, cooldown propio vía melee_attack_rate/_get_effective_fire_rate.
##
## Jugador y enemigos no colisionan físicamente entre sí (ambos solo
## chocan con props), así que pueden superponerse del todo — sin empuje,
## el rango de golpe del cuchillo (melee_range) queda prácticamente a la
## misma distancia que el rango de contacto del enemigo, sin margen real
## para golpear sin recibir daño. El empuje al conectar el golpe le da al
## jugador un respiro tras cada hit en vez de quedar pegado intercambiando
## daño (mismo patrón de empuje que _apply_dash_area_effect).
func _melee_attack() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var to_enemy: Vector2 = enemy.global_position - global_position
		var dist: float = to_enemy.length()
		if dist <= melee_range and enemy.has_method("take_damage"):
			enemy.take_damage(melee_damage)
			var push_dir := to_enemy.normalized()
			if push_dir.length() < 0.1:
				push_dir = Vector2.RIGHT
			enemy.global_position += push_dir * melee_knockback
	_play_melee_lunge()

## Feedback visual simple: el sprite del arma se adelanta y vuelve.
func _play_melee_lunge() -> void:
	var tween := create_tween()
	tween.tween_property(_gun_sprite, "position", _gun_base_pos + Vector2(10, 0), 0.05)
	tween.tween_property(_gun_sprite, "position", _gun_base_pos, 0.1)

## Disparo a distancia (SMG o Escopeta). Reusa la lógica de spread ya
## existente en bullet_count/bullet_spread_deg; la escopeta suma sus propios
## bonus de proyectiles/daño y usa su propio ángulo de dispersión.
func _shoot_ranged() -> void:
	if is_reloading:
		return
	if current_ammo <= 0:
		_start_reload()
		return

	var base_dir := (get_global_mouse_position() - global_position).normalized()
	var shot_count := bullet_count
	var shot_damage := bullet_damage
	var spread_deg := bullet_spread_deg
	if current_weapon == Weapon.SHOTGUN:
		shot_count += shotgun_bullet_count_bonus
		shot_damage += shotgun_damage_bonus
		spread_deg = shotgun_spread_deg

	for i in range(shot_count):
		var offset := 0.0
		if shot_count > 1:
			offset = deg_to_rad(spread_deg) * (i - float(shot_count - 1) / 2.0)
		var dir := base_dir.rotated(offset)

		var bullet := bullet_scene.instantiate()
		bullet.direction = dir
		bullet.shooter = self
		bullet.damage = shot_damage
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = global_position

	current_ammo -= 1
	if current_ammo <= 0:
		_start_reload()

func _start_reload() -> void:
	if is_reloading:
		return
	is_reloading = true
	reload_time_left = smg_reload_time if current_weapon == Weapon.SMG else shotgun_reload_time

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
