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
  UpgradeTree.gd  — árbol de mejoras de la corrida (25 nodos, 3 ramas, filtrado por arma)
  UpgradeUI.gd    — panel de selección (elección inicial / mejoras / hito de arma)
  WeaponData.gd   — roster de armas (5 armas x 2 niveles), stats y sprites
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

### Armas (jugador) — `scripts/WeaponData.gd`
Sistema por niveles: **5 armas × 2 niveles** (naranja = nivel 1, turquesa =
nivel 2 en `Weapons/Tiles/` — son las mismas 10 siluetas en 2 paletas, ver
"Mapa de assets"). `Player.gd` ya NO tiene `enum Weapon` ni `@export` por
arma — todo vive en `WeaponData.gd` (diccionario estático estilo
`UpgradeTree.gd`) y en el estado vivo del jugador:

```
weapon_id: String        # "" hasta elegir en la pantalla inicial
weapon_level: int
owned_weapons: Dictionary       # id -> nivel máximo alcanzado
wstats: Dictionary              # stats VIVOS del arma actual (mutados por mejoras)
weapon_upgrades: Array[String]  # mejoras del arma actual, se vacían al cambiar de arma
```

`equip_weapon(id, level)` es el único camino (arma nueva o subir de nivel):
recarga `wstats` desde `WeaponData.base_stats()` (que devuelve `.duplicate()`,
nunca la referencia estática) y **vacía `weapon_upgrades`** — cambiar de arma
o subir de nivel reinicia lo invertido en ella, a propósito (decisión de
diseño: la elección del hito cuesta algo).

- **Cuchillo** / **Hacha** (melee, sin munición): cuchillo rápido y seguro
  (`damage 2→3`, `rate 0.30→0.26s`, `range 56→62px`, `knockback 46→52`),
  hacha lenta pero pesada (`damage 5→7`, `rate 0.62→0.55s`, `range 72→80px`,
  `knockback 78→90`). El rango del melee dejó margen real respecto al
  `contact_range` del enemigo (24px) — antes (36px) casi no había margen.
- **Pistola** → **SMG** → **Escopeta** (a distancia, con cargador y recarga
  automática al vaciarse): la pistola queda intermedia (`mag 10→12`,
  `rate 0.34→0.30s`), la SMG es la de cadencia altísima y cargador grande
  (`mag 20→26`, `rate 0.14→0.12s`, poco daño por bala), la escopeta dispara
  en abanico (`count 6→7`, `spread 26°`, cargador chico `6→8`).
- El melee se muestra hoy **sin recorte** (primera pasada conservadora: el
  arte está dibujado vertical y `WeaponPivot` rota apuntando al mouse +
  `flip_v` — recortar el sprite ahí se vería raro sin retrabajar esa
  rotación, queda pendiente de afinar con el juego corriendo). Las armas a
  distancia sí usan `region_rect`/`scale` por nivel (calculados con
  `Image.getbbox()` real, no estimados).
- HUD muestra "Munición: X/Y" o "recargando..." cuando hay arma a distancia
  equipada (`Player.has_ranged_weapon()`).

**Flujo de progresión**: pantalla inicial (elegí cuchillo o hacha, con sprite
+ nombre) antes de la oleada 1 → cada oleada normal ofrece mejoras del arma
equipada → cada `MILESTONE_EVERY` oleadas (5) el panel ofrece en cambio
**subir de nivel** el arma actual o **conseguir un arma nueva** siguiendo la
progresión melee → pistola → SMG → escopeta (`WeaponData.milestone_choices()`).

### Árbol de mejoras (`UpgradeTree.gd`)
25 nodos en 3 ramas, con `requires`/`excludes` (exclusión **solo dentro de
la misma rama**) y ahora también `kind` (`""`/`"melee"`/`"ranged"`): los
nodos de `off` solo se ofrecen si coinciden con el tipo de arma equipada, así
la rama de armas y la de cadencia/daño ya no compiten por espacio ni se
ofrecen mejoras que no hacen nada visible (antes `off_t1_rate`/`off_t1_dmg`
aparecían aunque estuvieras con el cuchillo). Selección: hasta 3 nodos
disponibles, priorizando diversidad de ramas. Progreso combinado vía
`Player.all_taken_upgrades()` = `taken_upgrades` (mov/sur, persiste toda la
corrida) + `weapon_upgrades` (arma actual, se vacía al cambiar de arma).

- **Ofensiva (`off`)**, `kind: "ranged"`: Cadencia+/Daño+/Cargador Extendido
  (t1) → Ráfaga vs Bala Pesada (t2, exclusión) → Cañón de Cristal vs Enjambre
  (t3, exclusión, trade-off real). `kind: "melee"`: Filo Rápido/Filo Pesado
  (t1) → Alcance vs Brutalidad (t2, exclusión) → Torbellino vs Verdugo (t3,
  exclusión, trade-off). Las armas en sí (conseguir/subir de nivel) ya NO
  salen de acá — salen de los hitos cada 5 oleadas.
