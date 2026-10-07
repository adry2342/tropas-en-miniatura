extends CanvasLayer

@onready var title_label: Label = $Control/Panel/VBoxContainer/TitleLabel
@onready var card_container: HBoxContainer = $Control/Panel/VBoxContainer/CardContainer
@onready var next_battle_button: Button = $Control/Panel/VBoxContainer/ButtonsContainer/NextBattleButton
@onready var main_menu_button: Button = $Control/Panel/VBoxContainer/ButtonsContainer/MainMenuButton


func _ready() -> void:
	var panel: Panel = $Control/Panel
	panel.add_theme_stylebox_override("panel", UiKit.style(UiKit.BG, UiKit.GOLD, 12, 2, 0))
	title_label.add_theme_color_override("font_color", UiKit.GOLD)
	UiKit.style_button(next_battle_button, Color(0.18, 0.32, 0.18), UiKit.UP, Color.WHITE, 8)
	UiKit.style_button(main_menu_button, UiKit.PANEL_2, UiKit.BORDER)
	next_battle_button.text = "Siguiente ronda ▶"
	next_battle_button.disabled = false
	next_battle_button.pressed.connect(_on_next_battle_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	_display_round_summary()


func _display_round_summary() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	var stage = gsm.current_stage if gsm else 1

	if title_label:
		title_label.text = "¡VICTORIA EN LA RONDA %d!" % stage

	for child in card_container.get_children():
		child.queue_free()

	# Panel con resumen de la ronda
	var info_box = PanelContainer.new()
	info_box.custom_minimum_size = Vector2(460, 200)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# Leer el resumen de la ronda desde GSM
	var summary: Dictionary = gsm.last_round_summary if gsm else {}

	var kills: int = summary.get("kills", 0)
	var kill_coins: int = summary.get("kill_coins", 0)
	var win_coins: int = summary.get("win_coins", 0)
	var interest: int = summary.get("interest", 0)
	var gained: int = kill_coins + win_coins + interest

	# Monedas ganadas: solo la cifra; el desglose está en el botón ⓘ (pasar el ratón o pulsar)
	var coins_row := HBoxContainer.new()
	coins_row.name = "CoinsRow"
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coins_row.add_theme_constant_override("separation", 8)
	var gained_label := UiKit.label("💰 +%d monedas" % gained, 22, UiKit.GOLD)
	gained_label.name = "CoinsGained"
	coins_row.add_child(gained_label)
	var breakdown_text := "De dónde salen:\n☠️ Bajas: %d → +%d 💰\n🏁 Victoria: +%d 💰" % [kills, kill_coins, win_coins]
	if interest > 0:
		breakdown_text += "\n📈 Interés (+1 por cada %d ahorradas, máx. %d): +%d 💰" % [Economy.INTEREST_STEP, Economy.INTEREST_MAX, interest]
	var info_btn := Button.new()
	info_btn.name = "CoinsInfoButton"
	info_btn.text = "ⓘ"
	info_btn.tooltip_text = breakdown_text
	info_btn.focus_mode = Control.FOCUS_NONE
	info_btn.custom_minimum_size = Vector2(30, 30)
	info_btn.add_theme_font_size_override("font_size", 16)
	UiKit.style_button(info_btn, UiKit.PANEL_2, UiKit.GOLD, UiKit.GOLD, 15)
	coins_row.add_child(info_btn)
	vbox.add_child(coins_row)

	# Desglose (oculto hasta pulsar ⓘ)
	var breakdown := VBoxContainer.new()
	breakdown.name = "CoinsBreakdown"
	breakdown.visible = false
	breakdown.add_theme_constant_override("separation", 2)
	var lines: Array[String] = ["☠️ Bajas: %d → +%d 💰" % [kills, kill_coins], "🏁 Victoria +%d 💰" % win_coins]
	if interest > 0:
		lines.append("📈 Interés +%d 💰" % interest)
	for t in lines:
		var l := UiKit.label(t, 14, Color("#C8C8B8"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		breakdown.add_child(l)
	vbox.add_child(breakdown)
	info_btn.pressed.connect(func(): breakdown.visible = not breakdown.visible)

	# Puntos de Mando
	var points: int = summary.get("points", 0)
	var clean: bool = summary.get("clean", false)
	var points_label := UiKit.label("⭐ +%d Puntos de Mando%s" % [points, "  (✨ victoria limpia +%d)" % Economy.CLEAN_WIN_BONUS_POINTS if clean and Economy.CLEAN_WIN_BONUS_POINTS > 0 else ""], 16, Color(0.6, 0.82, 1.0))
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(points_label)

	# Línea 6: Totales (destacados: cifras grandes con icono)
	var total_coins: int = summary.get("coins_total", 0)
	var total_points: int = summary.get("points_total", 0)
	var totals := HBoxContainer.new()
	totals.name = "TotalsRow"
	totals.alignment = BoxContainer.ALIGNMENT_CENTER
	totals.add_theme_constant_override("separation", 18)
	totals.add_child(_big_chip("💰", total_coins, "Monedas", UiKit.GOLD,
			"💰 Monedas: se ganan por cada baja enemiga y al vencer. Compran equipo y reclutas en la Intendencia."))
	totals.add_child(_big_chip("⭐", total_points, "Puntos de Mando", Color(0.6, 0.82, 1.0),
			"⭐ Puntos de Mando: se ganan al vencer una ronda. Suben de nivel a tus tropas (panel de la tropa)."))
	vbox.add_child(totals)
	var legend = Label.new()
	legend.text = "💰 compra equipo · ⭐ sube de nivel"
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 14)
	legend.add_theme_color_override("font_color", Color("#C8C8B8"))
	vbox.add_child(legend)

	# Separador y probabilidad de jefe
	var separator = HSeparator.new()
	vbox.add_child(separator)

	var boss_label = Label.new()
	var next_chance: float = gsm.next_boss_chance() if gsm else 0.0
	if gsm and gsm.is_subboss_round(stage + 1):
		boss_label.text = "⚔️ Siguiente ronda: JEFE DE SECTOR (❤ %d de vida)" % roundi(Economy.subboss_hp(stage + 1))
	elif next_chance <= 0.0 and gsm and gsm.get("BOSS_MIN_ROUND") != null:
		boss_label.text = "☠️ Sin riesgo de jefe hasta la ronda %d" % int(gsm.get("BOSS_MIN_ROUND"))
	else:
		boss_label.text = "☠️ Probabilidad de jefe en la siguiente ronda: %s" % load("res://Scripts/Map/map.gd").pct_text(next_chance)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 13)
	boss_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	vbox.add_child(boss_label)

	vbox.add_theme_constant_override("separation", 6)
	info_box.add_child(vbox)
	card_container.add_child(info_box)


func _on_next_battle_pressed() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.advance_stage()
	get_tree().change_scene_to_file("res://Scenes/Map/map.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/UI/main_menu.tscn")


## Ficha de total: icono + cifra grande + etiqueta pequeña.
func _big_chip(icon: String, value: int, caption: String, color: Color, tip: String) -> PanelContainer:
	var chip := UiKit.panel(Color(color.r * 0.16, color.g * 0.16, color.b * 0.16), Color(color, 0.6), 10, 1, 10)
	chip.custom_minimum_size = Vector2(190, 0)
	chip.tooltip_text = tip
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(v)
	var big := UiKit.label("%s %d" % [icon, value], 34, color)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	var cap := UiKit.label(caption, 13, Color("#C8C8B8"))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	return chip
