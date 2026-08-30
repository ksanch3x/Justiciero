extends Node2D

@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@export var spitter_scene: PackedScene = preload("res://scenes/Spitter.tscn")
@export var runner_scene: PackedScene = preload("res://scenes/Runner.tscn")

## Sprite del jefe: fila sin usar hasta ahora del pack (fila 3, "morada"),
## ver STATUS.md sección "Mapa de assets". Son tiles 24x24 completos, igual
## que los del Grunt/Runner — no hace falta region_rect, se usan enteros.
const BOSS_TEX_1: Texture2D = preload("res://assets/desert-shooter-pack/Enemies/Tiles/tile_0012.png")
const BOSS_TEX_2: Texture2D = preload("res://assets/desert-shooter-pack/Enemies/Tiles/tile_0013.png")
const BOSS_TEX_3: Texture2D = preload("res://assets/desert-shooter-pack/Enemies/Tiles/tile_0014.png")
@export var base_enemies_per_wave: int = 4
@export var enemies_increment_per_wave: int = 2
@export var enemy_health_scale_per_wave: float = 0.15
## Escalado leve adicional del Grunt por oleada: velocidad (+3%/oleada,
## compuesto) y daño de contacto (+1 cada 4 oleadas). Deliberadamente más
## suave que el escalado de vida para no volver la curva injugable.
@export var enemy_speed_scale_per_wave: float = 0.03
@export var enemy_contact_damage_per_waves: int = 4
@export var time_between_spawns: float = 0.4

## Oleada desde la que cada tipo puede empezar a aparecer. Antes de eso
## solo spawnea el Grunt (comportamiento original).
const RUNNER_MIN_WAVE: int = 2
const SPITTER_MIN_WAVE: int = 3

## Cada MILESTONE_EVERY oleadas, en vez de mejoras normales se ofrece el
## hito: conseguir un arma nueva o subir de nivel la equipada.
const MILESTONE_EVERY: int = 5

var wave_number: int = 0
var enemies_to_spawn: int = 0
var enemies_alive: int = 0
var _spawn_timer: float = 0.0
var _choosing_upgrade: bool = false

## --- Sistema de salas/puertas/jefe (envuelve al de oleadas, no lo
## reemplaza: wave_number arriba sigue siendo global a toda la corrida). ---
var current_room_id: String = "room_1"
## Oleadas completadas DENTRO de la sala activa (se resetea a 0 en cada
## transición de sala). Cuando llega a RoomData.get_room(id).waves, se abre
## la puerta en vez de mostrar el panel de mejoras.
var waves_in_room: int = 0
## true mientras hay una puerta abierta esperando que el jugador la cruce.
## _process corta temprano igual que con _choosing_upgrade, para no volver
## a evaluar "oleada limpia" en cada frame mientras no hay nada que spawnear.
var _door_open: bool = false
var _boss_mode: bool = false
var _boss: CharacterBody2D = null

const PROP_NAMES: Array[String] = ["Cactus1", "Cactus2", "Bones1", "Bones2", "RockFormation"]
const DEFAULT_TINT: Color = Color(0.16, 0.16, 0.22, 1)
const WALL_THICKNESS: float = 40.0
const WALL_HEIGHT: float = 720.0
const WALL_COLOR: Color = Color(0.278431, 0.196078, 0.294118, 1)
## Mitad de la altura del vano de la puerta (vano total = 140px, cómodo
## para cruzar sin rozar los segmentos de pared restantes).
const DOOR_GAP_HALF_HEIGHT: float = 70.0
const SIDE_TO_WALL: Dictionary = {"east": "East", "west": "West"}

@onready var _player: CharacterBody2D = $Player
@onready var _hud: Label = $HUD/Label
@onready var _spawn_points: Node2D = $SpawnPoints
@onready var _upgrade_ui: CanvasLayer = $UpgradeUI
@onready var _walls: Node2D = $Walls
@onready var _props: Node2D = $Props
@onready var _canvas_modulate: CanvasModulate = $CanvasModulate

func _ready() -> void:
	_player.health_changed.connect(_on_player_health_changed)
	_player.died.connect(_on_player_died)
	_upgrade_ui.chosen.connect(_on_upgrade_chosen)
	_upgrade_ui.door_chosen.connect(_on_door_chosen)

	_apply_room(RoomData.get_room(current_room_id))

	# Pantalla inicial: elegir arma cuerpo a cuerpo antes de la oleada 1.
	# wave_number sigue en 0 mientras tanto (ver _update_hud, que muestra un
	# texto fijo en ese estado en vez de "Oleada: 0").
	_choosing_upgrade = true
	_hud.text = "Elegí tu arma inicial"
	_upgrade_ui.show_choices(_player, "weapon_pick")

