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

## --- UI kit del pack (assets/desert-shooter-pack/UI/, 198 tiles 16x16,
## nunca usado hasta el cierre del demo v2). Índices verificados armando un
## montage etiquetado con Python/PIL y leyéndolo tile por tile — NO son los
## rangos aproximados de la primera exploración (ver STATUS.md "Mapa de
## assets — UI kit" para el detalle completo). ---
const UI_TILE_DIR: String = "res://assets/desert-shooter-pack/UI/"

## Fuente bitmap: dígitos y A-Z, fondo morado con borde, ~14x16px por glifo.
## No hay minúsculas ni signos de puntuación en el pack — el título/botón de
## esta pantalla no los necesita.
const FONT_CHAR_INDEX: Dictionary = {
	"0": 93, "1": 94, "2": 95, "3": 96, "4": 97, "5": 98, "6": 99, "7": 100, "8": 101, "9": 102,
	"A": 108, "B": 109, "C": 110, "D": 111, "E": 112, "F": 113, "G": 114, "H": 115, "I": 116,
	"J": 117, "K": 118, "L": 119, "M": 120, "N": 126, "O": 127, "P": 128, "Q": 129, "R": 130,
	"S": 131, "T": 132, "U": 133, "V": 134, "W": 135, "X": 136, "Y": 137, "Z": 138,
}

## Panel de fondo del menú: único grupo de 9 tiles del pack con relleno
## sólido + centro distinto de los bordes (3x3 real, no un "3x2 de 2 tarjetas
## de botón" como los otros paneles del pack) — por eso es el candidato para
## un NinePatchRect de verdad. Orden: fila por fila, izq a der.
const PANEL_TILE_INDICES: Array[int] = [69, 70, 71, 87, 88, 89, 105, 106, 107]
const PANEL_TILE_PX: int = 16

## Barra de 3 piezas (cap izq / relleno repetible / cap der), set "corto"
## (gris para el fondo vacío, naranja para el relleno) — ver STATUS.md.
const BAR_BG_CAP_L: int = 65
const BAR_BG_MID: int = 66
const BAR_BG_CAP_R: int = 67
const BAR_FILL_CAP_L: int = 139
const BAR_FILL_MID: int = 140
const BAR_FILL_CAP_R: int = 142
const BAR_MID_SEGMENTS: int = 8
const BAR_CELL_SIZE: float = 20.0

var _boss_bar_bg: Control = null
var _boss_bar_fill_clip: Control = null
var _boss_bar_full_width: float = 0.0

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

	# Menú principal primero (bloquea _process igual que _choosing_upgrade):
	# recién al tocar "Jugar" arranca la pantalla de elegir arma inicial.
	_choosing_upgrade = true
	_hud.text = ""
	_show_main_menu()

## Pantalla inicial: elegir arma cuerpo a cuerpo antes de la oleada 1.
## wave_number sigue en 0 mientras tanto (ver _update_hud, que muestra un
## texto fijo en ese estado en vez de "Oleada: 0"). Se llama desde el botón
## "Jugar" del menú principal, no desde _ready() directamente.
func _start_weapon_pick() -> void:
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
	# El jefe no patrulla: detección/lose_track cubren toda la sala (900x640)
	# de sobra, así arranca persiguiendo de inmediato apenas se instancia
	# (ver Enemy.gd, máquina de estados PATROL/ALERT/CHASE/ATTACK) — un jefe
	# vagando antes de notar al jugador no tendría sentido acá.
	boss.detection_range = 2000.0
	boss.lose_track_range = 2000.0
	boss.died.connect(_on_boss_died)
	boss.health_changed.connect(_on_boss_health_changed)

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
	_make_boss_health_bar()
	_on_boss_health_changed(boss.health, boss.max_health)

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
	if is_instance_valid(_boss_bar_bg):
		_boss_bar_bg.queue_free()
	_boss_bar_bg = null
	_boss_bar_fill_clip = null

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

# ---------------------------------------------------------------------------
# UI kit del pack (barra de vida del jefe, menú principal) — ver STATUS.md
# "Mapa de assets — UI kit" para el detalle de qué es cada tile.
# ---------------------------------------------------------------------------

## `load()` en vez de `preload()`: son ~40 rutas distintas (fuente + barra +
## panel) armadas desde índices de un Dictionary/Array — preload exige una
## ruta constante literal, no sirve para esto. Godot cachea `load()` de todas
## formas, no hay costo real por reusar el mismo índice varias veces.
func _ui_tex(index: int) -> Texture2D:
	return load(UI_TILE_DIR + "tile_%04d.png" % index)

