extends CharacterBody2D

@export var speed: float = 220.0
@export var max_health: int = 5
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")

## Dash / esquiva (GDD 2.3: movilidad con costo, no i-frames infinitos).
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.7
@export var dash_invulnerable: bool = true
## Radio (px) usado por las mejoras de dash que interactúan con enemigos
## cercanos al final del dash (empuje de mov_t2_armored, daño de mov_t3_juggernaut).
@export var dash_impact_radius: float = 40.0
## Desplazamiento instantáneo (px) aplicado a los enemigos empujados por
## mov_t2_armored al terminar el dash.
@export var dash_push_impulse: float = 50.0
@export var dash_damage: int = 1

## --- Sistema de armas: roster de WeaponData.gd (5 armas x 2 niveles) ---
## weapon_id == "" hasta que Main muestra la pantalla de elección inicial y el
## jugador elige (ver riesgo #1 en STATUS.md/plan: _shoot()/_get_effective_
## fire_rate() y _physics_process tienen guardas explícitas para este estado).
var weapon_id: String = ""
var weapon_level: int = 1
## id de arma -> nivel máximo alcanzado (para no volver a ofrecer un arma ya
## tenida al mismo nivel, y para saber si "ya tuvo" ranged en milestone_choices).
var owned_weapons: Dictionary = {}
## Stats VIVOS del arma equipada (los mutan las mejoras de la rama `off`).
## Claves: damage/rate/range/knockback (melee) o damage/rate/mag/reload/
## count/spread (ranged). Se recarga entera en cada equip_weapon().
var wstats: Dictionary = {}
## Mejoras de la rama `off` tomadas para el arma ACTUAL. Se vacía en cada
## equip_weapon(): cambiar de arma (o subir de nivel) reinicia lo invertido
## en ella — es la palanca que hace la elección del hito genuinamente tensa.
var weapon_upgrades: Array[String] = []

## `fire_rate`/`bullet_spread_deg` ya no son la fuente de verdad ofensiva
## (eso vive en wstats), pero quedan como @export de fallback para cuando
## weapon_id == "" (pantalla inicial, antes de elegir arma) para no requerir
## tocar Player.tscn ni dejar valores default sin uso declarado.
@export var fire_rate: float = 0.2
@export var bullet_spread_deg: float = 8.0

var current_ammo: int = 0
var current_mag_size: int = 0
var is_reloading: bool = false
var reload_time_left: float = 0.0
var _gun_base_pos: Vector2 = Vector2.ZERO

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
@onready var _camera: Camera2D = $Camera2D

## --- Screen shake (jugo sin audio, ver STATUS.md) ---
## `_shake_strength` decae linealmente a 0 en `_physics_process`; cada frame
## se aplica un offset aleatorio a la cámara proporcional a la fuerza actual,
## así que golpes seguidos se acumulan (clamp) en vez de cortarse entre sí.
var _shake_strength: float = 0.0
const SHAKE_DECAY: float = 18.0
const SHAKE_MAX: float = 12.0

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
	# Guarda #3 contra weapon_id == "" (ver comentario en la declaración de
	# weapon_id): sin arma elegida el bloque de disparo ni siquiera corre, así
	# que fire_cooldown nunca se recarga con un valor degenerado.
	var shoot_allowed: bool = weapon_id != "" and (not is_dashing or can_shoot_while_dashing)
	if shoot_allowed and Input.is_action_pressed("shoot") and fire_cooldown <= 0.0:
		_shoot()
		fire_cooldown = _get_effective_fire_rate()

	_update_shake(delta)

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
	# Guarda #2 contra weapon_id == "": jamás devolver 0 acá. Si devolviera 0,
	# fire_cooldown se recargaría en 0 cada frame y _shoot() (que ya corta
	# temprano, guarda #1) terminaría siendo un no-op llamado a tasa de frame.
	if weapon_id == "":
		return 1.0
	var base_rate: float = wstats.get("rate", fire_rate)
	if _is_adrenaline_active():
		return base_rate * 0.8
	return base_rate

## Único camino para equipar un arma: tanto para conseguir una nueva como
## para subir de nivel la actual (mismo id, level+1). Recarga wstats desde
## WeaponData y VACÍA weapon_upgrades — ahí vive el "cambiar de arma reinicia
## lo invertido en ella" que el hito necesita para ser una decisión real.
func equip_weapon(id: String, level: int) -> void:
	weapon_id = id
	weapon_level = level
	owned_weapons[id] = max(owned_weapons.get(id, 0), level)
	wstats = WeaponData.base_stats(id, level)
	weapon_upgrades.clear()

	is_reloading = false
	reload_time_left = 0.0
	if WeaponData.is_ranged(id):
		current_mag_size = int(wstats.get("mag", 0))
		current_ammo = current_mag_size
	else:
		current_mag_size = 0
		current_ammo = 0

	_apply_weapon_visual()

## Progreso combinado para requires/excludes de la rama `off`: las mejoras de
## arma (weapon_upgrades, se vacían al cambiar de arma) más las de mov/sur
## (taken_upgrades, persisten toda la corrida). Con esto el árbol `off` se
## "reinicia" solo al cambiar de arma, sin lógica extra en UpgradeTree.
func all_taken_upgrades() -> Array:
	var combined: Array = []
	combined.append_array(taken_upgrades)
	combined.append_array(weapon_upgrades)
	return combined

