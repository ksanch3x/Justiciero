# Prototipo: Combate Top-Down / Shooter

Prototipo de Godot 4 aislado para probar el "minuto de diversión" del combate a
distancia (referencia GDD sección 2.3 y sección 0). No usa assets externos: todo
son formas de color (`Polygon2D`) generadas a mano, para poder iterar rápido sin
depender de arte.

## Qué prueba

- Movimiento en 8 direcciones con `CharacterBody2D` (WASD).
- Apuntado libre con el mouse (`look_at`) y disparo (click izquierdo) con cooldown
  (`fire_rate`), sin munición infinita real todavía — próximo paso natural.
- Enemigos (`Enemy.gd`) que persiguen al jugador y hacen daño de contacto con
  cooldown propio.
- Proyectiles (`Bullet.gd`) como `Area2D` con capas de colisión separadas
  (jugador=1, enemigo=2, balas=4) para que las balas del jugador no lo golpeen
  a él mismo.
- Spawner simple (`Main.gd`) que genera enemigos en puntos fijos cada
  `spawn_interval` segundos hasta `max_enemies`.
- HUD mínimo: vida y contador de enemigos eliminados. `R` reinicia la escena.

## Cómo correrlo

Abrir esta carpeta (`prototypes/combat-topdown/`) como proyecto en Godot 4.x y
correr la escena `Main.tscn` (ya configurada como escena principal).

## Controles

- Mover: WASD (o joystick izquierdo)
- Apuntar: mouse
- Disparar: click izquierdo (o gatillo del mando)
- Reiniciar tras morir: R

## Qué se aprendió

_(completar después de jugarlo — sensación del ritmo de disparo, si el
movimiento en 8 direcciones se siente bien, si el daño de contacto es
demasiado punitivo, etc.)_

## Próximos pasos posibles

- Agregar dash/esquiva con cooldown (ver GDD 2.3).
- Munición finita para el disparo a distancia.
- Diferenciar melee (silencioso, corto alcance) vs. ranged (ruidoso), aunque
  el sistema de ruido/alerta no aplica todavía a este prototipo aislado.
- Migrar lo aprendido (no el proyecto) a `games/justiciero/` cuando esté validado.
