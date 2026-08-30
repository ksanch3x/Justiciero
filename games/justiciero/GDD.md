# GDD: Justiciero (v2 — decisiones de diseño incorporadas)

**Motor:** Godot 4.x (2D)
**Género:** Roguelite / Action-RPG Top-Down
**Estilo Visual:** Pixel Art 2D — vista superior, 8 direcciones
**Rol del Desarrollador:** Director de Juego & Diseñador (programación asistida por IA)

> Este documento actualiza el GDD original con las decisiones de diseño tomadas en la ronda de planificación. Las preguntas abiertas resueltas se marcan como **[Decidido]**; lo que sigue pendiente se marca como **[Pendiente]** y queda listado en la sección 7.

---

## 0. Alcance y MVP

Antes de programar todo a la vez, conviene tener claro el mínimo jugable que valida el concepto. "Justiciero" combina combate + sigilo + IA de facciones + generación procedural + meta-progresión — cada sistema es un proyecto no trivial por sí solo. Se recomienda la hoja de ruta por fases (sección 6) en vez de todo desde el día uno.

**"Minuto de diversión" — [Decidido]: el Triángulo de Facciones en acción** (sección 2.1). Ver a policía y bandas criminales generar caos entre sí sin intervención directa del jugador es "el corazón del gancho del juego" según la sección 2.1 — es el sistema que hay que pulir primero como núcleo, por encima de sigilo/Alerta o de combate/progresión permanente (que siguen siendo necesarios, pero como soporte del gancho principal, no como el gancho en sí). Esto reordena la prioridad práctica dentro de la Fase 4 de la hoja de ruta (sección 6): dentro de esa fase, la interacción policía↔criminales es lo primero que debe sentirse bien, antes de pulir el resto.

---

## 1. Visión General & Core Loop

El jugador encarna a un justiciero urbano en una metrópolis dominada por el crimen — tono **GTA de mundo abierto**, estructurado como **roguelite de dificultad decreciente**: difícil desde el primer intento, y lo que lo aligera es el **Árbol de Habilidades permanente**, no el progreso dentro de una partida.

