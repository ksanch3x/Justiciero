# Prototipo: Combate Top-Down / Shooter (Roguelite de oleadas)

Prototipo de Godot 4.3 aislado para probar el "minuto de diversión" del
combate + progresión roguelite dentro de una corrida. Es su propio diseño,
más simple y arcade que `games/justiciero/GDD.md` — no hace falta mantener
fidelidad al GDD grande acá.

**Para el estado completo y detallado de qué está implementado (sistemas,
valores numéricos, capas de colisión, mapa de assets, cuidados técnicos que
ya causaron bugs), ver [`STATUS.md`](STATUS.md).** Este README es solo la
puerta de entrada rápida.

## Qué tiene ahora mismo (resumen)

- Movimiento 8 direcciones + dash con cooldown e invulnerabilidad.
- Arma inicial melee (cuchillo), progresa a SMG y escopeta (con munición y
  recarga) vía el árbol de mejoras.
- Árbol de mejoras de la corrida (`UpgradeTree.gd`): 18 nodos en 3 ramas
  (ofensiva, movilidad, supervivencia) con prerrequisitos y exclusión
  mutua dentro de cada rama.
- 3 tipos de enemigo (Grunt, Runner rápido, Spitter a distancia) con
  escalado progresivo por oleada.
- Escenario con piso de arena, props sólidos e iluminación (oscurecimiento
  ambiental + luces puntuales en jugador/balas/enemigos).

## Cómo correrlo

Abrir esta carpeta (`prototypes/combat-topdown/`) como proyecto en Godot
4.x y correr la escena `Main.tscn` (ya configurada como escena principal).

## Controles

- Mover: WASD (o joystick izquierdo)
- Apuntar: mouse
- Disparar / atacar: click izquierdo (o gatillo del mando)
- Dash: Espacio (o botón A del mando)
- Reiniciar tras morir: R

## Qué se aprendió

_(completar jugándolo — sensación del ritmo de oleadas, si el árbol de
mejoras genera decisiones interesantes, si el melee se siente bien con el
knockback nuevo, etc.)_