- **Movilidad (`mov`)**, `kind: ""` (siempre disponible): potencia el dash.
  Reflejos/Impulso (t1) → Dash Encadenado vs Esquiva Blindada (t2, exclusión)
  → Fantasma vs Titán (t3, exclusión, trade-off).
- **Supervivencia (`sur`)**, `kind: ""`: Vitalidad/Recuperación (t1) → Piel
  Gruesa vs Robo de Vida (t2, exclusión) → Último Aliento vs Adrenalina (t3,
  exclusión, trade-off).

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
- **Arena cerrada**: área interior jugable **900x640**, centrada en el
  origen (`x: [-450, 450]`, `y: [-320, 320]`). Antes era un área abierta de
  2000x2000 sin bordes; se achicó a pedido del usuario para que se sienta
  como un layout real (una sola sala cerrada, no salas múltiples conectadas
  — eso queda para más adelante).
- Fondo: `assets/generated/sand_floor_2000.png` — **generado con Python/PIL**
  (no está en Godot vía `texture_repeat`, causaba costuras visibles porque el
  primer tile elegido no era plano). Es una textura de 2000x2000 pre-tileada
  mezclando al azar 7 variantes de tile de arena (planas + moteadas) del
  pack, para verse natural sin bandas repetidas. El `Sprite2D` de fondo ahora
  acota su `region_rect` a `Rect2(0, 0, 900, 640)` en vez de mostrar la
  textura completa. Si hace falta regenerarla, el script de generación está
  en el historial de commits (no versionado como script aparte, se ejecutó
  inline).
- **Paredes** (`Main.tscn`, nodo `Walls`): 4 `StaticBody2D`
  (`North`/`South`/`East`/`West`), grosor 40px, ubicados justo afuera del
  área interior y extendidos en las esquinas para cerrar el borde sin
  huecos. Visual: `ColorRect` con `Color(0.278431, 0.196078, 0.294118)` —
  color RGB real (71, 50, 75) de `tile_0140.png`, confirmado con
  `Image.getdata()` (uno de los tiles 100% planos ya identificados abajo).
  Colisión: `RectangleShape2D`, `collision_layer=8` (misma capa que
  `Props`), así que Player/Enemy/Runner/Spitter ya chocan contra ellas sin
  tocar sus scripts (todos tienen `collision_mask=8`).
- `SpawnPoint1..5` (`Main.tscn`) reposicionados a `±380/±260` (antes
  `±400/±300`) para quedar cómodos dentro de la arena más chica, con margen
  real respecto a las paredes.
- `Camera2D` del jugador (`Player.tscn`) tiene límites
  (`limit_left/right/top/bottom = ∓490/∓360`) ajustados a la arena + el
  grosor de pared, para que nunca se vea el vacío fuera del área jugable.
- Props sólidos (`Main.tscn`, nodo `Props`): 2 cactus, 2 rocas/huesos, 1
  formación rocosa — `StaticBody2D`, `collision_layer=8`. Bloquean a
  jugador/enemigos (ambos tienen `collision_mask=8`). Posiciones sin cambios
  (ya caían dentro del nuevo límite, sin quedar pegadas a una pared).
