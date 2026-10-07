extends Control
## Menú principal: Jugar (→ Centro de mando), Configuración y Salir.
## El Códice, la run normal, los veteranos y las especialidades viven en el Centro de mando.

@export_file("*.tscn") var hub_scene_path: String = "res://Scenes/UI/command_center.tscn"

@onready var play_button: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton
var settings_button: Button
var settings: SettingsPanel = null


func _ready() -> void:
	_style()
	play_button.pressed.connect(_on_play_button_pressed)
	settings_button.pressed.connect(open_settings)
	quit_button.pressed.connect(_on_quit_button_pressed)


func _on_play_button_pressed() -> void:
	if not hub_scene_path.is_empty():
		get_tree().change_scene_to_file(hub_scene_path)
	else:
		push_error("No hub scene path assigned!")


## Abre el panel de Configuración (vídeo).
func open_settings() -> SettingsPanel:
	if settings and is_instance_valid(settings):
		return settings
	settings = SettingsPanel.new()
	settings.name = "Settings"
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings.closed.connect(func(): settings = null)
	add_child(settings)
	return settings


func _on_quit_button_pressed() -> void:
	get_tree().quit()


## Título y botones con el estilo común de la UI (UiKit).
func _style() -> void:
	var bg := get_node_or_null("BackgroundColor") as ColorRect
	if bg:
		bg.color = UiKit.BG
	var box: VBoxContainer = $CenterContainer/VBoxContainer
	box.custom_minimum_size.x = 300
	box.add_theme_constant_override("separation", 14)
	var title := UiKit.label("TROPAS EN MINIATURA", 48, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	box.add_child(title)
	box.move_child(title, 0)
	var sub := UiKit.label("Auto-battler roguelite · cada tropa es única", 15, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.move_child(sub, 1)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	box.add_child(gap)
	box.move_child(gap, 2)
	# Configuración entre Jugar y Salir
	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	box.add_child(settings_button)
	box.move_child(settings_button, quit_button.get_index())
	settings_button.text = "⚙  Configuración"
	settings_button.tooltip_text = "Modo de pantalla, resolución, VSync y FPS"
	for b in [play_button, settings_button, quit_button]:
		b.custom_minimum_size = Vector2(260, 52)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 20)
	play_button.text = "▶  Jugar"
	quit_button.text = "Salir"
	UiKit.style_button(play_button, Color(0.18, 0.32, 0.18), UiKit.UP, Color.WHITE, 8)
	UiKit.style_button(settings_button, UiKit.PANEL_2, Color(0.6, 0.82, 1.0, 0.8), Color(0.85, 0.92, 1.0), 8)
	UiKit.style_button(quit_button, UiKit.PANEL_2, UiKit.BORDER, UiKit.TEXT, 8)
