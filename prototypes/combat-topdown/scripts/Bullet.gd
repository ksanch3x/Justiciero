extends Area2D

@export var speed: float = 600.0
@export var damage: int = 1
@export var lifetime: float = 2.0
## Capa física a la que este proyectil hace daño (collision_mask). Por
## defecto 2 = enemigos (bala del jugador). El Spitter setea esto a 1
## (jugador) ANTES de add_child, mismo patrón que direction/shooter/damage.
@export var target_mask: int = 2

var direction: Vector2 = Vector2.RIGHT
var shooter: Node = null

func _ready() -> void:
	rotation = direction.angle()
	collision_mask = target_mask
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_expire)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body == shooter:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
		if shooter != null and shooter.has_method("_on_bullet_hit"):
			shooter._on_bullet_hit()
	queue_free()

func _expire() -> void:
	if is_instance_valid(self):
		queue_free()