- **Jugo visual sin audio** (`scripts/Fx.gd`, autoload): `flash_damage(sprite)`
  (tween de `modulate` rojo-blanco al recibir daño) y
  `play_death(node, sprite)` (tween de escala x1.4 + fade antes de
  `queue_free()`), usados en `take_damage()` de Player/Enemy/Spitter (Runner
  hereda de Enemy.gd sin overrides). Screen shake en `Player.gd`
  (`_camera`/`_start_shake()`/`_update_shake()`, offset aleatorio con
  decaimiento sobre `$Camera2D`): sutil al disparar/golpear, más notorio al
  recibir daño. **Sin sonido** — el usuario pausó el sistema de audio
  explícitamente ("los sonidos los cargamos después, los sintéticos son
  horribles"); no hay `Sfx.gd` ni generación de `.wav`.
- Iluminación: `CanvasModulate` oscurece la escena (`Color(0.16,0.16,0.22)`),
  + `PointLight2D` en jugador (ámbar), balas (blanco-amarillento chico) y
  enemigos (rojo tenue). Textura de luz generada (`assets/generated/light_glow.tres`,
  `GradientTexture2D` radial), no es un asset de imagen.

## Capas de colisión (importante para no romper nada al agregar cosas)

| Capa (bit) | Quién | Mask |
|---|---|---|
| 1 | Player | 8 (props) |
| 2 | Enemy/Runner/Spitter | 10 = 8+2 (props + otros enemigos) |
| 4 | Bullet del jugador | 2 (enemigos) |
| 8 | Props | — (estático) |
| 16 | Bullet enemiga (Spitter) | 1 (jugador), vía `Bullet.target_mask` |

Los enemigos **sí colisionan entre sí** (mask incluye su propia layer 2) —
antes no, y con oleadas grandes se apilaban exactamente en el mismo punto,
lo que hacía que golpear con melee se sintiera impreciso (en la práctica
pegabas a una masa superpuesta, no a enemigos distribuidos). Jugador y
enemigos siguen **sin colisionar físicamente entre sí** (por eso el melee
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
7. **Estado "todavía no elegido" (`weapon_id == ""`)**: entre que el jugador
   entra al árbol de escena y elige su arma en la pantalla inicial, `wstats`
   está vacío. Cualquier código que lea stats de arma (`_shoot()`,
   `_get_effective_fire_rate()`, el bloque de disparo en `_physics_process`)
   tiene que cortar explícitamente en ese estado — si no, un `.get()` con
   default en 0 puede hacer que `fire_cooldown` se recargue en 0 cada frame.
   Mismo patrón de precaución que el resto de esta lista: nunca asumir que
   un estado "todavía no inicializado" se comporta como el caso normal.
8. **`var x := <ternario o and/or>`**: el análisis estático de GDScript puede
   fallar en inferir el tipo cuando el lado derecho de `:=` es un operador
   ternario (`a if cond else b`) o una expresión booleana con `and`/`or`
   mezclada con llamadas a método (`Cannot infer the type of "x" variable`).
   Pasó más de una vez en este proyecto (`Main._update_hud`, luego
   `WeaponData.milestone_choices`, `Player._shoot`). Cuando el valor no sea
   un literal simple de un solo tipo, declarar el tipo explícito
   (`var x: bool = ...`) en vez de confiar en `:=`.

## Mapa de assets (`assets/desert-shooter-pack/`)

- `Players/Tiles/`: 16 tiles 24x24 (grid 4x4). Cada fila es una criatura
  distinta con su propio ciclo de 4 frames (no son 4 direcciones de la misma
  criatura). Jugador usa fila 2 (`tile_0008`-`tile_0010`, descartando
  `tile_0011` que es una pose de golpe/muerte, no de caminata).
- `Enemies/Tiles/`: mismo formato, 4 criaturas distintas (ver sección
  Enemigos arriba para el mapeo fila→tipo).
- `Weapons/Tiles/`: grid 10x4 de 24x24. Filas 0-1 (tiles 0-19) = **10 armas
  en 2 paletas** (naranja tiles 0-9 = nivel 1, turquesa tiles 10-19 = nivel
  2 de la misma arma — ver `WeaponData.gd`): pistola (1/11), SMG (2/12),
  escopeta (3/13), cuchillo (8/18), hacha (9/19); el resto (0,4-7) son otras
  siluetas de arma sin usar todavía. Filas 2-3 = íconos de UI (cruceta,
  mira), no son armas pese al nombre de la carpeta.
- `Tiles/`: 234 tiles 16x16, set de bloques/terreno variado (no es "arena"
  homogénea) — los índices usados para el piso están documentados en la
  sección Escenario arriba.
- `UI/`: 198 tiles 16x16, no usado todavía en este prototipo.

## Hallazgos de auditoría pendientes / conocidos (no bloqueantes)

- ~~Enemigos no colisionan entre sí~~ — corregido: `collision_mask` de
  Enemy/Runner/Spitter pasó a 10 (props + su propia layer), así se empujan
  entre sí en vez de apilarse. También se agregó telegraph visual (pulso
  amarillo, `Fx.telegraph_attack`, `attack_telegraph_time=0.25s` en
  `Enemy.gd`) antes de que el daño de contacto conecte — antes era
  instantáneo al tocar, sin aviso para esquivar.
- Jugado hasta oleada 7 en una corrida real (primer feedback de balance
  fuera de la auditoría) — el escalado se sintió duro ahí, sin precisar
  todavía qué componente exacto (cantidad de enemigos vs. escalado de
  daño/vida) fue el problema. Pendiente de otra pasada de balance con más
  feedback de partidas.
- El pool de mejoras viejo ya no existe (reemplazado por el árbol), pero el
  árbol nuevo todavía no fue jugado/balanceado a fondo — falta feedback real
  de partidas largas.
- **Backlog explícito del usuario** (no implementar todavía, "vamos paso a
  paso"): diseño de niveles reales (más allá de la arena única) y jefes.
- Audio pendiente **a propósito**: hay flash de daño, muerte con feedback
  (escala+fade) y screen shake (`scripts/Fx.gd` + `Player.gd`), pero sin
  sonido — el usuario pidió posponer `Sfx.gd`/síntesis de `.wav` para más
  adelante ("los sintéticos son horribles").