func _process(delta: float) -> void:
	if _choosing_upgrade or _door_open or _boss_mode:
		return

	if enemies_to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_enemy()
			enemies_to_spawn -= 1
			_spawn_timer = time_between_spawns
	elif enemies_alive <= 0:
		waves_in_room += 1
		var room: Dictionary = RoomData.get_room(current_room_id)
		if waves_in_room >= int(room["waves"]):
			_open_room_doors(room)
		else:
			_show_upgrade_selection()

	_update_hud()

func _start_next_wave() -> void:
	wave_number += 1
	enemies_to_spawn = base_enemies_per_wave + (wave_number - 1) * enemies_increment_per_wave
	enemies_alive = 0
	_spawn_timer = 0.0

## Elige qué escena spawnear esta vez. Pesos simples por oleada: el Grunt
## domina al principio y la proporción de Runner/Spitter crece con las
## oleadas, cada uno solo una vez habilitado (ver *_MIN_WAVE).
## Oleada 1:      Grunt 100
## Oleada 2-2:    Grunt 70 / Runner 30
## Oleada 3-4:    Grunt 55 / Runner 25 / Spitter 20
## Oleada 5+:     Grunt 40 / Runner 30 / Spitter 30
func _pick_enemy_scene() -> PackedScene:
	# La sala activa puede acotar aún más qué tipos aparecen (RoomData
	# .enemy_types), por encima del gate normal por wave_number: room_1 solo
	# tiene Grunt aunque wave_number ya habilite Runner/Spitter, por ejemplo.
	var room: Dictionary = RoomData.get_room(current_room_id)
	var allowed_types: Array = room.get("enemy_types", ["grunt", "runner", "spitter"])
	var runner_allowed: bool = allowed_types.has("runner")
	var spitter_allowed: bool = allowed_types.has("spitter")

	var runner_enabled: bool = wave_number >= RUNNER_MIN_WAVE and runner_allowed
	var spitter_enabled: bool = wave_number >= SPITTER_MIN_WAVE and spitter_allowed

	if not runner_enabled and not spitter_enabled:
		return enemy_scene

	var grunt_weight := 70
	var runner_weight: int = 30 if runner_enabled else 0
	var spitter_weight := 0
	if spitter_enabled:
		if wave_number >= 5:
			grunt_weight = 40
			runner_weight = 30
			spitter_weight = 30
		else:
			grunt_weight = 55
			runner_weight = 25
			spitter_weight = 20

	var total := grunt_weight + runner_weight + spitter_weight
	var roll := randi() % total
	if roll < grunt_weight:
		return enemy_scene
	roll -= grunt_weight
	if roll < runner_weight:
		return runner_scene
	return spitter_scene

func _spawn_enemy() -> void:
	var points := _spawn_points.get_children()
	if points.is_empty():
		return
	var point: Node2D = points[randi() % points.size()]

	var scene := _pick_enemy_scene()
	var enemy := scene.instantiate()

	var health_scale := 1.0 + float(wave_number - 1) * enemy_health_scale_per_wave
	enemy.max_health = int(ceil(enemy.max_health * health_scale))

	# El escalado de speed/contact_damage solo aplica al Grunt (Enemy.gd);
	# Runner y Spitter ya tienen su propia curva de dificultad por diseño
	# (más rápido/más débil, o a distancia) y no se re-escalan acá.
	if scene == enemy_scene:
		var speed_scale := pow(1.0 + enemy_speed_scale_per_wave, wave_number - 1)
		enemy.speed = enemy.speed * speed_scale
		enemy.contact_damage = enemy.contact_damage + int(floor(float(wave_number - 1) / float(enemy_contact_damage_per_waves)))

	enemy.died.connect(_on_enemy_died)

	add_child(enemy)
	enemy.global_position = point.global_position
	enemies_alive += 1

func _on_enemy_died() -> void:
	enemies_alive -= 1

func _show_upgrade_selection() -> void:
	if _player.has_wave_regen and _player.health < _player.max_health:
		_player.health = min(_player.max_health, _player.health + 1)
		_player.health_changed.emit(_player.health, _player.max_health)
	_choosing_upgrade = true
	var mode: String = "milestone" if wave_number % MILESTONE_EVERY == 0 else "upgrade"
	_upgrade_ui.show_choices(_player, mode)

func _on_upgrade_chosen() -> void:
	_choosing_upgrade = false
	_start_next_wave()

# ---------------------------------------------------------------------------
# Salas, puertas y jefe
# ---------------------------------------------------------------------------

