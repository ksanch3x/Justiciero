extends RefCounted
class_name WeaponData

## Roster estático de armas: 5 armas x 2 niveles ("naranja" nivel 1 / "turquesa"
## nivel 2 en Weapons/Tiles, ver STATUS.md "Mapa de assets"). Reemplaza los
## @export por-arma que vivían en Player.gd. Sin lambdas multilínea (no
## parsean dentro de literales de array/diccionario), todo con datos planos +
## static funcs, mismo patrón que UpgradeTree.gd.

const WEAPONS_DIR := "res://assets/desert-shooter-pack/Weapons/Tiles/"

## region_rect de cada tile calculado con Image.getbbox() (PIL) sobre el PNG
## real de 24x24 — no estimado, ver plan de implementación. Escalas elegidas
## para que todas las armas a distancia queden ~18-27px en pantalla.
static func _defs() -> Dictionary:
	return {
		"knife": {
			"name": "Cuchillo",
			"kind": "melee",
			"levels": [
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0008.png"),
					"region": Rect2(8, 5, 8, 13),
					"scale": Vector2(1.1, 1.1),
					"stats": {"damage": 2, "rate": 0.30, "range": 56.0, "knockback": 46.0},
				},
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0018.png"),
					"region": Rect2(9, 4, 7, 16),
					"scale": Vector2(1.0, 1.0),
					"stats": {"damage": 3, "rate": 0.26, "range": 62.0, "knockback": 52.0},
				},
			],
			"desc": "melee rápido y seguro",
		},
		"axe": {
			"name": "Hacha",
			"kind": "melee",
			"levels": [
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0009.png"),
					"region": Rect2(6, 3, 15, 19),
					"scale": Vector2(1.0, 1.0),
					"stats": {"damage": 5, "rate": 0.62, "range": 72.0, "knockback": 78.0},
				},
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0019.png"),
					"region": Rect2(4, 2, 16, 20),
					"scale": Vector2(1.0, 1.0),
					"stats": {"damage": 7, "rate": 0.55, "range": 80.0, "knockback": 90.0},
				},
			],
			"desc": "melee pesado: pega fuerte y lejos, pero castiga fallar",
		},
		"pistol": {
			"name": "Pistola",
			"kind": "ranged",
			"levels": [
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0001.png"),
					"region": Rect2(6, 8, 12, 8),
					"scale": Vector2(1.5, 1.5),
					"stats": {"damage": 2, "rate": 0.34, "mag": 10, "reload": 1.0, "count": 1, "spread": 3.0},
				},
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0011.png"),
					"region": Rect2(5, 8, 13, 9),
					"scale": Vector2(1.4, 1.4),
					"stats": {"damage": 3, "rate": 0.30, "mag": 12, "reload": 0.9, "count": 1, "spread": 3.0},
				},
			],
			"desc": "a distancia, intermedia entre SMG y escopeta",
		},
		"smg": {
			"name": "SMG",
			"kind": "ranged",
			"levels": [
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0002.png"),
					"region": Rect2(5, 6, 14, 12),
					"scale": Vector2(1.5, 1.5),
					"stats": {"damage": 1, "rate": 0.14, "mag": 20, "reload": 1.2, "count": 1, "spread": 8.0},
				},
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0012.png"),
					"region": Rect2(4, 5, 16, 14),
					"scale": Vector2(1.3, 1.3),
					"stats": {"damage": 2, "rate": 0.12, "mag": 26, "reload": 1.05, "count": 1, "spread": 8.0},
				},
			],
			"desc": "cadencia altísima, cargador grande, daño bajo por bala",
		},
		"shotgun": {
			"name": "Escopeta",
			"kind": "ranged",
			"levels": [
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0003.png"),
					"region": Rect2(1, 6, 22, 12),
					"scale": Vector2(1.2, 1.2),
					"stats": {"damage": 2, "rate": 0.85, "mag": 6, "reload": 1.8, "count": 6, "spread": 26.0},
				},
				{
					"texture": preload("res://assets/desert-shooter-pack/Weapons/Tiles/tile_0013.png"),
					"region": Rect2(1, 6, 22, 12),
					"scale": Vector2(1.2, 1.2),
					"stats": {"damage": 3, "rate": 0.75, "mag": 8, "reload": 1.6, "count": 7, "spread": 26.0},
				},
			],
			"desc": "cargador chico, abanico de proyectiles a corta distancia",
		},
	}

