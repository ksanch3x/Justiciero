extends Node

## Autoload de "jugo" visual sin audio (el audio queda pausado a pedido
## explícito del usuario, ver STATUS.md). Helpers reusados por
## Player.gd/Enemy.gd/Spitter.gd:
## - flash_damage(sprite): parpadeo rojo-blanco al recibir daño.
## - play_death(node, sprite): "pop" de escala + fade antes de queue_free().
## - telegraph_attack(sprite, duration): pulso amarillo antes de un golpe de
##   contacto, para que el jugador tenga un aviso visual y pueda esquivar
##   (antes el daño de contacto era instantáneo al tocar, sin ningún aviso).

## Flashea el modulate del sprite a blanco-rojizo y vuelve al color original.
func flash_damage(sprite: CanvasItem) -> void:
	if not is_instance_valid(sprite):
		return
	var original: Color = sprite.modulate
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate", Color(1.6, 0.3, 0.3), 0.05)
	tween.tween_property(sprite, "modulate", original, 0.15)

## Feedback de muerte: el sprite crece x1.4 y se desvanece antes de que el
## nodo se libere. `node` es el nodo a liberar (normalmente el mismo
## CharacterBody2D dueño de `sprite`); se separan porque la escala/fade se
## aplica al sprite visual, no al body físico.
func play_death(node: Node, sprite: CanvasItem) -> void:
	if not is_instance_valid(node):
		return
	node.set_physics_process(false)
	if not is_instance_valid(sprite):
		node.queue_free()
		return
	var tween := sprite.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", sprite.scale * 1.4, 0.18)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(node.queue_free)

## Pulsa el sprite a un amarillo brillante durante `duration` (windup del
## golpe) y vuelve al color original al terminar. Es puramente visual — el
## timing real del golpe lo maneja el script del enemigo, esto solo avisa.
func telegraph_attack(sprite: CanvasItem, duration: float) -> void:
	if not is_instance_valid(sprite):
		return
	var original: Color = sprite.modulate
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 0.4), duration * 0.5)
	tween.tween_property(sprite, "modulate", original, duration * 0.5)