> **Pilar de diseño:** morir es barato y esperado — perdés el botín de esa incursión, pero **nunca perdés el Árbol de Habilidades**. La dificultad real está en cuánto ha crecido tu Árbol, no en qué tan lejos llegaste en una sola corrida (modelo *Dead Cells*/*Hades*, no permadeath clásico).

**Narrativa — [Decidido]:** el juego tiene un **arco narrativo con final definido**, revelado principalmente en el Hub entre incursiones (no durante la corrida en sí), al estilo *Hades*. El final se desbloquea cuando el jugador acumula suficiente progreso permanente (Reputación / hitos del Árbol) — no depende de "ganar" una sola partida, lo que mantiene coherencia con el pilar de arriba.

El jugador es perseguido tanto por bandas criminales como por la policía.

### El Bucle Principal

1. **El Hub (Ciudad Fija — [Decidido]: un solo hub):** compra mejoras permanentes, selecciona contratos, y es donde avanza la narrativa entre incursiones.
2. **Entrada a Misiones (Interiores):** edificios corporativos, parqueos subterráneos, estaciones de metro, callejones.
3. **Fase de Infiltración y Combate:** limpia salas prediseñadas, recolecta botín, evita o enfrenta a la policía si sube la Alerta.
4. **Muerte o Extracción:**
   - **Éxito:** vuelve con el botín y dinero acumulado.
   - **Muerte:** pierde el dinero de esa incursión; conserva Reputación y desbloqueos del Hub.

---

## 2. Mecánicas Clave y Sistemas

### 2.1 Triángulo de Facciones (IA)

| Facción | Objetivo | Reacciona a |
|---|---|---|
| **Jugador** | Cumplir el contrato, extraer con botín | — |
| **Criminales** | Proteger territorio/botín | Ataca al jugador si lo detecta; ataca a la policía si es visto cometiendo un crimen frente a ellos |
| **Policía** | Mantener el orden, arrestar/neutralizar | Sube Nivel de Alerta si detecta al jugador; persigue criminales in fraganti |

Las tres facciones deben poder generar caos entre ellas sin intervención directa del jugador — es el corazón del "gancho" del juego. Vale la pena prototipar esta interacción aislada y temprano.

### 2.2 Sistema de Alerta / Ruido (por misión)

Niveles discretos, similar al "wanted level" de GTA:

| Nivel | Disparador | Comportamiento policial |
|---|---|---|
| 0 — Ignorado | Sin testigos, sin ruido reciente | Patrulla normal |
| 1 — Sospecha | Ruido sin visual directo | Un agente investiga la última posición del sonido |
| 2 — Persecución | Jugador visto en combate | Agentes cercanos persiguen, piden refuerzos |
| 3 — Bloqueo | Persecución sostenida / múltiples testigos | Refuerzos bloquean salidas conocidas |

**Decae con el tiempo** si el jugador rompe línea de visión y no genera más ruido — le da ritmo de tensión-alivio al sigilo.

> **Importante:** este sistema es **por misión** — se resetea entre incursiones. No confundir con Notoriedad (2.5), que es persistente.

**Fuentes de ruido:** disparos (radio grande, casi siempre sube a Nivel 1), melee (silencioso sin testigos), vidrios/puertas/alarmas (radio corto), cuerpos descubiertos (sube automático).

### 2.3 Combate y Sigilo

- **Melee vs. Ranged:** melee silencioso pero de alto riesgo (corto alcance); armas de fuego seguras a distancia pero generan ruido — eje central de las decisiones tácticas.
- **Movilidad:** dash/esquiva con costo (stamina o cooldown), para que no sea i-frames infinitos.
- **Escasez de recursos:** munición y curación finitas por incursión, no regenerables dentro de la misión.
- **Cobertura — [Decidido]: mecánica activa.** El jugador puede "pegarse a cobertura" (tipo twin-stick shooter), no solo bloqueo físico de línea de visión. Esto implica:
  - Un nuevo estado `EnCobertura` en `Player` (`CharacterBody2D`).
  - `EnemyBase` necesita calcular línea de visión considerando si el jugador está en ese estado, no solo geometría estática — más trabajo que la opción simple original, pero es la elección tomada.
- **Letal vs. no letal — [Decidido]: consecuencia distinta.** Matar policías sube dificultad futura (ver 2.5 Notoriedad); noquear es más seguro pero más lento/arriesgado en el momento.

### 2.4 Árbol de Habilidades (Progresión Permanente)

Sistema central del juego — la razón por la que el jugador vuelve tras morir.

- **La Reputación nunca baja.** Confirmado como regla dura, no solo pilar de diseño — ver 2.5 para cómo se resolvió la tensión con la consecuencia de matar.
- Se financia con Reputación (largo plazo), no con Dinero (corto plazo, se gasta o pierde dentro de la misma partida).
- Estructura de nodos con prerrequisitos, no lista de compras plana.

**Ramas sugeridas:**

| Rama | Nodo temprano | Nodo medio | Nodo tardío |
|---|---|---|---|
| **Supervivencia** | +Salud máxima | Reducción de daño recibido | Revivir una vez por incursión |
| **Ofensiva** | +Daño melee | +Daño a distancia | Ejecución instantánea a enemigos con poca vida |
| **Sigilo** | Radio de ruido reducido | Bomba de humo inicial gratis | Invisibilidad breve bajo cobertura |
| **Utilidad** | +1 espacio de inventario | Ganzúas ilimitadas | Extracción de emergencia |

**Efecto en la dificultad:** el contenido no escala hacia arriba — el jugador escala hacia el contenido, con una dificultad fija bien calibrada para "árbol vacío". Esto simplifica el diseño de misiones: no hace falta dificultad dinámica.

### 2.5 Sistema de Notoriedad (NUEVO — [Decidido] el mecanismo y los números)

Introducido para resolver la tensión entre "matar sube la dificultad futura" y el pilar de "la Reputación nunca baja". Es una **segunda estadística, separada de la Reputación**:

- **Persistente entre incursiones** (a diferencia del Nivel de Alerta, que es por misión).
- Sube cuando el jugador **mata** policías **o testigos civiles** — **[Decidido]**: no se limita a policía, matar testigos también sube Notoriedad (noquear no la sube en ningún caso). Mantiene el tono "GTA" de consecuencias por violencia indiscriminada, no solo por enfrentarse al estado. Los criminales quedan fuera — son un problema aparte del jugador, no algo que el jugador "gane" por matarlos.
- Efecto: sube el nivel base de Alerta / cantidad de refuerzos en incursiones futuras — el mundo se vuelve más hostil, sin tocar la Reputación ni el Árbol.
- **Reducción en el Hub — [Decidido]: ambas vías en paralelo.** Pagar con Dinero (rápido, cuesta más por tier) y una misión especial de "bajo perfil" (gratis pero más lenta) están disponibles al mismo tiempo — el jugador elige entre gastar dinero para ir rápido o gastar tiempo para ir gratis.
- **Tiers y techo — [Decidido]: 3 tiers con techo** (Bajo/Medio/Alto). Cada tier sube la Alerta base/refuerzos de la incursión siguiente; el tier más alto tiene techo (no escala sin límite). Simple de balancear y de comunicar al jugador vs. una escala granular de 5+ tiers.
- **Prototipo actual** (`prototypes/combat-topdown/scripts/SaveManager.gd`): ya implementa la mitad "sube y persiste" con un solo policía y un techo numérico provisorio (20, sin tiers todavía) — falta trasladar el modelo de 3 tiers, sumar testigos civiles como fuente, y construir el Hub real para alojar las dos vías de reducción.

---

## 3. Estructura de Misiones y Generación de Niveles

**Salas en grilla con conectores de puerta fijos** (approach de *Enter the Gungeon* / *The Binding of Isaac*):

1. Cada sala es una `PackedScene` con puertas en posiciones fijas (N/S/E/O), diseñadas a mano.
2. Un generador recorre una grilla lógica, garantizando que cada sala colocada conecte con una vecina compatible.
3. Salas especiales (botín, extracción, jefe) con reglas propias — ej. extracción siempre la más lejana del punto de entrada.

Más simple que BSP o ruido, y encaja con "salas prediseñadas".

**Estructura sugerida:** 4-6 salas (misión corta) / 8-12 (larga); dificultad escalando por sala; extracción señalizada y disponible desde el inicio (permite abortar con lo recolectado).

---

## 4. Arte, Assets & Estructura del Proyecto

**Asset packs — [Decidido]:**
- **Kenney "Roguelike Modern City"** (CC0, 1036 assets) — exteriores/calles, para el **Hub**.
- **Kenney "Roguelike Indoors"** (CC0, 480 assets) — interiores de edificios, para las **misiones**.
- Ambos de la misma serie de Kenney, mismo grid (16x16 px — verificar al abrir el spritesheet antes de fijarlo en el `TileSet` de Godot).
- Ninguno de los dos trae personajes animados en 8 direcciones — **[Pendiente]** elegir fuente para Jugador/Policía/Criminales (Idle/Walk/Attack/Dash), idealmente también a 16x16 para mantener consistencia.

- **Mapeo de Sprites:**
  - Jugador: sprite sheet 8 direcciones (Idle, Walk, Attack, Dash).
  - Facciones: diferenciadas por color/silueta.
  - Escenarios (`TileMapLayer`): capa de suelo + capa de colisión.
- **Audio:** sonidos de detección/alerta (sting de "te vieron", sirena aproximándose) tan importantes como disparos/golpes.

### Estructura de Carpetas (`res://`)

```
res://assets/sprites/player/
res://assets/sprites/enemies/
res://assets/tilesets/
res://assets/audio/
res://scenes/
res://scenes/rooms/
res://scripts/
res://scripts/states/
res://data/
```

---

## 5. Arquitectura Técnica para Godot 4

### 5.1 Nodos y Escenas Base

- **`Player` (`CharacterBody2D`):** movimiento 8 direcciones, dash/esquiva con cooldown, salud, estados de combate, **nuevo estado `EnCobertura`** (ver 2.3).
- **`EnemyBase` (`CharacterBody2D`):** máquina de estados (Patrulla → Alerta/Investigar → Persecución → Ataque → Huida). La detección debe considerar el estado `EnCobertura` del jugador, no solo geometría estática.
- **`TileMapLayer`:** terrenos, paredes con colisión, decoración.
- **Detección:** `Area2D` circular para el MVP; cono de visión real (raycasts) como mejora post-MVP.

### 5.2 Autoloads (Singletons)

- **`GameManager`:** estado de la partida actual, transición de escenas.
- **`FactionManager`:** Nivel de Alerta (por misión, decae con el tiempo) **y ahora también trackea Notoriedad** (persistente, vía `SaveManager`) — son datos relacionados pero con ciclos de vida distintos, conviene mantenerlos como propiedades separadas dentro del mismo manager o dividir en `FactionManager` + `NotorietyManager` si crece mucho.
- **`SaveManager`:** persistencia de Reputación, Notoriedad y mejoras permanentes (`ConfigFile` o JSON).
- **`EventBus`** *(opcional, recomendado)*: señales globales (`player_detected`, `noise_made`, `enemy_died`, `police_killed`) para desacoplar Player/Enemy/FactionManager.

### 5.3 Input — [Decidido]

Usar `InputMap` de Godot con acciones abstractas (`mover_arriba`, `atacar`, etc.) desde el día uno — soporta teclado+mouse y gamepad sin refactor futuro. El pulido/testeo de mando puede quedar para una fase posterior sin costo de arquitectura.

### 5.4 Consideraciones de rendimiento

- **Pooling de proyectiles:** reusar instancias en vez de `instantiate()`/`queue_free()` repetido.
- **Máquina de estados de enemigos:** `enum` + `match` alcanza para pocos tipos; migrar a `State` como escena separada si el roster crece.

---

## 6. Hoja de Ruta Sugerida (Fases de Desarrollo)

1. **Prototipo de combate:** jugador + un tipo de criminal en una sala fija. Sin sigilo, sin alerta.
2. **IA básica de enemigo:** máquina de estados en `EnemyBase`, sin policía todavía.
3. **Sistema de Alerta + Policía + Notoriedad:** agregar la segunda facción, las reglas de ruido/decaimiento, y la capa persistente de Notoriedad.
4. **Triángulo completo:** criminales y policía interactuando entre sí.
5. **Estructura de misión:** salas prediseñadas conectadas (orden fijo primero) + extracción.
6. **Generación procedural real** de la conexión de salas.
7. **Hub + progresión permanente + guardado + arco narrativo.**

---

## 7. Preguntas Abiertas Restantes

Las 5 preguntas de esta lista quedaron resueltas — ver sección 2.5 (Notoriedad: mecanismo de reducción, tiers/techo, alcance) y sección 0 ("minuto de diversión"). Queda una sola pendiente real:

- **Pack de personajes — [Decidido, provisorio]: seguir con placeholders de color por ahora.** No es prioridad mientras se siguen probando mecánicas — los tintes de color (como ya se hizo con `Police.gd`, que reusa el sprite del jugador teñido de azul) alcanzan. Elegir una fuente real de sprites 8-direcciones (Idle/Walk/Attack/Dash) para Jugador/Policía/Criminales queda para cuando el arte importe más que la funcionalidad — no bloquea ningún sistema pendiente.
- **Riesgo de balance:** calibrar la dificultad con el árbol vacío (primer intento) sigue siendo el trabajo de diseño más delicado del proyecto — no es una pregunta que se "resuelva" de una vez, es un ajuste continuo a medida que haya más sistemas jugables.

---

## Resumen Ejecutivo de Decisiones Tomadas

| # | Pregunta | Decisión |
|---|---|---|
| 1 | Narrativa | Arco con final definido, revelado entre incursiones (estilo Hades) |
| 2 | Matar vs. noquear | Consecuencia distinta |
| 3 | Mecanismo de esa consecuencia | Reputación nunca baja + nueva stat **Notoriedad** |
| 4 | Hubs | Uno solo, fijo |
| 5 | Gamepad | InputMap desde el inicio (soporta ambos), pulido de mando después |
| 6 | Cobertura | Mecánica activa — "pegarse a cobertura" |
| 7 | Assets de entorno | Kenney "Roguelike Modern City" (Hub) + "Roguelike Indoors" (misiones), CC0, 16x16 |
| 8 | Reducción de Notoriedad | Pagar con Dinero + misión de "bajo perfil", ambas vías en paralelo |
| 9 | Tiers de Notoriedad | 3 tiers (Bajo/Medio/Alto) con techo en el tier más alto |
| 10 | Alcance de Notoriedad | Cuenta matar policías y testigos civiles (no criminales) |
| 11 | Pack de personajes | Placeholders de color por ahora (no bloquea desarrollo) |
| 12 | "Minuto de diversión" | El Triángulo de Facciones en acción — núcleo a pulir primero |