## Sala normal completó sus oleadas: en vez del panel de mejoras/hito, se
## abre la puerta (o se ofrecen las 2 si la sala tiene bifurcación). Nunca
## compite con _show_upgrade_selection() — una u otra, nunca ambas.
func _open_room_doors(room: Dictionary) -> void:
	var doors: Dictionary = room["doors"]
	if doors.size() > 1:
		_choosing_upgrade = true
		_upgrade_ui.show_choices(_player, "door_pick", doors)
	else:
		var side: String = doors.keys()[0]
		_open_door(side, String(doors[side]))

func _on_door_chosen(side: String) -> void:
	_choosing_upgrade = false
	var room: Dictionary = RoomData.get_room(current_room_id)
	var doors: Dictionary = room["doors"]
	_open_door(side, String(doors[side]))

## Abre una puerta real en la pared East/West de esta sala: reemplaza el
## CollisionShape2D/ColorRect de esa pared por dos segmentos angostos con un
## vano central, y pone un Area2D sensor en el vano que dispara la
## transición cuando el jugador lo cruza (nada de click). La pared opuesta
## (no elegida) queda sólida para siempre.
func _open_door(side: String, dest_room_id: String) -> void:
	_door_open = true
	var wall_name: String = String(SIDE_TO_WALL[side])
	var wall_node: StaticBody2D = _walls.get_node(wall_name)
	_open_door_in_wall(wall_node, DOOR_GAP_HALF_HEIGHT)

	var trigger := Area2D.new()
	trigger.name = "DoorTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 1  # capa del jugador
	wall_node.add_child(trigger)
	trigger.position = Vector2.ZERO

	var trigger_shape := RectangleShape2D.new()
	trigger_shape.size = Vector2(WALL_THICKNESS + 20.0, DOOR_GAP_HALF_HEIGHT * 2.0)
	var trigger_cs := CollisionShape2D.new()
	trigger_cs.shape = trigger_shape
	trigger.add_child(trigger_cs)

	trigger.body_entered.connect(_on_door_crossed.bind(dest_room_id))

func _on_door_crossed(body: Node2D, dest_room_id: String) -> void:
	if body != _player:
		return
	_transition_to_room(dest_room_id)

## Función aislada a propósito (ver plan): reemplaza el CollisionShape2D
## sólido de `wall_node` (una de East/West, siempre vertical, alto
## WALL_HEIGHT) por dos segmentos StaticBody2D nuevos ("DoorSegTop"/
## "DoorSegBottom") que dejan un vano de `gap_half_height * 2` centrado en
## y=0 local. La forma/ColorRect ORIGINALES no se tocan ni se duplican mal
## (East y West comparten el mismo sub_resource en Main.tscn) — simplemente
## se deshabilitan/ocultan, así _restore_walls() los puede reactivar sin
## reconstruir nada.
func _open_door_in_wall(wall_node: StaticBody2D, gap_half_height: float) -> void:
	var orig_shape: CollisionShape2D = wall_node.get_node("CollisionShape2D")
	orig_shape.disabled = true
	var orig_rect: ColorRect = wall_node.get_node("ColorRect")
	orig_rect.visible = false

	var half_total: float = WALL_HEIGHT / 2.0
	var seg_height: float = half_total - gap_half_height
	if seg_height <= 0.0:
		return

	for sign_mult in [-1.0, 1.0]:
		var seg_center_y: float = sign_mult * (gap_half_height + seg_height / 2.0)
		var seg_name: String = "DoorSegTop" if sign_mult < 0.0 else "DoorSegBottom"

		var body := StaticBody2D.new()
		body.name = seg_name
		body.collision_layer = 8
		wall_node.add_child(body)
		body.position = Vector2(0, seg_center_y)

		var rect := ColorRect.new()
		rect.color = WALL_COLOR
		rect.offset_left = -WALL_THICKNESS / 2.0
		rect.offset_right = WALL_THICKNESS / 2.0
		rect.offset_top = -seg_height / 2.0
		rect.offset_bottom = seg_height / 2.0
		body.add_child(rect)

		var shape := RectangleShape2D.new()
		shape.size = Vector2(WALL_THICKNESS, seg_height)
		var cs := CollisionShape2D.new()
		cs.shape = shape
		body.add_child(cs)

## Restaura las 4 paredes a sólidas: libera cualquier segmento/trigger de
## puerta agregado por _open_door_in_wall()/_open_door() y reactiva la forma
## y el ColorRect originales de cada pared.
func _restore_walls() -> void:
	for wall_node in _walls.get_children():
		for child in wall_node.get_children():
			if String(child.name).begins_with("Door"):
				child.queue_free()
		var shape: CollisionShape2D = wall_node.get_node("CollisionShape2D")
		shape.disabled = false
		var rect: ColorRect = wall_node.get_node("ColorRect")
		rect.visible = true

