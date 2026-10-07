extends Control
## Centro de mando (v7): se entra desde el menú principal (Jugar). Válido para PC y móvil (horizontal).
## Una sala en vista ¾ dibujada a 1920×1080 que se escala para caber entera en la pantalla.
## Cada objeto es un CCHotspot (clic/toque solo sobre su silueta, brillo al pasar el ratón):
##   🗺 Mesa táctica → nueva run · 🧊 Tubos criogénicos → veteranos (ficha) · 🗄 Archivo → Códice
##   🖥 Terminal → árbol de especialidades · 🚪 Hangar → modo nuevo (bloqueado hasta 5 veteranos)
##   📻 Radio → Configuración · ← Menú principal
## v7.1: sin rótulos superpuestos (el arte ya lleva sus letreros); la información va en tooltips y avisos.
## Empezar una run o entrar al Modo Infinito pide confirmación.

const DETAIL_PANEL_SCRIPT = preload("res://Scripts/UI/troop_detail_panel.gd")
const RUN_START_SCENE := "res://Scenes/UI/troop_selection_screen.tscn"
const ART := "res://Assets/CommandCenter/"
const ROOM := Vector2(1920, 1080)
const MAIN_MENU_SCENE := "res://Scenes/UI/main_menu.tscn"
const NEW_MODE_NAME := "Modo Infinito"

## Posición (esquina superior izquierda, en coordenadas de la sala) de cada objeto y su color de brillo.
## Sale de Assets/CommandCenter/layout.json (generado con el arte); se copia aquí para no depender
## de un .json en el juego exportado.
const OBJECTS := {
	"war_table": {"file": "war_table.png", "pos": Vector2(593, 458), "glow": Color("2de0d0")},
	"specialty_terminal": {"file": "specialty_terminal.png", "pos": Vector2(1103, 51), "glow": Color("ffcf6a")},
	"hangar_door": {"file": "hangar_door.png", "pos": Vector2(1518, 23), "glow": Color("ff4a4a")},
	"archive": {"file": "archive.png", "pos": Vector2(1395, 614), "glow": Color("ffc870")},
	"radio_station": {"file": "radio_station.png", "pos": Vector2(16, 590), "glow": Color("7dff8a")},
}
const TOOLTIPS := {
	"war_table": "Mesa táctica · nueva operación",
	"specialty_terminal": "Terminal de especialidades · árbol de mejoras",
	"archive": "Archivo · Códice",
	"radio_station": "Radio · Configuración",
}
const TUBE_POSITIONS: Array[Vector2] = [Vector2(12, 87), Vector2(152, 87), Vector2(292, 87), Vector2(432, 87), Vector2(572, 87)]
const TUBE_SIZE := Vector2(212, 458)
const TUBE_SLOT := Rect2(58, 175, 100, 180)
const TUBE_GLOW := Color("5cf2ff")

var change_scene_enabled: bool = true # los tests lo desactivan
var room: Control
var hotspots: Dictionary = {}          # nombre -> CCHotspot
var tubes: Array[CCHotspot] = []
var tube_sprites: Array[TextureRect] = []
var detail_panel: CanvasLayer
var codex: CodexPanel = null
var settings: SettingsPanel = null
var tree_panel: SpecialtyTreePanel = null
var back_button: Button
var _hud_label: Label
var _toast: Label
var _confirm_layer: Control
var _confirm_title: Label
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button
var _confirm_action: Callable


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	detail_panel = DETAIL_PANEL_SCRIPT.new()
	detail_panel.name = "TroopDetailPanel"
	add_child(detail_panel)
	detail_panel.vault_card_changed.connect(func(_c): _pm_call("notify_changed"))
	detail_panel.vault_remove_confirmed.connect(_on_vault_remove_confirmed)
	var pm := _pm()
	if pm:
		pm.vault_changed.connect(refresh)
		if pm.has_signal("progress_changed"):
			pm.progress_changed.connect(refresh)
	resized.connect(_fit_room)
	_fit_room()
	refresh()
	if pm and pm.has_method("claimable_specialties") and not pm.claimable_specialties().is_empty():
		var names: Array = pm.claimable_specialties().map(func(sp): return sp.display_name)
		show_toast("🔓 Listas para desbloquear en el Terminal: %s" % ", ".join(names))


func _pm() -> Node:
	return get_node_or_null("/root/ProfileManager")


func _pm_call(method: String) -> void:
	var pm := _pm()
	if pm and pm.has_method(method):
		pm.call(method)


