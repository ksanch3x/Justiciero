# Justiciero — Monorepo de juegos

Este repo aloja varios proyectos de juego en desarrollo con **Godot 4.x**. El juego
principal es **Justiciero** (roguelite/action-RPG top-down), pero antes de invertir
tiempo en sus sistemas más complejos (facciones, sigilo, generación procedural,
progresión permanente) se prueban ideas y mecánicas sueltas en **prototipos**
pequeños y descartables.

## Estructura

```
games/
  justiciero/       # El juego principal. Proyecto Godot completo.
    GDD.md          # Documento de diseño (Game Design Document)
prototypes/
  <nombre>/         # Un prototipo por carpeta, cada uno su propio proyecto Godot
```

- **`games/justiciero/`**: el proyecto real, siguiendo la hoja de ruta por fases
  definida en su `GDD.md` (sección 6). Se desarrolla acá una vez que las mecánicas
  base estén validadas en prototipos.
- **`prototypes/`**: pruebas rápidas y aisladas de una sola mecánica (ej. combate
  top-down, sigilo/detección, IA de facciones, cobertura). Cada carpeta es un
  mini-proyecto Godot independiente, sin pretensión de mantenerse a largo plazo.
  Sirven para validar el "minuto de diversión" antes de construir el juego completo.

## Convención para nuevos prototipos

1. Crear `prototypes/<nombre-descriptivo>/` con su propio `project.godot`.
2. Agregar un `README.md` corto dentro con: qué mecánica prueba y qué se aprendió.
3. Si el prototipo valida una mecánica útil para Justiciero, migrar el código/aprendizaje
   a `games/justiciero/`, no el proyecto entero.

## Estado actual

- `games/justiciero/GDD.md`: documento de diseño v2, con decisiones tomadas y
  preguntas abiertas (ver sección 7 del documento).
- Próximo paso sugerido: definir el "minuto de diversión" (pregunta abierta) creando
  el primer prototipo en `prototypes/`.
