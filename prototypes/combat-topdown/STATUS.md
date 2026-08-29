# Estado del prototipo — combat-topdown

Documento de referencia rápida para retomar trabajo sin tener que releer todo
el código. Actualizar esta tabla/lista cada vez que se agregue o cambie un
sistema importante. Para el "por qué" de decisiones de diseño puntuales, ver
también los mensajes de commit (son descriptivos) y los comentarios inline en
el código, que documentan simplificaciones deliberadas.

## Qué es esto

Roguelite top-down shooter de oleadas, Godot 4.3 (GL Compatibility). Sirve
para validar mecánicas de combate antes de construir el juego grande
(`games/justiciero/`, ver su `GDD.md`) — **no** hay que mantener fidelidad al
GDD grande acá; este prototipo tiene su propio diseño, más simple y más
arcade. Progresión **no persistente**: todo se resetea con `R`
(`get_tree().reload_current_scene()`).

Escena principal: `scenes/Main.tscn`. Assets: `assets/desert-shooter-pack/`
(Kenney, CC0) — ver sección "Mapa de assets" abajo, ya se investigó qué hay
en cada subcarpeta para no tener que re-explorar el pack.

## Estructura de archivos

```
scripts/
  Player.gd       — jugador: movimiento, dash, armas (melee/SMG/escopeta), stats de mejoras
  Enemy.gd        — enemigo base "Grunt": persigue + daño de contacto
  Runner.gd       — extends Enemy.gd, solo cambia stats (rápido/débil)
  Spitter.gd      — enemigo a distancia, script propio (no hereda de Enemy.gd)
  Bullet.gd       — proyectil (Area2D), reusado por jugador y Spitter
  Main.gd         — spawner de oleadas, HUD, selección de tipo de enemigo por oleada
  UpgradeTree.gd  — árbol de mejoras de la corrida (18 nodos, 3 ramas)
  UpgradeUI.gd    — panel de selección de mejora entre oleadas
scenes/
  Player.tscn, Enemy.tscn, Runner.tscn, Spitter.tscn, Bullet.tscn, Main.tscn
```

## Sistemas implementados

### Movimiento y dash
- 8 direcciones, `CharacterBody2D` + `move_and_slide()`.
- Cuerpo **no rota** (el arte tiene perspectiva fija, no top-down puro) — solo
  `flip_h` según hacia dónde mira/dispara. El arma (`WeaponPivot`) sí rota,
  apunta al mouse.
- Dash: tecla **Espacio** / botón A del mando (acción `dash` en
  `project.godot`). Base: `dash_speed=600`, `dash_duration=0.15s`,
  `dash_cooldown=0.7s`, invulnerable durante el dash. No dispara mientras
  dashea (salvo mejora `mov_t3_phantom`).

### Armas (jugador)
Arranca con **melee** (cuchillo, sprite `Weapons/Tiles/tile_0008.png`), sin
munición. Se consigue arma a distancia vía árbol de mejoras (no hay pickups
en el mapa):
- **Melee**: `melee_damage=2`, `melee_range=36px`, cooldown `0.35s`,
  **empuja al enemigo golpeado `melee_knockback=46px`** (agregado porque sin
  esto el jugador quedaba pegado intercambiando daño con el enemigo — ver
  commit `9cefff3`).
- **SMG** (nodo `off_t1_smg`, sin requisitos): cadencia/daño reusan
  `fire_rate`/`bullet_damage`/`bullet_count` (las mismas variables que tocan
  las mejoras de daño/cadencia — por eso mejoras tomadas en melee ya vienen
  aplicadas al conseguir la SMG). Cargador `smg_mag_size=20`, recarga
  automática al vaciarse, `smg_reload_time=1.2s`.
- **Escopeta** (nodo `off_t2_shotgun`, requiere `off_t1_smg`): cadencia propia
  `shotgun_fire_rate=0.9s`, cargador `shotgun_mag_size=6`,
  `shotgun_reload_time=1.8s`, dispara en abanico (+5 proyectiles,
  `shotgun_spread_deg=28°`, +1 daño).
- HUD muestra "Munición: X/Y" o "recargando..." cuando hay arma a distancia
  equipada (`Player.has_ranged_weapon()`).

