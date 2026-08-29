extends RefCounted
class_name UpgradeTree

## Árbol de mejoras de UNA corrida (no persistente: se resetea junto con toda
## la escena cuando Main llama a get_tree().reload_current_scene()).
## Reemplaza al viejo UpgradePool (selección plana al azar) por nodos con
## tier/requires/excludes dentro de 3 ramas: ofensiva (off), movilidad (mov)
## y supervivencia (sur). La exclusión es SOLO dentro de cada rama, no hay
## exclusión cruzada entre ramas (decisión confirmada por el usuario).

# ---------------------------------------------------------------------------
# Rama OFENSIVA
# ---------------------------------------------------------------------------

static func _apply_off_t1_rate(p: CharacterBody2D) -> void:
	p.fire_rate = max(0.05, p.fire_rate * 0.85)

static func _apply_off_t1_dmg(p: CharacterBody2D) -> void:
	p.bullet_damage += 1

static func _apply_off_t2_burst(p: CharacterBody2D) -> void:
	p.bullet_count += 1
	p.bullet_damage = max(1, p.bullet_damage - 1)

static func _apply_off_t2_heavy(p: CharacterBody2D) -> void:
	p.bullet_damage += 2
	p.fire_rate *= 1.15

static func _apply_off_t3_glasscannon(p: CharacterBody2D) -> void:
	p.bullet_damage += 3
	p.max_health = max(1, p.max_health - 2)
	if p.health > p.max_health:
		p.health = p.max_health
	p.health_changed.emit(p.health, p.max_health)

