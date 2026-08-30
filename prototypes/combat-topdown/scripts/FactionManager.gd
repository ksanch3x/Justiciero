extends Node

## Autoload — GDD (games/justiciero/GDD.md) sección 2.2, Sistema de
## Alerta/Ruido. Por ahora solo el medidor + las reglas de subida/
## decaimiento; todavía no hay facción Policía que reaccione a esto (ver
## sección 6 del GDD, ese es el siguiente paso de la Fase 3). Se resetea
## por misión — a diferencia de Notoriedad (GDD 2.5), que sería persistente
## entre corridas y todavía no está implementada.

enum AlertLevel { IGNORED, SUSPICION, CHASE, LOCKDOWN }

const LEVEL_NAMES: Array[String] = ["Ignorado", "Sospecha", "Persecución", "Bloqueo"]
## Umbrales del medidor 0-100 para cada nivel, en el mismo orden que
## AlertLevel. El nivel se recalcula desde el medidor cada vez que cambia
## (subida por ruido, bajada por decaimiento) — un solo medidor, sin lógica
## separada para subir/bajar.
const LEVEL_THRESHOLDS: Array[float] = [0.0, 25.0, 55.0, 85.0]

## Cuánto sube el medidor cada fuente de ruido (GDD 2.2: disparos = radio
## grande, casi siempre sube a Nivel 1; melee silencioso salvo testigo).
## Sin sistema de testigos/radio físico todavía — valor plano por tipo de
## fuente hasta que haya Área2D de ruido real.
const NOISE_GUNSHOT: float = 30.0
const NOISE_MELEE: float = 6.0

## Decae solo cuando no hubo ruido nuevo en los últimos `decay_hold_time`
## segundos — si no, un solo disparo se diluiría antes de que algo llegue
## a reaccionar. Le da el ritmo de tensión-alivio que pide el GDD.
@export var decay_rate: float = 4.0
@export var decay_hold_time: float = 2.5

var meter: float = 0.0
var level: int = AlertLevel.IGNORED
var _hold_timer: float = 0.0
## Última posición donde se generó ruido — a dónde va Police.gd a
## investigar cuando el nivel sube a SUSPICION. Sin sentido hasta el primer
## report_noise(); Police.gd solo lo lee después de que el nivel ya subió.
var last_noise_position: Vector2 = Vector2.ZERO

signal level_changed(new_level: int, old_level: int)

func _process(delta: float) -> void:
	if _hold_timer > 0.0:
		_hold_timer -= delta
		return
	if meter <= 0.0:
		return
	meter = max(0.0, meter - decay_rate * delta)
	_recompute_level()

## Reporta una fuente de ruido (ver constantes NOISE_*). `amount` vive en el
## mismo rango 0-100 del medidor. `position` es dónde ocurrió — Police.gd la
## usa como punto de investigación cuando el nivel sube a SUSPICION.
func report_noise(amount: float, position: Vector2) -> void:
	meter = min(100.0, meter + amount)
	_hold_timer = decay_hold_time
	last_noise_position = position
	_recompute_level()

func _recompute_level() -> void:
	var new_level: int = AlertLevel.IGNORED
	for i in range(LEVEL_THRESHOLDS.size() - 1, -1, -1):
		if meter >= LEVEL_THRESHOLDS[i]:
			new_level = i
			break
	if new_level != level:
		var old_level: int = level
		level = new_level
		level_changed.emit(level, old_level)

## Reinicia el medidor a 0 — llamar al empezar una incursión nueva (el
## Nivel de Alerta es por misión, GDD 2.2, no persiste como Notoriedad).
func reset() -> void:
	meter = 0.0
	_hold_timer = 0.0
	if level != AlertLevel.IGNORED:
		var old_level: int = level
		level = AlertLevel.IGNORED
		level_changed.emit(level, old_level)

func level_name() -> String:
	return LEVEL_NAMES[level]