## Fila de tiles pegados sin separación (usada tanto para el fondo gris como
## para el relleno naranja de la barra de vida): cap izq + N tiles de
## relleno repetido + cap der, todos cuadrados de `cell_size` px.
func _make_bar_row(cap_l: int, mid: int, cap_r: int, mid_count: int, cell_size: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var indices: Array[int] = [cap_l]
	for i in range(mid_count):
		indices.append(mid)
	indices.append(cap_r)

	for idx in indices:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(cell_size, cell_size)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.texture = _ui_tex(idx)
		row.add_child(tr)

	return row

## Barra de vida del jefe: fondo gris fijo + relleno naranja recortado por el
## ancho de un Control con `clip_contents=true` (no `region_rect`: la barra
## está armada de varios tiles pegados, no es una sola textura continua, así
## que recortar el contenedor que los agrupa es más simple y no distorsiona
## ningún tile individual). El relleno se dibuja completo por debajo del
## recorte y se "vacía" achicando el ancho del contenedor desde la derecha —
## se ve igual que si drenara, sin estirar ni comprimir ningún tile.
func _make_boss_health_bar() -> void:
	var total_width: float = (BAR_MID_SEGMENTS + 2) * BAR_CELL_SIZE
	_boss_bar_full_width = total_width

	var root := Control.new()
	root.name = "BossHealthBar"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.offset_left = -total_width / 2.0
	root.offset_right = total_width / 2.0
	root.offset_top = 54.0
	root.offset_bottom = 54.0 + BAR_CELL_SIZE
	_hud.get_parent().add_child(root)

	var bg := _make_bar_row(BAR_BG_CAP_L, BAR_BG_MID, BAR_BG_CAP_R, BAR_MID_SEGMENTS, BAR_CELL_SIZE)
	root.add_child(bg)

	var fill_clip := Control.new()
	fill_clip.name = "FillClip"
	fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_clip.clip_contents = true
	fill_clip.position = Vector2.ZERO
	fill_clip.size = Vector2(total_width, BAR_CELL_SIZE)
	root.add_child(fill_clip)

	var fill := _make_bar_row(BAR_FILL_CAP_L, BAR_FILL_MID, BAR_FILL_CAP_R, BAR_MID_SEGMENTS, BAR_CELL_SIZE)
	fill_clip.add_child(fill)

	_boss_bar_bg = root
	_boss_bar_fill_clip = fill_clip

func _on_boss_health_changed(current: int, max_hp: int) -> void:
	if not is_instance_valid(_boss_bar_fill_clip):
		return
	var pct: float = 0.0
	if max_hp > 0:
		pct = clampf(float(current) / float(max_hp), 0.0, 1.0)
	_boss_bar_fill_clip.size = Vector2(_boss_bar_full_width * pct, BAR_CELL_SIZE)

## Compone los 9 tiles del panel (ver PANEL_TILE_INDICES) en una única
## Image de 48x48 y la envuelve en un ImageTexture — así el NinePatchRect
## de _show_main_menu() puede tratarlo como una textura de verdad con
## `patch_margin_*` en vez de necesitar 9 nodos separados.
func _make_panel_texture() -> ImageTexture:
	var full := Image.create(PANEL_TILE_PX * 3, PANEL_TILE_PX * 3, false, Image.FORMAT_RGBA8)
	for i in range(PANEL_TILE_INDICES.size()):
		var tile_img: Image = _ui_tex(PANEL_TILE_INDICES[i]).get_image()
		tile_img = tile_img.duplicate()
		tile_img.convert(Image.FORMAT_RGBA8)
		var col: int = i % 3
		var row: int = i / 3
		full.blit_rect(tile_img, Rect2i(0, 0, PANEL_TILE_PX, PANEL_TILE_PX), Vector2i(col * PANEL_TILE_PX, row * PANEL_TILE_PX))
	return ImageTexture.create_from_image(full)

## Ensambla texto con la fuente bitmap del pack (solo A-Z y 0-9, ver
## FONT_CHAR_INDEX — no hay minúsculas ni signos): un TextureRect por
## carácter en un HBoxContainer, espacio real para " " (un Control vacío del
## mismo ancho de celda). Caracteres sin mapeo (no debería pasar con los
## textos de esta pantalla) se saltean en silencio.
func _make_bitmap_text(text: String, cell_size: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(cell_size * 0.15))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for ch in text.to_upper():
		if ch == " ":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(cell_size * 0.6, cell_size)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(spacer)
			continue
		if not FONT_CHAR_INDEX.has(ch):
			continue
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(cell_size, cell_size)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.texture = _ui_tex(FONT_CHAR_INDEX[ch])
		row.add_child(tr)

	return row

## Botón mínimo con el mismo criterio de MOUSE_FILTER_IGNORE que
## UpgradeUI._make_card_button() (todo hijo de un Button necesita
## MOUSE_FILTER_IGNORE o el click deja de registrar en silencio) pero sin
## reusar ese método directamente: vive en otro nodo (UpgradeUI, no Main) y
## esta pantalla solo necesita un botón de texto simple, no la tarjeta con
## ícono+descripción.
func _make_menu_button(label: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(200, 56)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)

	var text_row := _make_bitmap_text(label, 18.0)
	center.add_child(text_row)

	return btn

## Menú principal, primera pantalla del demo (antes de "Elegí tu arma
## inicial"): CanvasLayer con panel 9-slice centrado, título en la fuente
## bitmap del pack y un único botón "Jugar" — sin "Salir" ni opciones, a
## propósito (ver plan v2, Cambio 3). Oculta el menú y dispara
## _start_weapon_pick() al tocar el botón.
func _show_main_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MainMenu"
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)

	var panel_w := 420.0
	var panel_h := 300.0
	var panel := NinePatchRect.new()
	panel.texture = _make_panel_texture()
	panel.patch_margin_left = PANEL_TILE_PX
	panel.patch_margin_right = PANEL_TILE_PX
	panel.patch_margin_top = PANEL_TILE_PX
	panel.patch_margin_bottom = PANEL_TILE_PX
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_w / 2.0
	panel.offset_right = panel_w / 2.0
	panel.offset_top = -panel_h / 2.0
	panel.offset_bottom = panel_h / 2.0
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	panel.add_child(vbox)

	var title_center := CenterContainer.new()
	title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_center)
	title_center.add_child(_make_bitmap_text("JUSTICIERO", 26.0))

	var btn_center := CenterContainer.new()
	btn_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(btn_center)
	var play_btn := _make_menu_button("JUGAR")
	play_btn.pressed.connect(_on_menu_play_pressed.bind(layer))
	btn_center.add_child(play_btn)

func _on_menu_play_pressed(layer: CanvasLayer) -> void:
	layer.queue_free()
	_start_weapon_pick()