### Árbol de mejoras (`UpgradeTree.gd`)
Reemplaza un pool plano por 18 nodos en 3 ramas, con `requires`/`excludes`
(exclusión **solo dentro de la misma rama**, no hay exclusión cruzada — así
lo pidió el usuario). Selección entre oleadas: hasta 3 nodos disponibles
(prerrequisitos cumplidos, no excluidos), priorizando diversidad de ramas.
Estado de progreso en `Player.taken_upgrades: Array[String]`.

- **Ofensiva (`off`)**: cadencia/daño (t1) → Ráfaga vs Bala Pesada (t2,
  exclusión mutua) → Cañón de Cristal vs Enjambre (t3, exclusión mutua,
  ambos con trade-off real). Más los nodos de arma: `off_t1_smg` (t1, sin
  requisitos) → `off_t2_shotgun` (t2, requiere SMG).
- **Movilidad (`mov`)**: potencia el dash. Reflejos/Impulso (t1) → Dash
  Encadenado vs Esquiva Blindada (t2, exclusión) → Fantasma vs Titán (t3,
  exclusión, ambos con trade-off).
- **Supervivencia (`sur`)**: Vitalidad/Recuperación (t1) → Piel Gruesa vs
  Robo de Vida (t2, exclusión) → Último Aliento vs Adrenalina (t3, exclusión,
  ambos con trade-off).

La mitad de los nodos de tier 2-3 tienen costo explícito (no todo es buff
puro) — decisión deliberada para mitigar el hallazgo de la auditoría de que
el juego se volvía más fácil con las oleadas.

### Enemigos
3 tipos, todos con sprite real del pack (no tintes, hay 4 criaturas
distintas en `Enemies/Tiles/`, una por fila del grid 4x4):
- **Grunt** (`Enemy.gd`/`Enemy.tscn`, fila 2 = naranja/amarilla): persigue,
  daño de contacto. Único tipo hasta oleada 2.
- **Runner** (`Runner.gd extends Enemy.gd`, fila 1 = marrón orejas moradas):
  más rápido, menos vida/daño. Desde oleada 2.
- **Spitter** (`Spitter.gd`, script propio, fila 0 = turquesa con púas):
  se acerca lento y dispara al estar en rango (`shoot_range=220px`,
  `fire_rate=1.4s`), **no hace kiting** (no retrocede). Vida baja (2), sin
  daño de contacto. Desde oleada 3. Sus balas usan
  `collision_layer=16` ("enemy_bullet", nueva capa) vía `Bullet.target_mask`
  para no chocar con las balas del jugador ni con otros enemigos.
- Fila 3 del pack (azul grande con dientes) **no se usa todavía** — candidata
  a un 4to tipo "tanque" más adelante.

**Escalado por oleada** (`Main.gd`): vida del Grunt +15%/oleada (ya existía),
+ velocidad +3%/oleada compuesto, + contact_damage +1 cada 4 oleadas (nuevo,
agregado porque la auditoría encontró que el juego se volvía más fácil con
el tiempo). Runner/Spitter no se re-escalan, tienen su propia curva por
diseño. Pesos de aparición por tipo suben gradualmente con la oleada (ver
comentario en `Main._pick_enemy_scene()`).

### Escenario
- Fondo: `assets/generated/sand_floor_2000.png` — **generado con Python/PIL**
  (no está en Godot vía `texture_repeat`, causaba costuras visibles porque el
  primer tile elegido no era plano). Es una textura de 2000x2000 pre-tileada
  mezclando al azar 7 variantes de tile de arena (planas + moteadas) del
  pack, para verse natural sin bandas repetidas. Si hace falta regenerarla,
  el script de generación está en el historial de commits (no versionado
  como script aparte, se ejecutó inline).
- Props sólidos (`Main.tscn`, nodo `Props`): 2 cactus, 2 rocas/huesos, 1
  formación rocosa — `StaticBody2D`, `collision_layer=8`. Bloquean a
  jugador/enemigos (ambos tienen `collision_mask=8`).
- Iluminación: `CanvasModulate` oscurece la escena (`Color(0.16,0.16,0.22)`),
  + `PointLight2D` en jugador (ámbar), balas (blanco-amarillento chico) y
  enemigos (rojo tenue). Textura de luz generada (`assets/generated/light_glow.tres`,
  `GradientTexture2D` radial), no es un asset de imagen.

