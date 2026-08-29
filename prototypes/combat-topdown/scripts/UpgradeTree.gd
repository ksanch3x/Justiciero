extends RefCounted
class_name UpgradeTree

## Árbol de mejoras de UNA corrida (no persistente: se resetea junto con toda
## la escena cuando Main llama a get_tree().reload_current_scene()).
## Reemplaza al viejo UpgradePool (selección plana al azar) por nodos con
## tier/requires/excludes dentro de 3 ramas: ofensiva (off), movilidad (mov)
## y supervivencia (sur). La exclusión es SOLO dentro de cada rama, no hay
## exclusión cruzada entre ramas (decisión confirmada por el usuario).

# ---------------------------------------------------------------------------
# Rama OFENSIVA — kind "ranged" opera sobre p.wstats (arma a distancia
# equipada), kind "melee" sobre p.wstats (arma cuerpo a cuerpo equipada).
# Las armas en sí ya NO salen de acá (ver WeaponData.gd / hitos en Main.gd) —
# estos nodos solo mejoran el arma que ya tenés equipada, y se filtran por
# `kind` antes de ofrecerse (ver UpgradeTree.get_available).
# ---------------------------------------------------------------------------

static func _apply_off_t1_rate(p: CharacterBody2D) -> void:
	p.wstats["rate"] = max(0.05, float(p.wstats.get("rate", 0.2)) * 0.85)

static func _apply_off_t1_dmg(p: CharacterBody2D) -> void:
	p.wstats["damage"] = int(p.wstats.get("damage", 1)) + 1

static func _apply_off_t2_burst(p: CharacterBody2D) -> void:
	p.wstats["count"] = int(p.wstats.get("count", 1)) + 1
	p.wstats["damage"] = max(1, int(p.wstats.get("damage", 1)) - 1)

static func _apply_off_t2_heavy(p: CharacterBody2D) -> void:
	p.wstats["damage"] = int(p.wstats.get("damage", 1)) + 2
	p.wstats["rate"] = float(p.wstats.get("rate", 0.2)) * 1.15

static func _apply_off_t3_glasscannon(p: CharacterBody2D) -> void:
	p.wstats["damage"] = int(p.wstats.get("damage", 1)) + 3
	p.max_health = max(1, p.max_health - 2)
	if p.health > p.max_health:
		p.health = p.max_health
	p.health_changed.emit(p.health, p.max_health)

static func _apply_off_t3_swarm(p: CharacterBody2D) -> void:
	p.wstats["count"] = int(p.wstats.get("count", 1)) + 2
	p.wstats["spread"] = float(p.wstats.get("spread", 8.0)) * 1.5

## off_t1_mag: +40% de cargador (redondeado hacia arriba), y el excedente se
## suma a la munición actual (no fuerza recarga). Única mejora que toca el
## recurso munición, que hasta ahora ninguna mejora tocaba.
static func _apply_off_t1_mag(p: CharacterBody2D) -> void:
	var old_mag: int = int(p.wstats.get("mag", 1))
	var new_mag: int = int(ceil(old_mag * 1.4))
	p.wstats["mag"] = new_mag
	p.current_mag_size = new_mag
	p.current_ammo += (new_mag - old_mag)

static func _apply_off_t1_swing(p: CharacterBody2D) -> void:
	p.wstats["rate"] = max(0.05, float(p.wstats.get("rate", 0.3)) * 0.85)

static func _apply_off_t1_edge(p: CharacterBody2D) -> void:
	p.wstats["damage"] = int(p.wstats.get("damage", 1)) + 1

static func _apply_off_t2_reach(p: CharacterBody2D) -> void:
	p.wstats["range"] = float(p.wstats.get("range", 40.0)) * 1.25
	p.wstats["knockback"] = float(p.wstats.get("knockback", 40.0)) + 12.0

static func _apply_off_t2_brutal(p: CharacterBody2D) -> void:
	p.wstats["damage"] = int(p.wstats.get("damage", 1)) + 3
	p.wstats["rate"] = float(p.wstats.get("rate", 0.3)) * 1.2

static func _apply_off_t3_whirl(p: CharacterBody2D) -> void:
	p.wstats["range"] = float(p.wstats.get("range", 40.0)) * 1.4
	p.wstats["damage"] = max(1, int(p.wstats.get("damage", 1)) - 1)

static func _apply_off_t3_exec(p: CharacterBody2D) -> void:
	p.wstats["damage"] = int(p.wstats.get("damage", 1)) + 5
	p.wstats["rate"] = float(p.wstats.get("rate", 0.3)) * 1.3

