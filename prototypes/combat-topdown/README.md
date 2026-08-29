# Prototipo: Combate Top-Down / Shooter (Roguelite de oleadas)

Prototipo de Godot 4 aislado para probar el "minuto de diversión" del combate a
distancia + progresión roguelite dentro de una corrida (referencia GDD sección
2.3, 2.4 y sección 0). No usa assets externos por defecto: formas de color
(`Polygon2D`) generadas a mano, para poder iterar rápido sin depender de arte
(el pack de Kenney ya está disponible en `assets/desert-shooter-pack/` para
integrarlo después).

## Qué prueba

- Movimiento en 8 direcciones con `CharacterBody2D` (WASD).
- Apuntado libre con el mouse (`look_at`) y disparo (click izquierdo) con cooldown
  (`fire_rate`).
- Enemigos (`Enemy.gd`) que persiguen al jugador y hacen daño de contacto con
  cooldown propio.
- Proyectiles (`Bullet.gd`) como `Area2D` con capas de colisión separadas
  (jugador=1, enemigo=2, balas=4) para que las balas del jugador no lo golpeen
  a él mismo.
- **Oleadas (`Main.gd`)**: se generan enemigos en tandas; cuando se elimina toda
  la oleada aparece una pantalla de selección de mejora (3 opciones al azar).
  Al elegir, arranca la siguiente oleada, con más enemigos y más vida cada vez.
- **Mejoras (`UpgradeTree.gd`)**: árbol de mejoras de UNA corrida (se resetea
  con `reload_current_scene()`, no persiste) con 3 ramas — ofensiva, movilidad
  y supervivencia —, cada una con tiers, requisitos y exclusiones dentro de la
  misma rama. No confundir con el árbol permanente del GDD grande (sección 2.4).
- HUD mínimo: oleada actual, vida y enemigos restantes. `R` reinicia la escena.

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
