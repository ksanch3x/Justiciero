# Estado del proyecto

Dónde está el prototipo respecto del GDD (`games/justiciero/GDD.md`), qué
se hizo en la última sesión, y qué falta. Para el detalle técnico de cada
sistema —cómo funciona, por qué se hizo así— ver `STATUS.md`, que es la
referencia viva; este archivo es el mapa de arriba.

## Fases del GDD (sección 6)

| Fase | Estado | Nota |
|---|---|---|
| 1. Prototipo de combate | ✅ | Armas (5×2 niveles), oleadas, árbol de mejoras por corrida |
| 2. IA básica de enemigo | ✅ | PATROL/ALERT/CHASE/ATTACK + cono de visión real |
| 3. Alerta + Policía + Notoriedad | ✅ | Medidor 0-100, policía que reacciona al ruido, Notoriedad persistida en disco |
| 4. Triángulo completo | ✅ | Policía↔Criminal pelean solos; testigos civiles |
| 5. Estructura de misión | ✅ | Salas con forma real, botín recogible y extracción con penalización por salir temprano |
| 6. Generación procedural | ✅ | El recorrido se arma en cada corrida desde plantillas |
| 7. Hub + progresión permanente | ❌ | Nada hecho. Es lo más grande que falta |

También cerrado fuera de fase: **GDD 2.3** (cobertura activa con raycast
real, y letal vs. no letal con noqueo que no sube Notoriedad).

## Qué se hizo en la última sesión

Agrupado por tema, con el commit donde quedó.

**Diseño cerrado**
- Las 5 preguntas abiertas de la sección 7 del GDD quedaron decididas y
  escritas en el propio GDD (`0c741b6`): reducción de Notoriedad en el Hub
  (Dinero **y** misión de bajo perfil, en paralelo), 3 tiers con techo,
  cuenta matar policías **y** testigos civiles, placeholders de color por
  ahora, y el "minuto de diversión" = el Triángulo de Facciones.
- Tres salas diseñadas por forma y flujo (oficina / estacionamiento /
  andén), independientes del tileset — publicadas como
  [planos de planta](https://claude.ai/code/artifact/a2cc91e3-8d79-431c-8a0c-a9f9d905fd3b).

**Sistemas nuevos**
- Alerta (`FactionManager`), Policía, Notoriedad persistente
  (`SaveManager`) — `51ebff4`, `d138dbb`, `ed33cc2`.
- Triángulo de Facciones: `Criminal.gd` pelea con `Police.gd` sin que el
  jugador intervenga (`bf17ae9`). Con **regla anti-vaciado**: el daño
  entre IA nunca mata, a poca vida huyen. Solo el jugador puede eliminar
  de verdad — si no, el Triángulo se comía la misión solo.
- Cobertura activa y noqueo no letal (`3249b1a`).
- Cono de visión real, con debug dibujado en pantalla (`ebc0f83`).
- Testigos civiles (`5044499`).
- Salas con forma (unión de rectángulos), muros generados por código,
  cámara por sala (`dd28928`).
- **Botín y extracción (Fase 5, Etapa A)**: pickup de botín de cadáveres y
  de contenedores fijos por sala; opción "Extraer" en cada transición, con
  un porcentaje del dinero que crece con la profundidad (30/45/60/80%) y
  el 100% + una cabeza solo por matar al jefe; `money`/`reputation`/`heads`
  persistidos. Morir pierde todo.
- Recorrido generado por corrida (`95b3a9a`).

**Bugs encontrados jugando y corregidos**
- Enemigos empujados fuera del mapa por el knockback; jugador demasiado
  rápido para un juego de sigilo; patrullas atascadas contra un muro;
  Policía y Criminal que nunca se cruzaban; matar delante de un policía
  sin que reaccionara (`3c4bf47`).
- Noqueo imposible de acertar: rango de 40px y **cero feedback visual**
  (`aa1e129`).
- Bots patrullando alrededor de (0,0) en vez de su spawn (`aa48511`).
- Noquear a un enemigo de oleada no bajaba `enemies_alive`: la oleada no
  terminaba nunca y la vía sigilosa trababa la corrida.
- Resolución nunca fijada, y dos salas más chicas que la vista — Godot no
  puede satisfacer límites de cámara menores al viewport (`b247b72`).

## Cómo se verifica sin Godot

En este entorno no hay editor de Godot: todo se edita como texto. Para no
depender de "lo probamos y vemos", hay herramientas que corren solas:

```
python3 tools/validate_rooms.py    # geometría de las plantillas de sala
python3 tools/check_balance.py     # balance de ()[]{} en los .gd
```

`validate_rooms.py` chequea que la unión de rects de cada sala esté
conectada, que spawns/props/contenedores de botín/entrada caigan dentro y no pisen un muro
interior, que las puertas caigan sobre el borde, y que existan suficientes
plantillas para bifurcar. Se probó metiéndole errores a propósito: los
detecta. **Correrlo después de tocar `RoomData.gd`.**

Además, durante la sesión se portaron a Python el **generador de muros**
(para renderizar cada sala y mirarla) y el **generador de recorridos**
(corrido sobre 3000 semillas: 0 problemas, 120 recorridos distintos). Así
apareció un bug de diseño que no se veía leyendo el código: la sala de
oficinas quedaba fusionada en un blob abierto, sin cuartos.

## Limitaciones conocidas

- **Nada de esto se corrió en Godot todavía.** La geometría y la
  generación están verificadas; el arranque real no. Un nombre de
  propiedad mal escrito o un nodo que no existe recién aparecerían al
  abrir el proyecto.
- Solo dos plantillas tienen 2 puertas y una está fija como entrada, así
  que la segunda bifurcación casi siempre cae en el andén. Se arregla
  agregando plantillas, no código.
- `Arena.bounds` es el bounding box de la sala, no su forma exacta: un
  punto clampeado puede caer en el hueco de una sala en L. Alcanza para
  "no salirte del mapa"; la colisión fina la hace la física.
- Balance con **un solo dato real** de playtest (oleada 7, en una versión
  vieja del juego).
- Assets: sigue el pack *desert-shooter*, no los Kenney *Roguelike Modern
  City* / *Indoors* que pide el GDD 4. Policía, Criminal y Civil son el
  sprite del jugador con `modulate` distinto — decisión explícita
  (GDD sección 7): placeholders hasta que el arte importe más que la
  funcionalidad.

## Qué sigue

Por tamaño e impacto, en orden:

1. **Probarlo en Godot.** Es el bloqueo real: hay mucho código sin correr.
2. **Fase 7 — Hub + Árbol permanente.** Es lo que le da sentido a que
   morir no duela: hoy `UpgradeTree.gd` es progresión *por corrida* y se
   pierde al morir. También falta Reputación (nunca implementada) y el
   mecanismo de bajar Notoriedad, que necesita un Hub donde vivir.
3. **Fase 5, Etapa B**: la misión "edificio" — subir piso por piso el
   mismo plano de oficinas, con la presión escalando por piso (más
   policía, Alerta base más alta, menos cobertura) y dos escaleras que
   llevan a variantes distintas. Se separó de la Etapa A a propósito:
   primero jugar el core loop, después construir la misión encima.
4. Cambio de assets, y otra pasada de balance con más partidas jugadas.