# ---------------------------------------------------------------- construcción

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.04, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	room = Control.new()
	room.name = "Room"
	room.size = ROOM
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(room)
	var room_bg := TextureRect.new()
	room_bg.name = "RoomBackground"
	room_bg.texture = load(ART + "bg_room.png")
	room_bg.size = ROOM
	room_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_child(room_bg)

	# Objetos ordenados por profundidad (lo más bajo en pantalla va delante)
	var items: Array = []
	for i in TUBE_POSITIONS.size():
		items.append({"kind": "tube", "index": i, "bottom": TUBE_POSITIONS[i].y + TUBE_SIZE.y})
	for key in OBJECTS:
		var tex: Texture2D = load(ART + OBJECTS[key].file)
		items.append({"kind": "object", "key": key, "tex": tex, "bottom": OBJECTS[key].pos.y + tex.get_size().y})
	items.sort_custom(func(a, b): return a.bottom < b.bottom)
	for it in items:
		if it.kind == "tube":
			_build_tube(it.index)
		else:
			_build_object(it.key, it.tex)

	# HUD fijo a la pantalla (no se escala con la sala)
	_hud_label = UiKit.label("", 18, UiKit.GOLD)
	_hud_label.name = "HudLabel"
	_hud_label.add_theme_constant_override("outline_size", 6)
	_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hud_label.offset_left = -420
	_hud_label.offset_right = -16
	_hud_label.offset_top = 10
	_hud_label.offset_bottom = 40
	add_child(_hud_label)

	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "←  Menú principal"
	back_button.custom_minimum_size = Vector2(190, 44)
	back_button.position = Vector2(12, 10)
	back_button.add_theme_font_size_override("font_size", 16)
	UiKit.style_button(back_button, Color(0.1, 0.11, 0.14, 0.85), UiKit.BORDER, UiKit.TEXT, 8)
	back_button.pressed.connect(go_main_menu)
	add_child(back_button)

	_toast = UiKit.label("", 20, UiKit.GOLD)
	_toast.name = "Toast"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -420
	_toast.offset_right = 420
	_toast.offset_top = -70
	_toast.offset_bottom = -36
	add_child(_toast)
	_build_confirm()


func _build_object(key: String, tex: Texture2D) -> void:
	var o: Dictionary = OBJECTS[key]
	var h := CCHotspot.new()
	h.name = key
	h.setup(tex, o.glow)
	h.position = o.pos
	room.add_child(h)
	h.activated.connect(_on_object_activated.bind(key))
	h.tooltip_text = TOOLTIPS.get(key, "")
	hotspots[key] = h


func _build_tube(i: int) -> void:
	var back: Texture2D = load(ART + "cryo_tube_back.png")
	var h := CCHotspot.new()
	h.name = "Tube%d" % i
	h.setup(back, TUBE_GLOW)
	h.position = TUBE_POSITIONS[i]
	room.add_child(h)
	h.activated.connect(open_tube.bind(i))
	tubes.append(h)
	var spr := TextureRect.new()
	spr.name = "Occupant%d" % i
	spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = TUBE_POSITIONS[i] + TUBE_SLOT.position
	spr.size = TUBE_SLOT.size
	spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spr.modulate = Color(0.82, 0.95, 1.0) # tinte frío de criogenia
	room.add_child(spr)
	tube_sprites.append(spr)
	var front := TextureRect.new()
	front.name = "TubeGlass%d" % i
	front.texture = load(ART + "cryo_tube_front.png")
	front.position = TUBE_POSITIONS[i]
	front.size = TUBE_SIZE
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_child(front)


## Escala la sala para que quepa entera (PC 16:9, móviles más alargados → franjas laterales).
func _fit_room() -> void:
	if room == null:
		return
	var s: float = minf(size.x / ROOM.x, size.y / ROOM.y)
	if s <= 0.0:
		return
	room.scale = Vector2(s, s)
	room.position = (size - ROOM * s) * 0.5


# ---------------------------------------------------------------- refresco

func refresh() -> void:
	var pm := _pm()
	var vault: Array = pm.vault if pm else []
	for i in tubes.size():
		var card: TroopCard = vault[i] if i < vault.size() else null
		tube_sprites[i].texture = UiKit.troop_texture(card) if card else null
		tubes[i].tooltip_text = ("%s · Nv. %d\nClic para ver su ficha" % [card.get_title(), card.level]) if card \
				else "Tubo vacío: vence al Jefe Final y criogeniza a uno de tus soldados"
	var unlocked: bool = pm != null and pm.is_new_mode_unlocked()
	var n_vault: int = vault.size()
	var size_v: int = ProfileManager.VAULT_SIZE
	var door: CCHotspot = hotspots.get("hangar_door")
	if door and door.material:
		var col := Color("ffb02e") if unlocked else Color("ff4a4a")
		door.glow_color = col
		(door.material as ShaderMaterial).set_shader_parameter("glow_color", col)
	if door:
		door.tooltip_text = ("Hangar · %s" % NEW_MODE_NAME) if unlocked \
				else "Hangar bloqueado · %s: reúne %d veteranos (%d/%d)" % [NEW_MODE_NAME, size_v, n_vault, size_v]
	var medals: int = int(pm.get("medals")) if pm and "medals" in pm else 0
	var wins: int = pm.final_boss_wins if pm else 0
	_hud_label.text = "🏅 %d Medallas   ·   ☠ %d Jefes Finales" % [medals, wins]
	# Especialidades con el hito conseguido: el terminal late hasta que se desbloquean
	var ready: Array = pm.claimable_specialties() if pm and pm.has_method("claimable_specialties") else []
	var term: CCHotspot = hotspots.get("specialty_terminal")
	if term:
		term.attention = not ready.is_empty()
		term.tooltip_text = TOOLTIPS.specialty_terminal + ("\n🔓 Listas para desbloquear: %d" % ready.size() if not ready.is_empty() else "")


