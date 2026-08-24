extends RefCounted
class_name UpgradePool

static func _apply_speed(p: CharacterBody2D) -> void:
	p.speed *= 1.2

static func _apply_fire_rate(p: CharacterBody2D) -> void:
	p.fire_rate = max(0.05, p.fire_rate * 0.8)

static func _apply_max_health(p: CharacterBody2D) -> void:
	p.max_health += 1
	p.health += 1
	p.health_changed.emit(p.health, p.max_health)

static func _apply_bullet_count(p: CharacterBody2D) -> void:
	p.bullet_count += 1

static func _apply_bullet_damage(p: CharacterBody2D) -> void:
	p.bullet_damage += 1

static func get_all() -> Array:
	return [
		{"name": "Velocidad +20%", "apply": Callable(UpgradePool, "_apply_speed")},
		{"name": "Cadencia de disparo +25%", "apply": Callable(UpgradePool, "_apply_fire_rate")},
		{"name": "+1 Vida máxima", "apply": Callable(UpgradePool, "_apply_max_health")},
		{"name": "+1 Proyectil", "apply": Callable(UpgradePool, "_apply_bullet_count")},
		{"name": "+1 Daño de bala", "apply": Callable(UpgradePool, "_apply_bullet_damage")},
	]

static func roll(count: int) -> Array:
	var pool := get_all()
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))