func has_ranged_weapon() -> bool:
	return weapon_id != "" and WeaponData.is_ranged(weapon_id)

## Actualiza el sprite de WeaponPivot/Gun según el arma equipada. Sin arma
## (weapon_id == "", pantalla inicial) el sprite queda oculto.
##
## Primera pasada CONSERVADORA para el melee (riesgo #3 del plan): cuchillo y
## hacha están dibujados verticales en el pack y WeaponPivot rota apuntando
## al mouse (+ flip_v en _physics_process), así que aplicarles el mismo
## region_rect/scale recortado que a las armas a distancia se vería raro sin
## además re-trabajar esa rotación. Por ahora el melee se muestra con la
## textura completa, sin recorte, tal como ya funcionaba antes de este
## cambio — afinar esto con el juego corriendo es trabajo pendiente.
func _apply_weapon_visual() -> void:
	if weapon_id == "":
		_gun_sprite.visible = false
		return
	_gun_sprite.visible = true
	_gun_sprite.texture = WeaponData.icon_texture(weapon_id, weapon_level)
	if WeaponData.is_ranged(weapon_id):
		_gun_sprite.region_enabled = true
		_gun_sprite.region_rect = WeaponData.icon_region(weapon_id, weapon_level)
		_gun_sprite.scale = WeaponData.icon_scale(weapon_id, weapon_level)
	else:
		_gun_sprite.region_enabled = false
		_gun_sprite.scale = Vector2(1.0, 1.0)

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

## Aumenta la fuerza de shake actual (clamp a SHAKE_MAX en vez de sumar sin
## límite, para que golpes/disparos seguidos no disparen un temblor gigante).
func _start_shake(amount: float) -> void:
	_shake_strength = min(_shake_strength + amount, SHAKE_MAX)

func _update_shake(delta: float) -> void:
	if _shake_strength <= 0.0:
		if _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO
		return
	_shake_strength = max(_shake_strength - SHAKE_DECAY * delta, 0.0)
	_camera.offset = Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	) * _shake_strength

func _shoot() -> void:
	# Guarda #1 contra weapon_id == "": sin arma elegida no hay nada que
	# disparar/golpear (pantalla inicial, entre _ready() y la elección).
	if weapon_id == "":
		return
	if WeaponData.is_ranged(weapon_id):
		_shoot_ranged()
	else:
		_melee_attack()

## Golpe cuerpo a cuerpo: daño instantáneo a todo enemigo dentro del alcance
## vigente (sin chequeo de ángulo, simplificación deliberada). Sin munición,
## cooldown propio vía wstats.rate/_get_effective_fire_rate.
##
## Jugador y enemigos no colisionan físicamente entre sí (ambos solo
## chocan con props), así que pueden superponerse del todo — sin empuje,
## el rango de golpe quedaría prácticamente a la misma distancia que el
## rango de contacto del enemigo, sin margen real para golpear sin recibir
## daño. El empuje al conectar el golpe le da al jugador un respiro tras
## cada hit (mismo patrón de empuje que _apply_dash_area_effect).
func _melee_attack() -> void:
	var melee_damage: int = wstats.get("damage", 1)
	var melee_range: float = wstats.get("range", 40.0)
	var melee_knockback: float = wstats.get("knockback", 40.0)
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
	_start_shake(1.5)
	# GDD 2.2: melee es silencioso comparado con las armas de fuego (sin
	# sistema de testigos todavía, así que por ahora es un ruido chico
	# plano en vez de "silencioso salvo testigo").
	FactionManager.report_noise(FactionManager.NOISE_MELEE)

## Feedback visual simple: el sprite del arma se adelanta y vuelve.
func _play_melee_lunge() -> void:
	var tween := create_tween()
	tween.tween_property(_gun_sprite, "position", _gun_base_pos + Vector2(10, 0), 0.05)
	tween.tween_property(_gun_sprite, "position", _gun_base_pos, 0.1)

## Disparo a distancia (pistola/SMG/escopeta): todos los stats (daño,
## cantidad de proyectiles, dispersión) vienen de wstats, ya sea el valor
## base del arma o el vivo tras mejoras de la rama off (kind: "ranged").
func _shoot_ranged() -> void:
	if is_reloading:
		return
	if current_ammo <= 0:
		_start_reload()
		return

	var base_dir := (get_global_mouse_position() - global_position).normalized()
	var shot_count: int = wstats.get("count", 1)
	var shot_damage: int = wstats.get("damage", 1)
	var spread_deg: float = wstats.get("spread", bullet_spread_deg)

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
	_start_shake(1.5)
	# GDD 2.2: disparos = radio grande, casi siempre sube a Nivel 1 (Sospecha).
	FactionManager.report_noise(FactionManager.NOISE_GUNSHOT)

func _start_reload() -> void:
	if is_reloading:
		return
	is_reloading = true
	reload_time_left = wstats.get("reload", 1.0)

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
	Fx.flash_damage(_anim)
	_start_shake(6.0)
	if health <= 0 and has_second_wind_available:
		has_second_wind_available = false
		health = 1
		health_changed.emit(health, max_health)
		return
	health_changed.emit(health, max_health)
	if health <= 0:
		died.emit()
		Fx.play_death(self, _anim)
