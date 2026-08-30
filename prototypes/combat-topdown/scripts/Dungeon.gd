extends Node

## Autoload — arma el recorrido de la incursión combinando las PLANTILLAS
## de sala de RoomData.gd (GDD hoja de ruta, Fase 6: "generación procedural
## real de la conexión de salas").
##
## Antes las 7 salas estaban cableadas a mano en RoomData: id fijo, puerta
## fija a un id fijo. Cada corrida recorría exactamente lo mismo. Ahora
## RoomData solo aporta la GEOMETRÍA reutilizable (forma, props, spawns,
## door_slots) y acá se decide, en cada corrida, qué plantilla va en qué
## lugar y a dónde lleva cada puerta.
##
## Qué NO hace (a propósito): no genera formas nuevas ni coloca rects al
## azar. Las salas siguen siendo diseñadas a mano — lo procedural es el
## ORDEN y las CONEXIONES. Un generador de formas reales daría salas sin
## intención de diseño, que es justo lo que las plantillas evitan (ver el
## documento de planos de planta).
##
## Estructura del recorrido — LAYER_SIZES describe cuántas salas hay en
## cada capa, y la última capa siempre es el jefe:
##
##     capa0 (1 sala)  --2 puertas-->  capa1 (2 salas, se elige una)
##          \--------------------------------/
##                          |  ambas convergen
##                          v
##     capa2 (1 sala)  --2 puertas-->  capa3 (2 salas)
##                          |
##                          v
##                    sala del jefe
##
## Una sala en una capa de 1 que va hacia una capa de 2 necesita plantilla
## con DOS door_slots; el resto alcanza con uno.

## Cuántas salas por capa, sin contar la del jefe (que va siempre al final).
## Cambiar esto cambia el largo/forma del recorrido sin tocar nada más.
const LAYER_SIZES: Array[int] = [1, 2, 1, 2]

## id de la plantilla que se usa siempre como sala del jefe.
const BOSS_TEMPLATE: String = "arena_jefe"
## id de la plantilla de la primera sala. Fija a propósito: la entrada es
## la que le enseña al jugador el mecanismo de elegir puerta, conviene que
## sea siempre la más legible.
const ENTRY_TEMPLATE: String = "cruz"

## id de sala -> dict de sala ya resuelto (misma forma que consumía
## Main.gd antes, con `doors` completo: lado -> {"to", "pos"}).
var _map: Dictionary = {}
var _start_id: String = ""
## Semilla usada en la corrida actual. Se imprime al generar: si aparece un
## recorrido roto o injugable, se puede reproducir exactamente pasando esta
## semilla a generate().
var seed_used: int = 0

func get_room(id: String) -> Dictionary:
	return _map[id]

func has_room(id: String) -> bool:
	return _map.has(id)

func start_room_id() -> String:
	return _start_id

## Genera un recorrido nuevo. `rng_seed < 0` = semilla aleatoria.
func generate(rng_seed: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed < 0:
		rng.randomize()
		seed_used = int(rng.seed)
	else:
		rng.seed = rng_seed
		seed_used = rng_seed

	_map = {}

	# 1) Ids de cada capa, más la capa final del jefe.
	var layers: Array = []
	for layer_index in range(LAYER_SIZES.size()):
		var ids: Array[String] = []
		for slot in range(LAYER_SIZES[layer_index]):
			ids.append("r%d_%d" % [layer_index, slot])
		layers.append(ids)
	var boss_id: String = "r_boss"
	layers.append([boss_id] as Array[String])

	# 2) Elegir plantilla para cada sala. Cuántas puertas necesita cada una
	#    sale de cuántas salas tiene la capa SIGUIENTE.
	var used_templates: Array[String] = []
	for layer_index in range(layers.size() - 1):
		var next_count: int = layers[layer_index + 1].size()
		var doors_needed: int = next_count
		for id in layers[layer_index]:
			var template_id: String = ""
			if layer_index == 0:
				template_id = ENTRY_TEMPLATE
			else:
				template_id = _pick_template(rng, doors_needed, used_templates)
			used_templates.append(template_id)
			_map[id] = _instantiate_template(template_id, id)

	_map[boss_id] = _instantiate_template(BOSS_TEMPLATE, boss_id)

	# 3) Conectar: cada sala de una capa apunta a las de la capa siguiente.
	#    Con capa siguiente de 2, las dos puertas van a una sala cada una
	#    (la bifurcación real); con capa siguiente de 1, todas convergen.
	for layer_index in range(layers.size() - 1):
		var next_ids: Array = layers[layer_index + 1]
		for id in layers[layer_index]:
			var room: Dictionary = _map[id]
			var slots: Dictionary = room["door_slots"]
			var sides: Array = _ordered_sides(slots)
			var doors: Dictionary = {}
			for i in range(next_ids.size()):
				if i >= sides.size():
					# La plantilla no tiene tantos slots como salidas pedía
					# la capa: _pick_template ya lo evita, pero si alguna vez
					# se agrega una plantilla mal etiquetada, es mejor una
					# puerta de menos que un índice fuera de rango.
					break
				var side: String = sides[i]
				doors[side] = {"to": next_ids[i], "pos": slots[side]}
			room["doors"] = doors

	_map[boss_id]["doors"] = {}
	_start_id = layers[0][0]

	print("[Dungeon] recorrido generado, semilla=%d, salas=%d" % [seed_used, _map.size()])

## Elige una plantilla con al menos `doors_needed` slots, prefiriendo las
## que todavía no salieron en esta corrida (para que un recorrido no repita
## la misma sala dos veces si hay alternativas).
func _pick_template(rng: RandomNumberGenerator, doors_needed: int, used: Array[String]) -> String:
	var eligible: Array[String] = []
	for template_id in RoomData.all_ids():
		var template: Dictionary = RoomData.get_template(template_id)
		if bool(template["is_boss"]):
			continue
		if template["door_slots"].size() < doors_needed:
			continue
		eligible.append(template_id)

	var fresh: Array[String] = []
	for template_id in eligible:
		if not used.has(template_id):
			fresh.append(template_id)
	var pool: Array[String] = fresh if not fresh.is_empty() else eligible
	# Si no hubiera ninguna elegible (no debería: hay 2 plantillas con 2
	# slots), se cae a la de entrada antes que romper la generación.
	if pool.is_empty():
		return ENTRY_TEMPLATE
	return pool[rng.randi_range(0, pool.size() - 1)]

## Orden fijo Este-antes-que-Oeste, para que la UI de elección de puerta
## (UpgradeUI, modo "door_pick") liste siempre igual y no dependa del orden
## de inserción del Dictionary.
func _ordered_sides(slots: Dictionary) -> Array:
	var out: Array = []
	for side in ["east", "west", "north", "south"]:
		if slots.has(side):
			out.append(side)
	return out

## Copia el dict de la plantilla para esta sala concreta. `duplicate(true)`
## es importante: sin copia profunda, dos salas generadas desde la misma
## plantilla compartirían los mismos sub-diccionarios y escribir `doors` en
## una pisaría la otra.
func _instantiate_template(template_id: String, room_id: String) -> Dictionary:
	var room: Dictionary = RoomData.get_template(template_id).duplicate(true)
	room["id"] = room_id
	room["template"] = template_id
	if not room.has("blockers"):
		room["blockers"] = []
	return room
