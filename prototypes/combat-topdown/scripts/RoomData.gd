extends RefCounted
class_name RoomData

## PLANTILLAS de sala: geometría reutilizable, sin conexiones.
##
## Estas 7 entradas NO son el recorrido — son las piezas. Quién va primero,
## a dónde lleva cada puerta y cuántas salas tiene la corrida lo decide
## `Dungeon.gd` en runtime (GDD Fase 6, generación procedural). Antes acá
## estaba cableada la cadena entera (`room_1` -> `room_2a`...), así que
## todas las corridas eran idénticas.
##
## Por eso una plantilla declara `door_slots` (DÓNDE puede haber una puerta)
## y no `doors` (a qué sala lleva): el destino lo completa el generador.
## Una plantilla con 2 slots puede usarse en una bifurcación; una con 1,
## solo como paso.
##
## Mismo patrón que UpgradeTree.gd: todo dato, nada de escena nueva —
## Main.gd construye la geometría por código en vez de instanciar.
##
## === Salas con FORMA (unión de rectángulos), no cajas ===
## Antes las 7 salas eran el mismo rectángulo fijo de 900x640 y las paredes
## eran 4 StaticBody2D fijos en Main.tscn. Ahora cada sala define `rects`:
## una lista de Rect2 en coordenadas de mundo cuya UNIÓN es el interior
## jugable. Main._build_walls_for_room() recorre el borde de esa unión y
## genera los muros; Main._apply_camera_limits() ajusta la cámara al
## bounding box. Eso permite pasillos, cuartos laterales y formas en L sin
## tocar código — solo datos acá.
##
## Reglas para editar `rects` (validadas por tools/validate_rooms.py, que
## corre sin Godot):
##  - Todos los rects de una sala deben formar UNA sola región conectada
##    (si dos no se tocan, queda una isla inalcanzable).
##  - Para que dos rects conecten de verdad tienen que SOLAPARSE, no solo
##    tocarse en el borde — el generador de muros trabaja sobre una grilla
##    de WALL_CELL px (ver Main.gd), y dos rects que solo comparten una
##    arista dejan una pared entre medio.
##  - `entry`, cada `spawns[i]` y cada `props[i].pos` tienen que caer
##    DENTRO de la unión; cada `door_slots[x]` tiene que caer SOBRE su
##    borde.
##
## Campos de cada sala:
##   rects: Array[Rect2]    — unión = interior jugable, en coords de mundo.
##   blockers: Array[Rect2] — muros INTERIORES sólidos (divisorias de
##                            oficina, columnas). Opcional. Sin esto una
##                            sala de varios rects queda como un espacio
##                            abierto con muescas, no como cuartos: los
##                            muros del borde solos no alcanzan. Un "vano"
##                            interno se modela dejando hueco ENTRE dos
##                            blockers, no restándoselo a uno.
##   entry: Vector2         — dónde aparece el jugador al entrar a la sala
##                            (antes era siempre (0,0), que con formas
##                            asimétricas puede caer fuera o dentro de un
##                            muro).
##   spawns: Array[Vector2] — puntos de aparición de enemigos de oleada
##                            (antes eran los 5 nodos fijos de SpawnPoints
##                            en Main.tscn, pensados para el rectángulo
##                            viejo, que en varias formas caían en un muro).
##   waves: int             — oleadas antes de abrir la(s) puerta(s)
##                            (0 en la del jefe: ahí se llama directo a
##                            Main._spawn_boss()).
##   enemy_types: Array[String] — subconjunto de ["grunt","runner","spitter"]
##                            habilitado acá (además del gate por
##                            wave_number que ya existe en Main.gd).
##   door_slots: Dictionary — lado ("east"/"west") -> Vector2, centro de un
##                            vano POSIBLE, sobre el borde de la unión. El
##                            destino lo completa Dungeon.gd al generar el
##                            recorrido (queda como `doors[side].to`).
##                            2 slots = la plantilla sirve para bifurcar.
##   props: Array[Dictionary] — 5 entradas, una por StaticBody2D fijo de
##                            Props (mismo orden que PROP_NAMES):
##                            {"visible": bool, "pos": Vector2}.
##   loot: Array[Dictionary] — contenedores fijos de botín (Fase 5):
##                            {"pos": Vector2, "amount": int}. Se colocan a
##                            propósito en las zonas de riesgo (oficinas sin
##                            salida, esquinas expuestas): el botín tiene que
##                            costar algo, si no la decisión de extraer no
##                            existe. Misma regla que props: dentro de la
##                            unión y sin pisar un blocker (validado).
##   tint: Variant          — Color para el CanvasModulate, o null para el
##                            tinte por defecto de Main.tscn.
##   is_boss: bool          — true solo en la plantilla del jefe.

const PROP_NAMES: Array[String] = ["Cactus1", "Cactus2", "Bones1", "Bones2", "RockFormation"]

static func get_template(id: String) -> Dictionary:
	return _templates()[id]