## Capas de colisión (importante para no romper nada al agregar cosas)

| Capa (bit) | Quién | Mask |
|---|---|---|
| 1 | Player | 8 (props) |
| 2 | Enemy/Runner/Spitter | 8 (props) |
| 4 | Bullet del jugador | 2 (enemigos) |
| 8 | Props | — (estático) |
| 16 | Bullet enemiga (Spitter) | 1 (jugador), vía `Bullet.target_mask` |

Jugador y enemigos **no colisionan físicamente entre sí** (por eso el melee
necesitó knockback explícito — pueden superponerse del todo).

## Cuidados técnicos que ya causaron bugs reales (no repetir)

1. **GDScript**: lambdas multilínea dentro de literales de array/diccionario
   no parsean. Usar `Callable(Clase, "_metodo_estatico")` (patrón ya
   establecido en `UpgradeTree.gd`).
2. **`.tscn` `load_steps`**: debe ser exactamente
   `ext_resource + sub_resource + 1`. Se edita todo a mano como texto (no hay
   Godot instalable en este entorno) — revisar dos veces al tocar un `.tscn`.
3. **Orden en instanciación de nodos dinámicos** (balas, enemigos): setear
   propiedades que `_ready()` vaya a leer (`direction`, `shooter`, `damage`,
   `max_health`, etc.) **antes** de `add_child()`; `global_position` **después**
   (necesita estar en el árbol para resolver transform de padre). Godot llama
   `_ready()` de forma síncrona dentro de `add_child()`.
4. **`AnimatedSprite2D`**: no confiar en la propiedad serializada
   `playing = true` del `.tscn` para que arranque sola — llamar
   `.play("nombre")` explícito en `_ready()` del script (causó el bug de
   "animación estática" en enemigos).
5. **Velocity de `CharacterBody2D` en otro script**: `Enemy.gd` recalcula
   `velocity` desde cero cada frame antes de `move_and_slide()`, así que un
   empuje/knockback externo debe aplicarse como offset directo de
   `global_position`, no seteando `velocity` (se perdería en el siguiente
   tick del enemigo).
6. **Sprites del pack no siempre son lo que parecen**: varios "tiles de
   piso" en `Tiles/` son en realidad piezas de borde/transición, no relleno
   plano — verificar con Python/PIL (`set(im.getdata())`) antes de asumir que
   un tile es uniforme.

## Mapa de assets (`assets/desert-shooter-pack/`)

- `Players/Tiles/`: 16 tiles 24x24 (grid 4x4). Cada fila es una criatura
  distinta con su propio ciclo de 4 frames (no son 4 direcciones de la misma
  criatura). Jugador usa fila 2 (`tile_0008`-`tile_0010`, descartando
  `tile_0011` que es una pose de golpe/muerte, no de caminata).
- `Enemies/Tiles/`: mismo formato, 4 criaturas distintas (ver sección
  Enemigos arriba para el mapeo fila→tipo).
- `Weapons/Tiles/`: grid 10x4 de 24x24. Filas 0-1 = íconos de armas (pistolas,
  dagas/hachas en las últimas columnas). Filas 2-3 = íconos de UI (cruceta,
  mira), no son armas pese al nombre de la carpeta.
- `Tiles/`: 234 tiles 16x16, set de bloques/terreno variado (no es "arena"
  homogénea) — los índices usados para el piso están documentados en la
  sección Escenario arriba.
- `UI/`: 198 tiles 16x16, no usado todavía en este prototipo.

## Hallazgos de auditoría pendientes / conocidos (no bloqueantes)

- Enemigos no colisionan entre sí → se pueden apilar visualmente con oleadas
  grandes (mitigado parcialmente por el knockback del dash/melee, no
  resuelto del todo).
- El pool de mejoras viejo ya no existe (reemplazado por el árbol), pero el
  árbol nuevo todavía no fue jugado/balanceado a fondo — falta feedback real
  de partidas largas.
- Falta "jugo" (juice): sin sonido, sin screen shake, sin flash de daño al
  jugador. Identificado como próxima prioridad de sensación de juego antes
  que más contenido.