# ---------------------------------------------------------------------------
# Rama MOVILIDAD
# ---------------------------------------------------------------------------

static func _apply_mov_t1_cd(p: CharacterBody2D) -> void:
	p.dash_cooldown *= 0.75

static func _apply_mov_t1_dur(p: CharacterBody2D) -> void:
	p.dash_duration *= 1.3

static func _apply_mov_t2_chain(p: CharacterBody2D) -> void:
	p.has_chain_dash = true
	p.dash_charges_max = 2

static func _apply_mov_t2_armored(p: CharacterBody2D) -> void:
	p.dash_invulnerable = true
	p.has_dash_push = true
	p.dash_duration *= 0.8

static func _apply_mov_t3_phantom(p: CharacterBody2D) -> void:
	p.can_shoot_while_dashing = true
	p.dash_speed *= 0.85

static func _apply_mov_t3_juggernaut(p: CharacterBody2D) -> void:
	p.dash_speed *= 1.4
	p.has_dash_damage = true
	# Simplificación deliberada: el GDD original pedía fire_rate x1.1
	# "aplicado una sola vez cada vez que termina un dash" (efecto temporal
	# por dash). Para no meter un sistema de timers/buffs temporales al
	# fire_rate solo por este nodo, se aplica UNA VEZ y de forma PERMANENTE
	# al tomar el nodo (penalización fija de cadencia a cambio del dash
	# más rápido y dañino). Documentado también en el reporte final.
	p.fire_rate *= 1.1

# ---------------------------------------------------------------------------
# Rama SUPERVIVENCIA
# ---------------------------------------------------------------------------

static func _apply_sur_t1_hp(p: CharacterBody2D) -> void:
	p.max_health += 1
	p.health += 1
	p.health_changed.emit(p.health, p.max_health)

static func _apply_sur_t1_regen(p: CharacterBody2D) -> void:
	p.has_wave_regen = true

static func _apply_sur_t2_thick(p: CharacterBody2D) -> void:
	p.max_health += 3
	p.health += 3
	p.health_changed.emit(p.health, p.max_health)
	p.speed *= 0.9

static func _apply_sur_t2_lifesteal(p: CharacterBody2D) -> void:
	p.has_lifesteal = true

static func _apply_sur_t3_secondwind(p: CharacterBody2D) -> void:
	p.has_second_wind_available = true

static func _apply_sur_t3_adrenaline(p: CharacterBody2D) -> void:
	p.has_adrenaline = true
	p.max_health = max(1, p.max_health - 1)
	if p.health > p.max_health:
		p.health = p.max_health
	p.health_changed.emit(p.health, p.max_health)

# ---------------------------------------------------------------------------
# Datos del árbol
# ---------------------------------------------------------------------------