static func _apply_off_t3_swarm(p: CharacterBody2D) -> void:
	p.bullet_count += 2
	p.bullet_spread_deg *= 1.5

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
			"branch": "off", "tier": 1, "requires": [], "excludes": []},
		{"id": "off_t1_dmg", "name": "Daño +", "desc": "daño de bala +1",
			"apply": Callable(UpgradeTree, "_apply_off_t1_dmg"),
			"branch": "off", "tier": 1, "requires": [], "excludes": []},
		{"id": "off_t2_burst", "name": "Ráfaga", "desc": "+1 proyectil, daño de bala -1 (mín 1)",
			"apply": Callable(UpgradeTree, "_apply_off_t2_burst"),
			"branch": "off", "tier": 2, "requires": ["off_t1_rate"], "excludes": ["off_t2_heavy"]},
		{"id": "off_t2_heavy", "name": "Bala Pesada", "desc": "daño de bala +2, cadencia x1.15 (más lenta)",
			"apply": Callable(UpgradeTree, "_apply_off_t2_heavy"),
			"branch": "off", "tier": 2, "requires": ["off_t1_dmg"], "excludes": ["off_t2_burst"]},
		{"id": "off_t3_glasscannon", "name": "Cañón de Cristal", "desc": "daño de bala +3, vida máx -2",
			"apply": Callable(UpgradeTree, "_apply_off_t3_glasscannon"),
			"branch": "off", "tier": 3, "requires": ["off_t2_heavy"], "excludes": ["off_t3_swarm"]},
		{"id": "off_t3_swarm", "name": "Enjambre", "desc": "+2 proyectiles, +50% dispersión de disparo",
			"apply": Callable(UpgradeTree, "_apply_off_t3_swarm"),
			"branch": "off", "tier": 3, "requires": ["off_t2_burst"], "excludes": ["off_t3_glasscannon"]},

		{"id": "mov_t1_cd", "name": "Reflejos", "desc": "cooldown de dash x0.75",
			"apply": Callable(UpgradeTree, "_apply_mov_t1_cd"),
			"branch": "mov", "tier": 1, "requires": [], "excludes": []},
		{"id": "mov_t1_dur", "name": "Impulso", "desc": "duración de dash x1.3",
			"apply": Callable(UpgradeTree, "_apply_mov_t1_dur"),
			"branch": "mov", "tier": 1, "requires": [], "excludes": []},
		{"id": "mov_t2_chain", "name": "Dash Encadenado", "desc": "2do dash inmediato; el siguiente cooldown se duplica",
			"apply": Callable(UpgradeTree, "_apply_mov_t2_chain"),
			"branch": "mov", "tier": 2, "requires": ["mov_t1_cd"], "excludes": ["mov_t2_armored"]},
		{"id": "mov_t2_armored", "name": "Esquiva Blindada", "desc": "empuja enemigos cercanos al terminar el dash, duración x0.8",
			"apply": Callable(UpgradeTree, "_apply_mov_t2_armored"),
			"branch": "mov", "tier": 2, "requires": ["mov_t1_dur"], "excludes": ["mov_t2_chain"]},
		{"id": "mov_t3_phantom", "name": "Fantasma", "desc": "podés disparar durante el dash, velocidad de dash x0.85",
			"apply": Callable(UpgradeTree, "_apply_mov_t3_phantom"),
			"branch": "mov", "tier": 3, "requires": ["mov_t2_chain"], "excludes": ["mov_t3_juggernaut"]},
		{"id": "mov_t3_juggernaut", "name": "Titán", "desc": "velocidad de dash x1.4 y daña al tocar enemigos; cadencia x1.1 permanente",
			"apply": Callable(UpgradeTree, "_apply_mov_t3_juggernaut"),
			"branch": "mov", "tier": 3, "requires": ["mov_t2_armored"], "excludes": ["mov_t3_phantom"]},

		{"id": "sur_t1_hp", "name": "Vitalidad", "desc": "vida máx +1, vida actual +1",
			"apply": Callable(UpgradeTree, "_apply_sur_t1_hp"),
			"branch": "sur", "tier": 1, "requires": [], "excludes": []},
		{"id": "sur_t1_regen", "name": "Recuperación", "desc": "cura 1 de vida al superar cada oleada",
			"apply": Callable(UpgradeTree, "_apply_sur_t1_regen"),
			"branch": "sur", "tier": 1, "requires": [], "excludes": []},
		{"id": "sur_t2_thick", "name": "Piel Gruesa", "desc": "vida máx +3, velocidad x0.9",
			"apply": Callable(UpgradeTree, "_apply_sur_t2_thick"),
			"branch": "sur", "tier": 2, "requires": ["sur_t1_hp"], "excludes": ["sur_t2_lifesteal"]},
		{"id": "sur_t2_lifesteal", "name": "Robo de Vida", "desc": "cada 10 impactos de bala, cura 1 de vida",
			"apply": Callable(UpgradeTree, "_apply_sur_t2_lifesteal"),
			"branch": "sur", "tier": 2, "requires": ["sur_t1_regen"], "excludes": ["sur_t2_thick"]},
		{"id": "sur_t3_secondwind", "name": "Último Aliento", "desc": "una vez por corrida, sobrevivís con 1 de vida",
			"apply": Callable(UpgradeTree, "_apply_sur_t3_secondwind"),
			"branch": "sur", "tier": 3, "requires": ["sur_t2_thick"], "excludes": ["sur_t3_adrenaline"]},
		{"id": "sur_t3_adrenaline", "name": "Adrenalina", "desc": "bajo 30% de vida: velocidad +25%, cadencia x0.8; vida máx -1",
			"apply": Callable(UpgradeTree, "_apply_sur_t3_adrenaline"),
			"branch": "sur", "tier": 3, "requires": ["sur_t2_lifesteal"], "excludes": ["sur_t3_secondwind"]},
	]

## Devuelve los nodos disponibles para `taken`: no tomados, con todos sus
## requires cumplidos y ninguno de sus excludes tomado (exclusión solo
## dentro de la misma rama, ya que excludes solo lista ids de la misma rama).
static func get_available(taken: Array) -> Array:
	var result := []
	for upgrade in get_all():
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
static func roll(taken: Array, count: int) -> Array:
	var available := get_available(taken)
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