static func has_template(id: String) -> bool:
	return _templates().has(id)

static func all_ids() -> Array:
	return _templates().keys()

static func _templates() -> Dictionary:
	return {
		# Entrada: sala central con dos pasillos laterales que terminan en
		# las puertas. Enseña el mecanismo de "elegir puerta" con la forma
		# más simple que ya no es una caja.
		"cruz": {
			"id": "cruz",
			"loot": [
				{"pos": Vector2(-520, 0), "amount": 25},
				{"pos": Vector2(-300, 210), "amount": 20},
			],
			"rects": [
				Rect2(-360, -260, 480, 520),
				Rect2(100, -60, 300, 120),
				Rect2(-560, -60, 220, 120),
			],
			"entry": Vector2(-120, 0),
			"spawns": [
				Vector2(-280, -200), Vector2(40, -200),
				Vector2(-280, 200), Vector2(40, 200), Vector2(-120, -210),
			],
			"waves": 2,
			"enemy_types": ["grunt"],
			"door_slots": {"east": Vector2(400, 0), "west": Vector2(-560, 0)},
			"tint": null,
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(-200, -120)},
				{"visible": true, "pos": Vector2(-40, 140)},
				{"visible": true, "pos": Vector2(20, -160)},
				{"visible": true, "pos": Vector2(-260, 60)},
				{"visible": true, "pos": Vector2(60, 20)},
			],
		},
		# Oficinas: bullpen abierto + pasillo vertical + dos oficinas de una
		# sola puerta. La del norte es callejón sin salida (botín/riesgo);
		# la del sur lleva a la salida.
		"oficinas": {
			"id": "oficinas",
			"loot": [
				{"pos": Vector2(380, -170), "amount": 35},
				{"pos": Vector2(380, 170), "amount": 25},
			],
			"rects": [
				Rect2(-420, -280, 540, 560),
				Rect2(100, -230, 360, 460),
			],
			# Dos divisorias horizontales parten el ala este en tres bandas
			# (oficina norte / pasillo central / oficina sur). El hueco
			# entre los dos tramos de cada divisoria ES la puerta de esa
			# oficina: una sola entrada, sin salida alternativa.
			"blockers": [
				Rect2(100, -90, 120, 20), Rect2(300, -90, 160, 20),
				Rect2(100, 70, 120, 20), Rect2(300, 70, 160, 20),
			],
			"entry": Vector2(-360, 0),
			"spawns": [
				Vector2(-340, -220), Vector2(-40, -220),
				Vector2(-340, 220), Vector2(-40, 220), Vector2(-200, 0),
			],
			"waves": 2,
			"enemy_types": ["grunt", "runner"],
			"door_slots": {"east": Vector2(460, 135)},
			"tint": Color(0.22, 0.15, 0.12, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(-260, -140)},
				{"visible": true, "pos": Vector2(-100, 60)},
				{"visible": true, "pos": Vector2(-300, 160)},
				{"visible": true, "pos": Vector2(0, -160)},
				{"visible": true, "pos": Vector2(340, -140)},
			],
		},
		# Estacionamiento: el lote más abierto de todos, a propósito — es
		# donde Policía y Criminal tienen espacio real para cruzarse.
		"estacionamiento": {
			"id": "estacionamiento",
			"loot": [
				{"pos": Vector2(-390, -280), "amount": 30},
				{"pos": Vector2(390, 280), "amount": 25},
			],
			"rects": [
				Rect2(-440, -320, 880, 640),
			],
			# Grilla de 20 columnas: cobertura Y carriles de patrulla al
			# mismo tiempo. Es lo que evita que el lote grande se sienta un
			# campo abierto vacío — sin ellas no hay dónde romper línea de
			# visión en la sala más ancha del recorrido.
			"blockers": [
				Rect2(-320, -240, 40, 40), Rect2(-170, -240, 40, 40), Rect2(-20, -240, 40, 40), Rect2(130, -240, 40, 40), Rect2(280, -240, 40, 40),
				Rect2(-320, -95, 40, 40), Rect2(-170, -95, 40, 40), Rect2(-20, -95, 40, 40), Rect2(130, -95, 40, 40), Rect2(280, -95, 40, 40),
				Rect2(-320, 50, 40, 40), Rect2(-170, 50, 40, 40), Rect2(-20, 50, 40, 40), Rect2(130, 50, 40, 40), Rect2(280, 50, 40, 40),
				Rect2(-320, 195, 40, 40), Rect2(-170, 195, 40, 40), Rect2(-20, 195, 40, 40), Rect2(130, 195, 40, 40), Rect2(280, 195, 40, 40),
			],
			"entry": Vector2(-380, 0),
			"spawns": [
				Vector2(-380, -260), Vector2(380, -260),
				Vector2(-380, 260), Vector2(380, 260), Vector2(0, -280),
			],
			"waves": 2,
			"enemy_types": ["grunt", "runner", "spitter"],
			"door_slots": {"east": Vector2(440, 0)},
			"tint": Color(0.12, 0.16, 0.22, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(-240, -160)},
				{"visible": true, "pos": Vector2(-60, -160)},
				{"visible": true, "pos": Vector2(120, -160)},
				{"visible": true, "pos": Vector2(-240, 160)},
				{"visible": true, "pos": Vector2(120, 160)},
			],
		},
		# Andén: pasillo largo con dos alcobas sin salida. La sala más
		# expuesta — casi sin cobertura, obliga a leer las patrullas.
		"anden": {
			"id": "anden",
			"loot": [
				{"pos": Vector2(-200, 180), "amount": 30},
				{"pos": Vector2(240, 180), "amount": 30},
			],
			"rects": [
				Rect2(-620, -80, 1240, 160),
				Rect2(-280, 60, 160, 190),
				Rect2(160, 60, 160, 190),
			],
			"entry": Vector2(-560, 0),
			"spawns": [
				Vector2(-480, 0), Vector2(-160, 0),
				Vector2(160, 0), Vector2(480, 0), Vector2(0, 0),
			],
			"waves": 3,
			"enemy_types": ["grunt", "runner", "spitter"],
			"door_slots": {"east": Vector2(620, 0), "west": Vector2(-620, 0)},
			"tint": Color(0.18, 0.18, 0.14, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(-360, -20)},
				{"visible": true, "pos": Vector2(60, 20)},
				{"visible": true, "pos": Vector2(380, -20)},
				{"visible": true, "pos": Vector2(-220, 160)},
				{"visible": true, "pos": Vector2(220, 160)},
			],
		},
		# Sala en L: la forma obliga a doblar sin ver lo que hay del otro
		# lado — buen terreno para que una patrulla te sorprenda.
		"ele": {
			"id": "ele",
			"loot": [
				{"pos": Vector2(-300, 220), "amount": 35},
			],
			"rects": [
				Rect2(-420, -280, 500, 280),
				Rect2(-420, -20, 240, 300),
			],
			"entry": Vector2(-360, -140),
			"spawns": [
				Vector2(-340, -220), Vector2(0, -220),
				Vector2(-340, 200), Vector2(-240, 60), Vector2(-100, -100),
			],
			"waves": 3,
			"enemy_types": ["grunt", "runner", "spitter"],
			"door_slots": {"east": Vector2(80, -140)},
			"tint": Color(0.24, 0.10, 0.20, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(-200, -200)},
				{"visible": true, "pos": Vector2(-60, -60)},
				{"visible": true, "pos": Vector2(-320, -80)},
				{"visible": true, "pos": Vector2(-300, 140)},
				{"visible": true, "pos": Vector2(-380, 20)},
			],
		},
		# Dos cámaras unidas por un cuello angosto: el cuello es un cuello
		# de botella real, se pelea distinto a cada lado.
		"camaras": {
			"id": "camaras",
			"loot": [
				{"pos": Vector2(-400, 200), "amount": 25},
				{"pos": Vector2(400, -200), "amount": 25},
			],
			"rects": [
				Rect2(-460, -240, 360, 480),
				Rect2(-120, -90, 260, 180),
				Rect2(120, -240, 360, 480),
			],
			"entry": Vector2(-400, 0),
			"spawns": [
				Vector2(-380, -180), Vector2(-380, 180),
				Vector2(400, -180), Vector2(400, 180), Vector2(0, 0),
			],
			"waves": 3,
			"enemy_types": ["grunt", "runner", "spitter"],
			"door_slots": {"east": Vector2(480, 0)},
			"tint": Color(0.10, 0.20, 0.24, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(-300, -120)},
				{"visible": true, "pos": Vector2(-300, 120)},
				{"visible": true, "pos": Vector2(300, -120)},
				{"visible": true, "pos": Vector2(300, 120)},
				{"visible": false, "pos": Vector2(0, 0)},
			],
		},
		# Arena del jefe: abierta y sin cobertura útil — la pelea no tiene
		# dónde esconderse, a propósito.
		"arena_jefe": {
			"id": "arena_jefe",
			"loot": [],
			"rects": [
				Rect2(-460, -320, 920, 640),
			],
			"entry": Vector2(0, 240),
			"spawns": [
				Vector2(0, -240), Vector2(-300, -200),
				Vector2(300, -200), Vector2(-300, 200), Vector2(300, 200),
			],
			"waves": 0,
			"enemy_types": [],
			"door_slots": {},
			"tint": Color(0.20, 0.08, 0.08, 1),
			"is_boss": true,
			"props": [
				{"visible": false, "pos": Vector2(0, 0)},
				{"visible": true, "pos": Vector2(-380, -260)},
				{"visible": false, "pos": Vector2(0, 0)},
				{"visible": true, "pos": Vector2(380, 260)},
				{"visible": true, "pos": Vector2(-380, 260)},
			],
		},
	}
