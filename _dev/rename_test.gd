extends Node
## Comprobación del renombrado en la ficha de tropa: clic en el nombre, teclas reales (Enter/Esc),
## nombre vacío, límite de letras y modo Cuartel. Imprime ✔/✘ y RENAME_TEST OK/FALLO; guarda
## _dev/art_tmp/rename_1_editando.png y rename_2_renombrado.png.

var panel
var _fails := 0


func _ready() -> void:
	GameStateManager.reset_run()
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.26, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	panel = preload("res://Scripts/UI/troop_detail_panel.gd").new()
	add_child(panel)
	await get_tree().process_frame

	var c: TroopCard = UnitFactory.make_recruit()
	c.unit_name = "Kaya"
	GameStateManager.add_troop_to_army(c)
	var roster_hits := [0]
	EventBus.roster_changed.connect(func(): roster_hits[0] += 1)
	panel.open_card(c)
	await _frames(3)

	# 1) Clic en el nombre -> campo de texto con el nombre seleccionado
	panel._name_label.gui_input.emit(_click(false))
	await _frames(2)
	_check(panel.is_editing_name(), "clic en el nombre abre el campo")
	_check(panel._name_edit.has_focus(), "el campo tiene el foco")
	_check(panel._name_edit.get_selected_text() == "Kaya", "el nombre sale seleccionado")
	_check(not panel._name_label.visible, "la etiqueta se oculta mientras se escribe")
	await _shot("rename_1_editando")

	# 2) Escribir con teclas reales (sustituye la selección) y Enter
	for k in [KEY_M, KEY_A, KEY_R, KEY_A]:
		await _key(k, true)
	await _key(KEY_ENTER)
	_check(not panel.is_editing_name(), "Enter cierra el campo")
	_check(c.unit_name == "MARA", "Enter guarda el nombre (%s)" % c.unit_name)
	_check(panel._name_label.text == "MARA", "la cabecera muestra el nombre nuevo")
	_check(roster_hits[0] > 0, "se emite roster_changed")
	await _shot("rename_2_renombrado")

	# 3) Esc cancela solo la edición, la ficha sigue abierta
	panel.begin_name_edit()
	await _frames(1)
	await _key(KEY_X)
	await _key(KEY_ESCAPE)
	_check(not panel.is_editing_name(), "Esc cierra el campo")
	_check(panel.visible, "Esc no cierra la ficha mientras se escribe")
	_check(c.unit_name == "MARA", "Esc no cambia el nombre")
	await _key(KEY_ESCAPE)
	_check(not panel.visible, "un segundo Esc sí cierra la ficha")

	# 4) Vacío / espacios -> se queda el anterior; recorte y límite de letras
	panel.open_card(c)
	await _frames(1)
	panel.begin_name_edit()
	panel._name_edit.text = "   "
	panel.commit_name_edit()
	_check(c.unit_name == "MARA", "un nombre vacío no se acepta")
	_check(panel._name_edit.max_length == TroopCard.NAME_MAX_LEN, "límite de %d letras en el campo" % TroopCard.NAME_MAX_LEN)
	panel.rename("  Cabo Ramírez de la Sierra  ")
	_check(c.unit_name == "Cabo Ramírez de", "recorta espacios y largo (%s)" % c.unit_name)

	# 5) Perder el foco (clic fuera) confirma
	panel.begin_name_edit()
	panel._name_edit.text = "Lola"
	await _frames(1)
	Input.parse_input_event(_motion(Vector2(5, 5)))
	Input.parse_input_event(_click(true, Vector2(5, 5)))
	Input.parse_input_event(_click(false, Vector2(5, 5)))
	await _frames(2)
	_check(c.unit_name == "Lola" and not panel.is_editing_name(), "clic fuera confirma (%s)" % c.unit_name)

	# 6) Cuartel: renombrar emite vault_card_changed y no roster_changed
	panel.close()
	var v := c.duplicate_card()
	var vault_hits := [0]
	panel.vault_card_changed.connect(func(_c): vault_hits[0] += 1)
	panel.open_vault_card(v)
	roster_hits[0] = 0
	panel.rename("Sargento Ríos")
	_check(v.unit_name == "Sargento Ríos" and vault_hits[0] == 1 and roster_hits[0] == 0, "Cuartel: vault_card_changed")
	_check(ProfileManager.card_to_dict(v).unit_name == "Sargento Ríos", "card_to_dict guarda el nombre")

	print("RENAME_TEST " + ("OK" if _fails == 0 else "FALLO (%d)" % _fails))


func _check(ok: bool, what: String) -> void:
	print(("✔ " if ok else "✘ ") + what)
	if not ok:
		_fails += 1


func _key(k: Key, shift := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.pressed = pressed
		if pressed and k >= KEY_A and k <= KEY_Z:
			e.unicode = k # mayúscula (KEY_A == "A")
		Input.parse_input_event(e)
		await _frames(1)


func _click(pressed: bool, pos := Vector2.ZERO) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e


func _motion(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	return e


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(file: String) -> void:
	await _frames(6)
	get_viewport().get_texture().get_image().save_png("res://_dev/art_tmp/%s.png" % file)
