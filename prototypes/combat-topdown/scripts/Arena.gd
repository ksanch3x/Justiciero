extends Node

## Autoload — límites del área jugable de la sala ACTIVA, en un solo lugar.
##
## Antes cada script que necesitaba "no salirte del mapa" tenía su propia
## copia hardcodeada del rectángulo viejo (`PATROL_ARENA_MIN/MAX` en
## Enemy/Spitter/Police/Criminal, `ARENA_MIN/MAX` en Player) — 5 copias del
## mismo ±400/±270. Eso funcionaba mientras TODAS las salas fueran el mismo
## rectángulo de 900x640; con salas de forma y tamaño distinto (ver
## RoomData.gd) esos números quedaron mal en casi todas: en room_3, por
## ejemplo, el área real llega a x=±620, así que el clamp viejo encerraba a
## los bots en el tercio central del andén.
##
## Main.set_room() lo actualiza en cada transición de sala.
##
## Nota: `bounds` es el BOUNDING BOX de la unión de rects, no la forma
## exacta — un punto clampeado puede caer igual en un hueco de una sala en
## L. Alcanza para lo que se usa (evitar que un empujón mande a alguien
## fuera del mapa, y que un punto de patrulla quede absurdamente lejos);
## la colisión real con los muros la sigue haciendo la física.

## Valor inicial razonable por si algo consulta antes de que Main corra
## _ready() — se pisa en la primera llamada a set_bounds().
var bounds: Rect2 = Rect2(-400, -270, 800, 540)

## Margen por defecto: radio de colisión de los cuerpos (14px, ver
## CircleShape2D_player en Player.tscn) más un poco, para que un punto
## clampeado no quede incrustado en el muro.
const BODY_MARGIN: float = 20.0

func set_bounds(new_bounds: Rect2) -> void:
	bounds = new_bounds

## Devuelve `pos` clampeado dentro del área jugable, dejando `margin` px
## libres contra el borde.
func clamp_point(pos: Vector2, margin: float = BODY_MARGIN) -> Vector2:
	var min_x: float = bounds.position.x + margin
	var max_x: float = bounds.position.x + bounds.size.x - margin
	var min_y: float = bounds.position.y + margin
	var max_y: float = bounds.position.y + bounds.size.y - margin
	# Si la sala es más angosta que 2*margin en algún eje, clampf con
	# min > max devolvería basura — en ese caso se usa el centro del eje.
	var x: float = (bounds.position.x + bounds.size.x / 2.0) if min_x > max_x else clampf(pos.x, min_x, max_x)
	var y: float = (bounds.position.y + bounds.size.y / 2.0) if min_y > max_y else clampf(pos.y, min_y, max_y)
	return Vector2(x, y)
