extends CanvasLayer

signal chosen
## Emitida solo en modo "door_pick", en vez de `chosen` (Main necesita saber
## QUÉ puerta se eligió, no solo que se eligió algo).
signal door_chosen(side: String)

var _player: CharacterBody2D
## Lado -> id de sala destino, guardado por show_choices() en modo
## "door_pick" (ver RoomData.doors). Solo se usa dentro de ese modo.
var _doors: Dictionary = {}
## Oferta de extracción del momento (Main._extraction_offer()):
## {"rate": float, "money": int, "total": int}. Vacío = no ofrecer salida.
var _extraction: Dictionary = {}

const DOOR_LABELS: Dictionary = {"east": "Puerta Este", "west": "Puerta Oeste"}
## "Lado" centinela con el que se emite door_chosen cuando el jugador elige
## extraer en vez de cruzar una puerta — reusa la señal que ya existía en
## lugar de agregar una segunda. Main.gd define la misma constante (esta
## escena no tiene class_name, no se puede referenciar desde allá): si se
## cambia una, hay que cambiar la otra.
const EXTRACT_SIDE: String = "extract"
## Orden fijo de recorrido para que "Este" siempre aparezca antes que "Oeste"
## sin depender del orden de inserción del Dictionary de la sala.
const DOOR_SIDE_ORDER: Array[String] = ["east", "west"]

@onready var _buttons_container: VBoxContainer = $Panel/Root/VBoxContainer
@onready var _title: Label = $Panel/Root/Title

func _ready() -> void:
	hide()

## mode: "weapon_pick" (elección inicial, cuchillo vs hacha), "milestone"
## (cada MILESTONE_EVERY oleadas: subir de nivel vs arma nueva), "upgrade"
## (mejoras normales del árbol, filtradas por el arma equipada), o
## "door_pick" (sala despejada: elegir por cuál puerta seguir, o extraer;
## `doors` trae el mapeo lado->sala destino, y `extraction` la oferta de
## salida — ver Main._open_room_doors y Main._extraction_offer).
func show_choices(player: CharacterBody2D, mode: String = "upgrade", doors: Dictionary = {}, extraction: Dictionary = {}) -> void:
	_player = player
	_doors = doors
	_extraction = extraction

	for child in _buttons_container.get_children():
		child.queue_free()

	match mode:
		"weapon_pick":
			_title.text = "Elegí tu arma inicial"
			_show_weapon_pick_choices()
		"milestone":
			_title.text = "¡Hito! Elegí un arma nueva o mejorá la que tenés"
			_show_milestone_choices()
		"door_pick":
			_title.text = "¡Sala despejada! Seguir adelante o extraer"
			_show_door_pick_choices()
		_:
			_title.text = "¡Oleada superada! Elegí una mejora:"
			_show_upgrade_choices()

func _show_door_pick_choices() -> void:
	for side in DOOR_SIDE_ORDER:
		if not _doors.has(side):
			continue
		var btn := _make_card_button(null, Rect2(), DOOR_LABELS[side], "Cruzá para continuar por este camino")
		btn.pressed.connect(_on_door_picked.bind(side))
		_buttons_container.add_child(btn)

	# Tercera opción: irse con lo puesto (GDD sección 1, "extraer o
	# morir"). Va con los números concretos porque la decisión sin ellos
	# es a ciegas — no se puede pesar codicia contra riesgo sin saber
	# cuánto se pierde por salir ahora.
	if not _extraction.is_empty():
		var take: int = int(_extraction["money"])
		var total: int = int(_extraction["total"])
		var pct: int = int(round(float(_extraction["rate"]) * 100.0))
		var desc: String = "Terminás la corrida y te llevás %d de %d (%d%%). Lo demás se pierde." % [take, total, pct]
		var extract_btn := _make_card_button(null, Rect2(), "Extraer ahora", desc)
		extract_btn.pressed.connect(_on_door_picked.bind(EXTRACT_SIDE))
		_buttons_container.add_child(extract_btn)
	show()

func _show_weapon_pick_choices() -> void:
	for weapon_id in WeaponData.MELEE_IDS:
		_make_weapon_card(weapon_id, 1, _on_weapon_picked)
	show()

func _show_milestone_choices() -> void:
	var choices: Array = WeaponData.milestone_choices(_player)
	if choices.is_empty():
		_show_upgrade_choices()
		return
	for choice in choices:
		_make_weapon_card(choice["id"], choice["level"], _on_weapon_picked)
	show()

## Si no hay ninguna mejora disponible para el arma actual (y mov/sur ya
## agotadas), no muestra el panel: avisa a Main directamente vía `chosen`,
## igual que si el jugador hubiese elegido algo.
func _show_upgrade_choices() -> void:
	var weapon_kind := ""
	if _player.weapon_id != "":
		weapon_kind = "melee" if not WeaponData.is_ranged(_player.weapon_id) else "ranged"

	var choices := UpgradeTree.roll(_player.all_taken_upgrades(), 3, weapon_kind)
	if choices.is_empty():
		chosen.emit()
		return

	for upgrade in choices:
		_make_upgrade_card(upgrade)
	show()

func _make_weapon_card(weapon_id: String, level: int, on_pick: Callable) -> void:
	var btn := _make_card_button(
		WeaponData.icon_texture(weapon_id, level),
		WeaponData.icon_region(weapon_id, level),
		WeaponData.display_name(weapon_id, level),
		WeaponData.description(weapon_id)
	)
	btn.pressed.connect(on_pick.bind(weapon_id, level))
	_buttons_container.add_child(btn)

func _make_upgrade_card(upgrade: Dictionary) -> void:
	var icon_tex: Texture2D = null
	var icon_region := Rect2()
	if _player.weapon_id != "" and upgrade.get("kind", "") != "":
		icon_tex = WeaponData.icon_texture(_player.weapon_id, _player.weapon_level)
		icon_region = WeaponData.icon_region(_player.weapon_id, _player.weapon_level)

	var btn := _make_card_button(icon_tex, icon_region, upgrade["name"], upgrade["desc"])
	btn.pressed.connect(_on_upgrade_picked.bind(upgrade))
	_buttons_container.add_child(btn)

## Construye una tarjeta Button con ícono (opcional) + nombre + descripción.
## Todos los hijos con MOUSE_FILTER_IGNORE: si no, absorben el click y el
## Button deja de recibir input (bug silencioso, sin error en consola).
func _make_card_button(icon_tex: Texture2D, icon_region: Rect2, title: String, desc: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(320, 64)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	btn.add_child(hbox)

	if icon_tex != null:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(48, 48)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var atlas := AtlasTexture.new()
		atlas.atlas = icon_tex
		atlas.region = icon_region
		icon.texture = atlas
		hbox.add_child(icon)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var name_label := Label.new()
	name_label.text = title
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc_label)

	return btn

func _on_door_picked(side: String) -> void:
	hide()
	door_chosen.emit(side)

func _on_weapon_picked(weapon_id: String, level: int) -> void:
	_player.equip_weapon(weapon_id, level)
	hide()
	chosen.emit()

func _on_upgrade_picked(upgrade: Dictionary) -> void:
	upgrade["apply"].call(_player)
	if upgrade.get("kind", "") == "":
		_player.taken_upgrades.append(upgrade["id"])
	else:
		_player.weapon_upgrades.append(upgrade["id"])
	hide()
	chosen.emit()
