class_name SettingsPanel
extends Control
## Panel de Configuración (menú principal). Versión PC: vídeo. Cada cambio se aplica y se guarda al momento
## (SettingsManager). Preparado para añadir más secciones (audio, controles…).

signal closed

var _mode_opt: OptionButton
var _res_opt: OptionButton
var _vsync_check: CheckButton
var _fps_opt: OptionButton
# --- Pruebas (PROVISIONAL) ---
var unlock_all_button: Button
var delete_save_button: Button
var no_save_check: CheckButton
var _dev_info: Label
var _delete_armed: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_load_values()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


func _sm() -> Node:
	return get_node_or_null("/root/SettingsManager")


func _row(grid: GridContainer, title: String, ctrl: Control, hint: String = "") -> void:
	var l := UiKit.label(title, 16, UiKit.TEXT)
	l.tooltip_text = hint
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	ctrl.custom_minimum_size = Vector2(260, 38)
	ctrl.tooltip_text = hint
	grid.add_child(ctrl)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiKit.panel(UiKit.BG, UiKit.BORDER, 14, 2, 22)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var header := HBoxContainer.new()
	v.add_child(header)
	var title := UiKit.label("⚙  CONFIGURACIÓN", 26, UiKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var x := Button.new()
	x.text = "✕"
	x.tooltip_text = "Cerrar (Esc)"
	x.custom_minimum_size = Vector2(40, 36)
	UiKit.style_button(x, UiKit.PANEL_2, UiKit.BORDER)
	x.pressed.connect(close)
	header.add_child(x)

	v.add_child(UiKit.label("VÍDEO", 13, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)

	_mode_opt = OptionButton.new()
	_mode_opt.name = "WindowModeOption"
	for n in SettingsManager.WINDOW_MODE_NAMES:
		_mode_opt.add_item(n)
	_mode_opt.item_selected.connect(func(i: int):
		var sm := _sm()
		if sm:
			sm.set_window_mode(i)
		_update_enabled())
	_row(grid, "Modo de pantalla", _mode_opt, "Ventana, pantalla completa exclusiva o ventana sin bordes a pantalla completa")

	_res_opt = OptionButton.new()
	_res_opt.name = "ResolutionOption"
	for r in SettingsManager.RESOLUTIONS:
		_res_opt.add_item("%d × %d" % [r.x, r.y])
	_res_opt.item_selected.connect(func(i: int):
		var sm := _sm()
		if sm:
			sm.set_resolution(SettingsManager.RESOLUTIONS[i]))
	_row(grid, "Resolución", _res_opt, "Tamaño de la ventana (solo en modo Ventana)")

	_vsync_check = CheckButton.new()
	_vsync_check.name = "VsyncCheck"
	_vsync_check.text = ""
	_vsync_check.toggled.connect(func(on: bool):
		var sm := _sm()
		if sm:
			sm.set_vsync(on))
	_row(grid, "Sincronización vertical", _vsync_check, "Evita el tearing; limita los FPS a la frecuencia del monitor")

	_fps_opt = OptionButton.new()
	_fps_opt.name = "FpsOption"
	for f in SettingsManager.FPS_LIMITS:
		_fps_opt.add_item("Sin límite" if f == 0 else "%d FPS" % f)
	_fps_opt.item_selected.connect(func(i: int):
		var sm := _sm()
		if sm:
			sm.set_max_fps(SettingsManager.FPS_LIMITS[i]))
	_row(grid, "Límite de FPS", _fps_opt, "Máximo de fotogramas por segundo")

	for ob in [_mode_opt, _res_opt, _fps_opt]:
		UiKit.style_button(ob, UiKit.PANEL_2, UiKit.BORDER)

	var note := UiKit.wrap_label("Los cambios se aplican y se guardan al momento.", 12, UiKit.MUTED, 480)
	v.add_child(note)
	_build_dev_section(v)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "Volver"
	back.custom_minimum_size = Vector2(200, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 17)
	UiKit.style_button(back, UiKit.PANEL_2, UiKit.BORDER, UiKit.TEXT, 8)
	back.pressed.connect(close)
	v.add_child(back)


## PROVISIONAL: herramientas para probar el juego (quitar antes de publicar).
func _build_dev_section(v: VBoxContainer) -> void:
	v.add_child(HSeparator.new())
	v.add_child(UiKit.label("PRUEBAS  ·  provisional", 13, Color(1.0, 0.6, 0.3)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	unlock_all_button = Button.new()
	unlock_all_button.name = "UnlockAllButton"
	unlock_all_button.text = "🔓 Desbloquear todo"
	unlock_all_button.tooltip_text = "Todas las especialidades, el hangar del Modo Infinito y +999 🏅"
	unlock_all_button.custom_minimum_size = Vector2(250, 44)
	UiKit.style_button(unlock_all_button, Color(0.18, 0.28, 0.16), UiKit.UP, Color.WHITE, 8)
	unlock_all_button.pressed.connect(_on_unlock_all)
	row.add_child(unlock_all_button)
	delete_save_button = Button.new()
	delete_save_button.name = "DeleteSaveButton"
	delete_save_button.text = "🗑 Borrar partida guardada"
	delete_save_button.tooltip_text = "Borra veteranos, medallas, especialidades y el archivo guardado"
	delete_save_button.custom_minimum_size = Vector2(250, 44)
	UiKit.style_button(delete_save_button, Color(0.3, 0.1, 0.08), UiKit.DOWN, Color.WHITE, 8)
	delete_save_button.pressed.connect(_on_delete_save)
	row.add_child(delete_save_button)
	no_save_check = CheckButton.new()
	no_save_check.name = "NoSaveCheck"
	no_save_check.text = "No guardar nada mientras el juego esté abierto"
	no_save_check.tooltip_text = "Para pruebas: lo que hagas no se escribe en AppData (al cerrar el juego se vuelve a guardar normal)"
	var pm := _pm()
	no_save_check.set_pressed_no_signal(pm != null and not pm.persist)
	no_save_check.toggled.connect(func(on: bool):
		var p := _pm()
		if p:
			p.persist = not on
		_dev_info.text = "No se guardará nada en esta sesión." if on else "El progreso se vuelve a guardar.")
	v.add_child(no_save_check)
	_dev_info = UiKit.label("", 13, UiKit.GOLD)
	_dev_info.name = "DevInfo"
	v.add_child(_dev_info)


func _pm() -> Node:
	return get_node_or_null("/root/ProfileManager")


func _on_unlock_all() -> void:
	var pm := _pm()
	if pm:
		pm.dev_unlock_everything()
		_dev_info.text = "✓ Todo desbloqueado (+999 🏅)."


## Dos pulsaciones: la primera pide confirmación (3 s), la segunda borra.
func _on_delete_save() -> void:
	if not _delete_armed:
		_delete_armed = true
		delete_save_button.text = "⚠ Pulsa otra vez para borrar"
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(self) and _delete_armed:
				_delete_armed = false
				delete_save_button.text = "🗑 Borrar partida guardada")
		return
	_delete_armed = false
	delete_save_button.text = "🗑 Borrar partida guardada"
	var pm := _pm()
	if pm:
		pm.delete_save()
		_dev_info.text = "✓ Partida guardada borrada: el perfil empieza de cero."


func _load_values() -> void:
	var sm := _sm()
	if sm == null:
		return
	_mode_opt.select(sm.window_mode)
	var ri: int = SettingsManager.RESOLUTIONS.find(sm.resolution)
	_res_opt.select(ri if ri >= 0 else 0)
	_vsync_check.set_pressed_no_signal(sm.vsync)
	var fi: int = SettingsManager.FPS_LIMITS.find(sm.max_fps)
	_fps_opt.select(fi if fi >= 0 else SettingsManager.FPS_LIMITS.size() - 1)
	_update_enabled()


func _update_enabled() -> void:
	_res_opt.disabled = _mode_opt.selected != SettingsManager.WINDOW_MODE_NAMES.find("Ventana")
