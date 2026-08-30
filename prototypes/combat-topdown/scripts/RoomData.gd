extends RefCounted
class_name RoomData

## Datos estáticos de las 7 salas de la mazmorra (v2, cierre del demo):
## room_1 -> elige puerta Este/Oeste -> room_2a/room_2b -> 1 puerta ->
## room_3 -> elige puerta Este/Oeste -> room_4a/room_4b -> 1 puerta ->
## room_boss. Mismo patrón que UpgradeTree.gd: todo dato, nada de escena
## nueva — Main.gd reposiciona los mismos 5 StaticBody2D de Props y
## reconstruye las paredes por código en vez de instanciar nada.
##
## Las 7 salas comparten la MISMA geometría exterior (900x640, paredes en
## los mismos 4 bordes) para no tocar los limit_* de la cámara ni el
## region_rect del fondo — lo único que cambia entre salas es qué pared
## tiene el hueco de puerta, qué props están visibles/dónde, el tinte del
## CanvasModulate, y qué tipos de enemigo puede spawnear Main.
##
## Campos de cada sala:
##   waves: Int            — oleadas normales antes de abrir la(s) puerta(s)
##                            (0 en room_boss: ahí no hay oleadas, se llama
##                            directo a Main._spawn_boss()).
##   enemy_types: Array[String] — subconjunto de ["grunt","runner","spitter"]
##                            habilitado en esta sala (además del gate normal
##                            por wave_number que ya existe en Main.gd).
##   doors: Dictionary      — lado ("east"/"west") -> id de sala destino.
##                            1 entrada = puerta única, se abre sola sin UI.
##                            2 entradas = se muestra UpgradeUI en modo
##                            "door_pick" para elegir.
##   props: Array[Dictionary] — 5 entradas, una por cada StaticBody2D fijo
##                            de Props (mismo orden que PROP_NAMES en
##                            Main.gd): {"visible": bool, "pos": Vector2}.
##   tint: Variant          — Color para el CanvasModulate, o null para usar
##                            el tinte por defecto de Main.tscn.
##   is_boss: bool          — true solo en room_boss.

const PROP_NAMES: Array[String] = ["Cactus1", "Cactus2", "Bones1", "Bones2", "RockFormation"]

static func get_room(id: String) -> Dictionary:
	return _rooms()[id]

static func _rooms() -> Dictionary:
	return {
		"room_1": {
			"id": "room_1",
			"waves": 2,
			"enemy_types": ["grunt"],
			"doors": {"east": "room_2a", "west": "room_2b"},
			"tint": null,
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(180, 90)},
				{"visible": true, "pos": Vector2(-220, -140)},
				{"visible": true, "pos": Vector2(260, -220)},
				{"visible": true, "pos": Vector2(-260, 180)},
				{"visible": true, "pos": Vector2(60, 240)},
			],
		},
		"room_2a": {
			"id": "room_2a",
			"waves": 2,
			"enemy_types": ["grunt", "runner"],
			"doors": {"east": "room_3"},
			"tint": Color(0.22, 0.15, 0.12, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(-200, 80)},
				{"visible": true, "pos": Vector2(200, -180)},
				{"visible": true, "pos": Vector2(-260, -220)},
				{"visible": true, "pos": Vector2(260, 200)},
				{"visible": true, "pos": Vector2(0, -260)},
			],
		},
		"room_2b": {
			"id": "room_2b",
			"waves": 2,
			"enemy_types": ["grunt", "runner", "spitter"],
			"doors": {"east": "room_3"},
			"tint": Color(0.12, 0.16, 0.22, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(220, 160)},
				{"visible": true, "pos": Vector2(-180, -100)},
				{"visible": true, "pos": Vector2(0, 240)},
				{"visible": true, "pos": Vector2(-260, 240)},
				{"visible": true, "pos": Vector2(260, -240)},
			],
		},
		"room_3": {
			"id": "room_3",
			"waves": 3,
			"enemy_types": ["grunt", "runner", "spitter"],
			"doors": {"east": "room_4a", "west": "room_4b"},
			"tint": Color(0.18, 0.18, 0.14, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(0, -240)},
				{"visible": true, "pos": Vector2(-260, 0)},
				{"visible": true, "pos": Vector2(260, 0)},
				{"visible": true, "pos": Vector2(-180, 220)},
				{"visible": true, "pos": Vector2(180, 220)},
			],
		},
		"room_4a": {
			"id": "room_4a",
			"waves": 3,
			"enemy_types": ["grunt", "runner", "spitter"],
			"doors": {"east": "room_boss"},
			"tint": Color(0.24, 0.10, 0.20, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(220, -200)},
				{"visible": true, "pos": Vector2(-220, 200)},
				{"visible": true, "pos": Vector2(0, 0)},
				{"visible": true, "pos": Vector2(-260, -220)},
				{"visible": true, "pos": Vector2(260, 220)},
			],
		},
		"room_4b": {
			"id": "room_4b",
			"waves": 3,
			"enemy_types": ["grunt", "runner", "spitter"],
			"doors": {"east": "room_boss"},
			"tint": Color(0.10, 0.20, 0.24, 1),
			"is_boss": false,
			"props": [
				{"visible": true, "pos": Vector2(-220, -200)},
				{"visible": true, "pos": Vector2(220, 200)},
				{"visible": true, "pos": Vector2(0, -240)},
				{"visible": true, "pos": Vector2(260, -220)},
				{"visible": true, "pos": Vector2(-260, 220)},
			],
		},
		"room_boss": {
			"id": "room_boss",
			"waves": 0,
			"enemy_types": [],
			"doors": {},
			"tint": Color(0.20, 0.08, 0.08, 1),
			"is_boss": true,
			"props": [
				{"visible": false, "pos": Vector2(180, 90)},
				{"visible": true, "pos": Vector2(-300, -240)},
				{"visible": false, "pos": Vector2(260, -220)},
				{"visible": true, "pos": Vector2(300, 240)},
				{"visible": true, "pos": Vector2(-300, 240)},
			],
		},
	}