## Reposiciona/muestra los mismos 5 StaticBody2D de Props (no instancia
## nada nuevo) y actualiza el tinte del CanvasModulate según `room`.
func _apply_room(room: Dictionary) -> void:
	var props_cfg: Array = room["props"]
	for i in range(PROP_NAMES.size()):
		var prop_node: StaticBody2D = _props.get_node(PROP_NAMES[i])
		var cfg: Dictionary = props_cfg[i]
		prop_node.visible = bool(cfg["visible"])
		prop_node.position = cfg["pos"]
		var prop_shape: CollisionShape2D = prop_node.get_node("CollisionShape2D")
		prop_shape.disabled = not bool(cfg["visible"])

	var tint: Variant = room["tint"]
	_canvas_modulate.color = tint if tint != null else DEFAULT_TINT

## Restaura las paredes, cambia de sala activa y arranca lo que corresponda
## en la sala nueva (siguiente oleada, o el jefe si es room_boss).
func _transition_to_room(dest_room_id: String) -> void:
	_restore_walls()
	_door_open = false
	waves_in_room = 0
	current_room_id = dest_room_id

	var room: Dictionary = RoomData.get_room(dest_room_id)
	_apply_room(room)
	_player.global_position = Vector2(0, 0)

	if bool(room["is_boss"]):
		_spawn_boss()
	else:
		_start_next_wave()

## Variante de instancia de Enemy.tscn, sin tocar Enemy.gd/Enemy.tscn:
## overrides de stats ANTES de add_child() (los lee _ready()), y de
## posición/visual/colisión DESPUÉS (necesitan estar en el árbol / el nodo
## hijo ya resuelto). Sin fases, sin ataque a distancia, sin invocación —
## un Grunt grande con vida alta y golpe fuerte, nada más.
func _spawn_boss() -> void:
	_boss_mode = true
	enemies_to_spawn = 0
	enemies_alive = 0

	var boss: CharacterBody2D = enemy_scene.instantiate()
	boss.max_health = 220
	boss.speed = 95.0
	boss.contact_damage = 4
	boss.contact_range = 30.0
	boss.attack_interval = 1.1
	boss.attack_telegraph_time = 0.35
	boss.died.connect(_on_boss_died)

	add_child(boss)
	boss.global_position = Vector2(0, -150)

	var visual: AnimatedSprite2D = boss.get_node("Visual")
	visual.scale = Vector2(2.4, 2.4)
	visual.sprite_frames = _make_boss_sprite_frames()
	visual.play("walk")

	var cshape: CollisionShape2D = boss.get_node("CollisionShape2D")
	var circle := CircleShape2D.new()
	circle.radius = 26.0
	cshape.shape = circle

	_boss = boss
	_hud.text = "Sala del Jefe — ¡Derrotalo!   Vida: %d/%d" % [_player.health, _player.max_health]

## SpriteFrames construido en código (no sub_resource de .tscn) con el
## sprite sin usar hasta ahora del pack, ver comentario junto a BOSS_TEX_*.
func _make_boss_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("walk")
	frames.set_animation_loop("walk", true)
	frames.set_animation_speed("walk", 5.0)
	for tex in [BOSS_TEX_1, BOSS_TEX_2, BOSS_TEX_3]:
		frames.add_frame("walk", tex)
	return frames

func _on_boss_died() -> void:
	_boss_mode = false
	set_process(false)
	_hud.text = "¡Jefe derrotado! Presioná R para reiniciar."

func _on_player_health_changed(_current: int, _max_hp: int) -> void:
	_update_hud()

func _on_player_died() -> void:
	_hud.text = "Muerto en oleada %d. Presiona R para reiniciar." % wave_number
	set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()

func _update_hud() -> void:
	var hp: int = 0
	var max_hp: int = 0
	if is_instance_valid(_player):
		hp = _player.health
		max_hp = _player.max_health

	# En la sala del jefe no hay contador de oleadas/enemigos restantes que
	# mostrar — mismo texto fijo que ya usa _spawn_boss(), solo con la vida
	# del jugador al día (esto se llama también desde
	# _on_player_health_changed mientras _boss_mode es true).
	if _boss_mode:
		_hud.text = "Sala del Jefe — ¡Derrotalo!   Vida: %d/%d" % [hp, max_hp]
		return

	var alive_or_pending := enemies_alive + enemies_to_spawn

	var ammo_text := ""
	if is_instance_valid(_player) and _player.has_ranged_weapon():
		if _player.is_reloading:
			ammo_text = "   Munición: recargando..."
		else:
			ammo_text = "   Munición: %d/%d" % [_player.current_ammo, _player.current_mag_size]

	_hud.text = "Oleada: %d   Vida: %d/%d   Enemigos restantes: %d%s" % [wave_number, hp, max_hp, alive_or_pending, ammo_text]