static func get_all() -> Array:
	return [
		{"id": "off_t1_rate", "name": "Cadencia +", "desc": "cadencia de disparo x0.85 (más rápida)",
			"apply": Callable(UpgradeTree, "_apply_off_t1_rate"),
			"branch": "off", "kind": "ranged", "tier": 1, "requires": [], "excludes": []},
		{"id": "off_t1_dmg", "name": "Daño +", "desc": "daño de bala +1",
			"apply": Callable(UpgradeTree, "_apply_off_t1_dmg"),
			"branch": "off", "kind": "ranged", "tier": 1, "requires": [], "excludes": []},
		{"id": "off_t1_mag", "name": "Cargador Extendido", "desc": "cargador +40%",
			"apply": Callable(UpgradeTree, "_apply_off_t1_mag"),
			"branch": "off", "kind": "ranged", "tier": 1, "requires": [], "excludes": []},
		{"id": "off_t2_burst", "name": "Ráfaga", "desc": "+1 proyectil, daño de bala -1 (mín 1)",
			"apply": Callable(UpgradeTree, "_apply_off_t2_burst"),
			"branch": "off", "kind": "ranged", "tier": 2, "requires": ["off_t1_rate"], "excludes": ["off_t2_heavy"]},
		{"id": "off_t2_heavy", "name": "Bala Pesada", "desc": "daño de bala +2, cadencia x1.15 (más lenta)",
			"apply": Callable(UpgradeTree, "_apply_off_t2_heavy"),
			"branch": "off", "kind": "ranged", "tier": 2, "requires": ["off_t1_dmg"], "excludes": ["off_t2_burst"]},
		{"id": "off_t3_glasscannon", "name": "Cañón de Cristal", "desc": "daño de bala +3, vida máx -2",
			"apply": Callable(UpgradeTree, "_apply_off_t3_glasscannon"),
			"branch": "off", "kind": "ranged", "tier": 3, "requires": ["off_t2_heavy"], "excludes": ["off_t3_swarm"]},
		{"id": "off_t3_swarm", "name": "Enjambre", "desc": "+2 proyectiles, +50% dispersión de disparo",
			"apply": Callable(UpgradeTree, "_apply_off_t3_swarm"),
			"branch": "off", "kind": "ranged", "tier": 3, "requires": ["off_t2_burst"], "excludes": ["off_t3_glasscannon"]},

		{"id": "off_t1_swing", "name": "Filo Rápido", "desc": "cadencia de golpe x0.85 (más rápida)",
			"apply": Callable(UpgradeTree, "_apply_off_t1_swing"),
			"branch": "off", "kind": "melee", "tier": 1, "requires": [], "excludes": []},
		{"id": "off_t1_edge", "name": "Filo Pesado", "desc": "daño de golpe +1",
			"apply": Callable(UpgradeTree, "_apply_off_t1_edge"),
			"branch": "off", "kind": "melee", "tier": 1, "requires": [], "excludes": []},
		{"id": "off_t2_reach", "name": "Alcance", "desc": "alcance x1.25, empuje +12",
			"apply": Callable(UpgradeTree, "_apply_off_t2_reach"),
			"branch": "off", "kind": "melee", "tier": 2, "requires": ["off_t1_swing"], "excludes": ["off_t2_brutal"]},
		{"id": "off_t2_brutal", "name": "Brutalidad", "desc": "daño +3, cadencia x1.2 (más lenta)",
			"apply": Callable(UpgradeTree, "_apply_off_t2_brutal"),
			"branch": "off", "kind": "melee", "tier": 2, "requires": ["off_t1_edge"], "excludes": ["off_t2_reach"]},
		{"id": "off_t3_whirl", "name": "Torbellino", "desc": "alcance x1.4, daño -1",
			"apply": Callable(UpgradeTree, "_apply_off_t3_whirl"),
			"branch": "off", "kind": "melee", "tier": 3, "requires": ["off_t2_reach"], "excludes": ["off_t3_exec"]},
		{"id": "off_t3_exec", "name": "Verdugo", "desc": "daño +5, cadencia x1.3 (mucho más lenta)",
			"apply": Callable(UpgradeTree, "_apply_off_t3_exec"),
			"branch": "off", "kind": "melee", "tier": 3, "requires": ["off_t2_brutal"], "excludes": ["off_t3_whirl"]},

		{"id": "mov_t1_cd", "name": "Reflejos", "desc": "cooldown de dash x0.75",
			"apply": Callable(UpgradeTree, "_apply_mov_t1_cd"),
			"branch": "mov", "kind": "", "tier": 1, "requires": [], "excludes": []},
		{"id": "mov_t1_dur", "name": "Impulso", "desc": "duración de dash x1.3",
			"apply": Callable(UpgradeTree, "_apply_mov_t1_dur"),
			"branch": "mov", "kind": "", "tier": 1, "requires": [], "excludes": []},
		{"id": "mov_t2_chain", "name": "Dash Encadenado", "desc": "2do dash inmediato; el siguiente cooldown se duplica",
			"apply": Callable(UpgradeTree, "_apply_mov_t2_chain"),
			"branch": "mov", "kind": "", "tier": 2, "requires": ["mov_t1_cd"], "excludes": ["mov_t2_armored"]},
		{"id": "mov_t2_armored", "name": "Esquiva Blindada", "desc": "empuja enemigos cercanos al terminar el dash, duración x0.8",
			"apply": Callable(UpgradeTree, "_apply_mov_t2_armored"),
			"branch": "mov", "kind": "", "tier": 2, "requires": ["mov_t1_dur"], "excludes": ["mov_t2_chain"]},
		{"id": "mov_t3_phantom", "name": "Fantasma", "desc": "podés disparar durante el dash, velocidad de dash x0.85",
			"apply": Callable(UpgradeTree, "_apply_mov_t3_phantom"),
			"branch": "mov", "kind": "", "tier": 3, "requires": ["mov_t2_chain"], "excludes": ["mov_t3_juggernaut"]},
		{"id": "mov_t3_juggernaut", "name": "Titán", "desc": "velocidad de dash x1.4 y daña al tocar enemigos; cadencia x1.1 permanente",
			"apply": Callable(UpgradeTree, "_apply_mov_t3_juggernaut"),
			"branch": "mov", "kind": "", "tier": 3, "requires": ["mov_t2_armored"], "excludes": ["mov_t3_phantom"]},

		{"id": "sur_t1_hp", "name": "Vitalidad", "desc": "vida máx +1, vida actual +1",
			"apply": Callable(UpgradeTree, "_apply_sur_t1_hp"),
			"branch": "sur", "kind": "", "tier": 1, "requires": [], "excludes": []},
		{"id": "sur_t1_regen", "name": "Recuperación", "desc": "cura 1 de vida al superar cada oleada",
			"apply": Callable(UpgradeTree, "_apply_sur_t1_regen"),
			"branch": "sur", "kind": "", "tier": 1, "requires": [], "excludes": []},
		{"id": "sur_t2_thick", "name": "Piel Gruesa", "desc": "vida máx +3, velocidad x0.9",
			"apply": Callable(UpgradeTree, "_apply_sur_t2_thick"),
			"branch": "sur", "kind": "", "tier": 2, "requires": ["sur_t1_hp"], "excludes": ["sur_t2_lifesteal"]},
		{"id": "sur_t2_lifesteal", "name": "Robo de Vida", "desc": "cada 10 impactos de bala, cura 1 de vida",
			"apply": Callable(UpgradeTree, "_apply_sur_t2_lifesteal"),
			"branch": "sur", "kind": "", "tier": 2, "requires": ["sur_t1_regen"], "excludes": ["sur_t2_thick"]},
		{"id": "sur_t3_secondwind", "name": "Último Aliento", "desc": "una vez por corrida, sobrevivís con 1 de vida",
			"apply": Callable(UpgradeTree, "_apply_sur_t3_secondwind"),
			"branch": "sur", "kind": "", "tier": 3, "requires": ["sur_t2_thick"], "excludes": ["sur_t3_adrenaline"]},
		{"id": "sur_t3_adrenaline", "name": "Adrenalina", "desc": "bajo 30% de vida: velocidad +25%, cadencia x0.8; vida máx -1",
			"apply": Callable(UpgradeTree, "_apply_sur_t3_adrenaline"),
			"branch": "sur", "kind": "", "tier": 3, "requires": ["sur_t2_lifesteal"], "excludes": ["sur_t3_secondwind"]},
	]