## Orden de progresión ranged usado por milestone_choices(): melee -> pistola
## -> SMG -> escopeta.
const RANGED_PROGRESSION := ["pistol", "smg", "shotgun"]
const MELEE_IDS := ["knife", "axe"]

static func all() -> Dictionary:
	return _defs()

static func is_ranged(id: String) -> bool:
	var defs := _defs()
	if not defs.has(id):
		return false
	return defs[id]["kind"] == "ranged"

static func weapon_name(id: String) -> String:
	var defs := _defs()
	if not defs.has(id):
		return ""
	return defs[id]["name"]

## Nombre + nivel en números romanos simples (solo hay 2 niveles).
static func display_name(id: String, level: int) -> String:
	var roman: String = "I" if level <= 1 else "II"
	return "%s %s" % [weapon_name(id), roman]

static func description(id: String) -> String:
	var defs := _defs()
	if not defs.has(id):
		return ""
	return defs[id]["desc"]

## Copia (duplicate()) de los stats base de `id` en `level`: si devolviera la
## referencia al diccionario estático, las mejoras (que mutan wstats in-place)
## contaminarían la tabla base para el resto de la corrida.
static func base_stats(id: String, level: int) -> Dictionary:
	var defs := _defs()
	if not defs.has(id):
		return {}
	var levels: Array = defs[id]["levels"]
	var idx: int = clamp(level - 1, 0, levels.size() - 1)
	var stats: Dictionary = levels[idx]["stats"]
	return stats.duplicate()

static func icon_texture(id: String, level: int) -> Texture2D:
	var defs := _defs()
	if not defs.has(id):
		return null
	var levels: Array = defs[id]["levels"]
	var idx: int = clamp(level - 1, 0, levels.size() - 1)
	return levels[idx]["texture"]

static func icon_region(id: String, level: int) -> Rect2:
	var defs := _defs()
	if not defs.has(id):
		return Rect2()
	var levels: Array = defs[id]["levels"]
	var idx: int = clamp(level - 1, 0, levels.size() - 1)
	return levels[idx]["region"]

static func icon_scale(id: String, level: int) -> Vector2:
	var defs := _defs()
	if not defs.has(id):
		return Vector2.ONE
	var levels: Array = defs[id]["levels"]
	var idx: int = clamp(level - 1, 0, levels.size() - 1)
	return levels[idx]["scale"]

## Opciones del hito (cada MILESTONE_EVERY oleadas): subir de nivel el arma
## equipada (solo si sigue en nivel 1) + hasta 2 armas nuevas siguiendo la
## progresión melee -> pistola -> SMG -> escopeta, más el melee que el jugador
## no eligió al empezar. Nunca ofrece un arma ya poseída al mismo nivel que ya
## tiene. Devuelve [] si no hay nada que ofrecer (Main cae al roll normal).
static func milestone_choices(player) -> Array:
	var choices := []

	if player.weapon_id != "" and player.weapon_level == 1:
		choices.append({
			"type": "weapon", "id": player.weapon_id, "level": 2,
			"name": display_name(player.weapon_id, 2),
			"desc": "Sube de nivel tu arma actual: %s" % description(player.weapon_id),
		})

	var new_weapon_ids := []

	# El melee que no eligió al empezar, si todavía no lo tiene.
	for melee_id in MELEE_IDS:
		if melee_id != player.weapon_id and not player.owned_weapons.has(melee_id):
			new_weapon_ids.append(melee_id)

	# Progresión ranged: ofrece la primera que el jugador todavía no tenga.
	var has_any_ranged := false
	for ranged_id in RANGED_PROGRESSION:
		if player.owned_weapons.has(ranged_id):
			has_any_ranged = true
			break
	if not has_any_ranged:
		new_weapon_ids.append("pistol")
	else:
		for i in range(RANGED_PROGRESSION.size()):
			var ranged_id: String = RANGED_PROGRESSION[i]
			if player.owned_weapons.has(ranged_id):
				continue
			var prev_owned: bool = (i == 0) or player.owned_weapons.has(RANGED_PROGRESSION[i - 1])
			if prev_owned:
				new_weapon_ids.append(ranged_id)
				break

	for wid in new_weapon_ids:
		if choices.size() >= 3:
			break
		choices.append({
			"type": "weapon", "id": wid, "level": 1,
			"name": display_name(wid, 1),
			"desc": description(wid),
		})

	return choices
