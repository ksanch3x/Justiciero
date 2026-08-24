extends RefCounted
class_name UpgradePool

static func get_all() -> Array:
	return [
		{
			"name": "Velocidad +20%",
			"apply": func(p: CharacterBody2D) -> void:
				p.speed *= 1.2
		},
		{
			"name": "Cadencia de disparo +25%",
			"apply": func(p: CharacterBody2D) -> void:
				p.fire_rate = max(0.05, p.fire_rate * 0.8)
		},
		{
			"name": "+1 Vida máxima",
			"apply": func(p: CharacterBody2D) -> void:
				p.max_health += 1
				p.health += 1
				p.health_changed.emit(p.health, p.max_health)
		},
		{
			"name": "+1 Proyectil",
			"apply": func(p: CharacterBody2D) -> void:
				p.bullet_count += 1
		},
		{
			"name": "+1 Daño de bala",
			"apply": func(p: CharacterBody2D) -> void:
				p.bullet_damage += 1
		},
	]

static func roll(count: int) -> Array:
	var pool := get_all()
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))