## Devuelve los nodos disponibles para `taken` (progreso combinado: mov/sur
## persistente + mejoras del arma actual, ver Player.all_taken_upgrades()):
## no tomados, con todos sus requires cumplidos, ninguno de sus excludes
## tomado (exclusión solo dentro de la misma rama), y si tienen `kind`
## ("melee"/"ranged") que coincida con el arma equipada — los nodos con
## kind "" (mov/sur) siempre están disponibles sin importar el arma.
static func get_available(taken: Array, weapon_kind: String = "") -> Array:
	var result := []
	for upgrade in get_all():
		var kind: String = upgrade.get("kind", "")
		if kind != "" and kind != weapon_kind:
			continue
		if taken.has(upgrade["id"]):
			continue
		var requires_ok := true
		for req in upgrade["requires"]:
			if not taken.has(req):
				requires_ok = false
				break
		if not requires_ok:
			continue
		var excluded := false
		for exc in upgrade["excludes"]:
			if taken.has(exc):
				excluded = true
				break
		if excluded:
			continue
		result.append(upgrade)
	return result

## Elige hasta `count` mejoras disponibles, priorizando diversidad de ramas:
## agrupa por rama y va tomando de a una por rama en rondas, para no mostrar
## 3 mejoras de la misma rama cuando hay opciones de otras ramas disponibles.
static func roll(taken: Array, count: int, weapon_kind: String = "") -> Array:
	var available := get_available(taken, weapon_kind)
	available.shuffle()

	var by_branch := {}
	for upgrade in available:
		var branch: String = upgrade["branch"]
		if not by_branch.has(branch):
			by_branch[branch] = []
		by_branch[branch].append(upgrade)

	var branch_keys := by_branch.keys()
	branch_keys.shuffle()

	var result := []
	var exhausted := false
	while result.size() < count and not exhausted:
		exhausted = true
		for branch in branch_keys:
			if result.size() >= count:
				break
			var bucket: Array = by_branch[branch]
			if bucket.is_empty():
				continue
			exhausted = false
			result.append(bucket.pop_back())

	return result
