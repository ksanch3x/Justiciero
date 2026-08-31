extends Area2D

## Botín recogible (GDD sección 1, core loop: entrar → RECOLECTAR →
## extraer o morir). Dos fuentes, misma escena:
##
##  - lo que sueltan los enemigos al morir, en el lugar donde cayeron
##    (Main._on_enemy_died). Recogerlo obliga a moverse hacia el cadáver,
##    que es exactamente donde acaba de haber ruido: la exposición es el
##    costo del botín, no un adorno.
##  - contenedores fijos colocados por sala como dato (RoomData `loot`).
##
## No tiene lógica propia más allá de detectar al jugador: quién lleva la
## cuenta del botín de la corrida es Main, y esa cuenta es VOLÁTIL a
## propósito — morir la pierde entera (SaveManager.bank_run solo se llama
## al extraer).

signal picked(amount: int)

## Cuánto vale. Lo lee _ready() para pintar el tamaño, así que Main tiene
## que setearlo ANTES de add_child() (cuidado técnico #3 de STATUS.md).
@export var amount: int = 10
## Color del placeholder. Los contenedores fijos valen más y se pintan
## distinto para que se lean de lejos.
@export var body_color: Color = Color(1.0, 0.85, 0.25, 1.0)

@onready var _visual: ColorRect = $Visual

## Un mínimo de tiempo antes de poder recogerse. Sin esto, un botín que
## cae justo debajo del jugador (enemigo muerto cuerpo a cuerpo) se
## recoge en el mismo frame y no se ve nunca — se pierde la lectura de
## "esto lo dejó el que maté ahí".
const PICKUP_DELAY: float = 0.15
var _age: float = 0.0

func _ready() -> void:
	# El grupo lo usa Main._apply_room_loot() para limpiar de una lo que
	# quedó sin recoger al cambiar de sala.
	add_to_group("loot")
	_visual.color = body_color
	# Tamaño según valor, con techo: un botín gordo se ve gordo, pero no
	# tanto como para tapar media sala.
	var side: float = clamp(10.0 + float(amount) * 0.25, 10.0, 22.0)
	_visual.size = Vector2(side, side)
	_visual.position = -_visual.size * 0.5
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_age += delta
	# Pulso suave para que se distinga del decorado sin necesitar arte.
	_visual.modulate.a = 0.75 + 0.25 * sin(_age * 6.0)

func _on_body_entered(body: Node2D) -> void:
	if _age < PICKUP_DELAY:
		return
	if not body.is_in_group("player"):
		return
	picked.emit(amount)
	queue_free()
