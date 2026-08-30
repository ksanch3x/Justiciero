extends Node

## Autoload — GDD (games/justiciero/GDD.md) sección 2.5 y 5.2: Notoriedad,
## la stat que SÍ persiste entre corridas (a diferencia del Nivel de Alerta
## de FactionManager.gd, que es por misión y se resetea siempre). Sube
## cuando el jugador mata policías — noquear no la sube, pero no hay
## sistema no-letal implementado todavía (GDD 2.3, pendiente), así que por
## ahora CUALQUIER muerte de un Police.gd cuenta como "matar".
##
## Solo Notoriedad por ahora — Reputación (GDD 2.4, financia el Árbol de
## Habilidades permanente) y el resto del guardado quedan para cuando
## exista el Árbol de verdad, no tiene sentido persistir un stat sin nada
## que lo lea todavía.
##
## Mecanismo de reducción en el Hub (GDD 2.5) sigue [Pendiente] en el GDD
## mismo — no implementado acá tampoco, esta es solo la mitad "sube y
## persiste" del sistema.

const SAVE_PATH: String = "user://justiciero_save.cfg"
const SECTION: String = "progress"
const KEY_NOTORIETY: String = "notoriety"

## Cuánto sube la Notoriedad por cada policía muerto por el jugador.
const NOTORIETY_PER_POLICE_KILL: int = 1
## Y por cada testigo civil. GDD 2.5 [Decidido]: cuenta matar policías Y
## testigos civiles (no criminales — esos son un problema aparte, no algo
## que el jugador "gane" por matarlos). Pesa menos que un policía: matar
## al estado es peor que matar a un transeúnte, pero ninguno es gratis.
const NOTORIETY_PER_CIVILIAN_KILL: int = 1
## Techo simple para que no crezca sin límite mientras no haya UI/tiers
## definidos (GDD 2.5 lo deja [Pendiente] explícitamente) — valor
## provisorio, fácil de subir/quitar cuando se definan los tiers reales.
const NOTORIETY_CAP: int = 20

var notoriety: int = 0

signal notoriety_changed(new_value: int)

func _ready() -> void:
	_load_data()

func add_police_kill() -> void:
	_add_notoriety(NOTORIETY_PER_POLICE_KILL)

func add_civilian_kill() -> void:
	_add_notoriety(NOTORIETY_PER_CIVILIAN_KILL)

func _add_notoriety(amount: int) -> void:
	notoriety = min(NOTORIETY_CAP, notoriety + amount)
	_save_data()
	notoriety_changed.emit(notoriety)

func _load_data() -> void:
	var cfg := ConfigFile.new()
	# ERR_FILE_NOT_FOUND es esperado la primera vez que corre el juego —
	# no es un error real, `notoriety` ya arranca en 0 por defecto.
	if cfg.load(SAVE_PATH) == OK:
		notoriety = int(cfg.get_value(SECTION, KEY_NOTORIETY, 0))

func _save_data() -> void:
	var cfg := ConfigFile.new()
	# Recarga antes de guardar para no pisar otras claves que el futuro
	# guardado de Reputación/Árbol vaya a agregar a este mismo archivo.
	cfg.load(SAVE_PATH)
	cfg.set_value(SECTION, KEY_NOTORIETY, notoriety)
	cfg.save(SAVE_PATH)