# ---------------------------------------------------------------- acciones

func _on_object_activated(key: String) -> void:
	match key:
		"war_table":
			ask_confirm("🗺  ¿Iniciar operación?", "Empezará una run nueva desde la ronda 1.", start_normal_run, "¡A la batalla!")
		"archive":
			open_codex()
		"specialty_terminal":
			open_specialty_tree()
		"radio_station":
			open_settings()
		"hangar_door":
			_on_hangar()


func start_normal_run() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.reset_run()
	if change_scene_enabled:
		get_tree().change_scene_to_file(RUN_START_SCENE)


func open_tube(i: int) -> void:
	var pm := _pm()
	if pm and i < pm.vault.size():
		detail_panel.open_vault_card(pm.vault[i])
	else:
		show_toast("🧊 Tubo vacío: vence al Jefe Final y criogeniza a uno de tus soldados")


func _on_vault_remove_confirmed(card: TroopCard) -> void:
	var pm := _pm()
	if pm and pm.remove_troop(card):
		show_toast("🗑 %s ha salido de la bahía criogénica" % card.unit_name)


func open_codex() -> CodexPanel:
	if codex and is_instance_valid(codex):
		return codex
	codex = CodexPanel.new()
	codex.name = "Codex"
	codex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	codex.closed.connect(func(): codex = null)
	add_child(codex)
	return codex


func open_settings() -> SettingsPanel:
	if settings and is_instance_valid(settings):
		return settings
	settings = SettingsPanel.new()
	settings.name = "Settings"
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings.closed.connect(func(): settings = null)
	add_child(settings)
	return settings


func open_specialty_tree() -> SpecialtyTreePanel:
	if tree_panel and is_instance_valid(tree_panel):
		return tree_panel
	tree_panel = SpecialtyTreePanel.new()
	tree_panel.name = "SpecialtyTree"
	tree_panel.closed.connect(func(): tree_panel = null)
	add_child(tree_panel)
	return tree_panel


func _on_hangar() -> void:
	var pm := _pm()
	if pm and pm.is_new_mode_unlocked():
		ask_confirm("🚪  ¿Entrar en el %s?" % NEW_MODE_NAME, "Tus 5 veteranos saldrán de los tubos criogénicos.", \
				func(): show_toast("⚔ %s: ¡próximamente!" % NEW_MODE_NAME), "Entrar")
	else:
		var n: int = pm.vault.size() if pm else 0
		show_toast("🔒 Hangar bloqueado: necesitas %d veteranos en los tubos (%d/%d)" % [ProfileManager.VAULT_SIZE, n, ProfileManager.VAULT_SIZE])


func go_main_menu() -> void:
	if change_scene_enabled:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_confirm_open():
		close_confirm()
		get_viewport().set_input_as_handled()
	elif codex == null and settings == null and tree_panel == null and not detail_panel.visible:
		go_main_menu()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- confirmación

func _build_confirm() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.name = "Confirm"
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.visible = false
	add_child(_confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)
	var box := UiKit.panel(UiKit.BG, Color("2de0d0"), 12, 2, 22)
	box.custom_minimum_size = Vector2(500, 0)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	box.add_child(v)
	_confirm_title = UiKit.label("", 26, UiKit.GOLD)
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_confirm_title)
	_confirm_text = UiKit.wrap_label("", 15, UiKit.TEXT, 456)
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_confirm_no = Button.new()
	_confirm_no.name = "ConfirmNo"
	_confirm_no.text = "Cancelar"
	_confirm_no.custom_minimum_size = Vector2(190, 52)
	_confirm_no.add_theme_font_size_override("font_size", 17)
	UiKit.style_button(_confirm_no, UiKit.PANEL_2, UiKit.BORDER, UiKit.TEXT, 8)
	_confirm_no.pressed.connect(close_confirm)
	row.add_child(_confirm_no)
	_confirm_yes = Button.new()
	_confirm_yes.name = "ConfirmYes"
	_confirm_yes.custom_minimum_size = Vector2(190, 52)
	_confirm_yes.add_theme_font_size_override("font_size", 17)
	UiKit.style_button(_confirm_yes, Color(0.18, 0.32, 0.18), UiKit.UP, Color.WHITE, 8)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	row.add_child(_confirm_yes)


## Pide confirmación antes de una acción importante (empezar run, entrar en el Modo Infinito).
func ask_confirm(title: String, text: String, action: Callable, yes_text: String = "Aceptar") -> void:
	_confirm_title.text = title
	_confirm_text.text = text
	_confirm_yes.text = yes_text
	_confirm_action = action
	_confirm_layer.visible = true
	_confirm_yes.grab_focus()


func is_confirm_open() -> bool:
	return _confirm_layer != null and _confirm_layer.visible


func close_confirm() -> void:
	_confirm_layer.visible = false
	_confirm_action = Callable()


func _on_confirm_yes() -> void:
	var action := _confirm_action
	close_confirm()
	if action.is_valid():
		action.call()


func show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)
