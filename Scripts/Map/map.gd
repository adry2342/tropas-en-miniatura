extends Control
## Pantalla entre rondas (rondas infinitas).
## Muestra la ronda actual y gira la ruleta del jefe: cada ronda ganada suma +2% de que
## salga el jefe. Si sale, la siguiente ronda es contra el jefe (derrotarlo gana la partida).

const BATTLE_SCENE_PATH = "res://Scenes/Battle/battle.tscn"
const TRACK_WIDTH: float = 560.0
const SPIN_TIME: float = 2.4
const SAFE_COLOR := Color(0.1, 0.11, 0.09) # fondo vacío de la barra
const BOSS_COLOR := Color(0.72, 0.16, 0.12) # rojo apagado
const CREAM := Color(0.96, 0.92, 0.78)
const GOLD_COLOR := Color(1.0, 0.85, 0.2)

var _round_label: Label
var _chance_label: Label
var _track: ColorRect
var _track_holder: Control
var _boss_zone: ColorRect
var _needle: ColorRect
var _result_label: Label
var _fight_button: Button
var _stats_label: Label
var _spin_tween: Tween
var _target_x: float = 0.0
var _result_type: String = ""


func _ready() -> void:
	_build_ui()
	_start_round()


func _gsm() -> Node:
	return get_node_or_null("/root/GameStateManager")


func _start_round() -> void:
	var gsm = _gsm()
	var round_number: int = gsm.current_stage if gsm else 1
	var chance: float = gsm.boss_chance if gsm else 0.0
	var already_rolled: bool = gsm != null and gsm.rolled_round == round_number
	
	_round_label.text = "RONDA %d" % round_number
	var min_round = gsm.get("BOSS_MIN_ROUND") if gsm else null
	var no_risk: bool = min_round != null and round_number < int(min_round)
	if no_risk:
		chance = 0.0
		_chance_label.text = "☠️ Sin riesgo de jefe final hasta la ronda %d" % int(min_round)
	else:
		_chance_label.text = "☠️ Riesgo de jefe: %s" % pct_text(chance)
	# Jefe de Sector fijo cada 10 rondas: se avisa siempre de cuándo llega el próximo
	if gsm and gsm.has_method("is_subboss_round"):
		var every: int = int(gsm.SUBBOSS_EVERY)
		var next_sub: int = int(ceil(float(round_number) / every)) * every
		_chance_label.text += "   ·   ⚔️ Jefe de Sector: ronda %d (❤ %d)" % [next_sub, roundi(Economy.subboss_hp(next_sub))]
	_stats_label.text = "💰 Monedas: %d   ·   ⭐ Puntos de Mando: %d\n🏆 Victorias: %d   ·   🎖️ Tropas: %d/%d" % [
		gsm.coins if gsm else 0, gsm.command_points if gsm else 0, gsm.wins_count if gsm else 0,
		_army_count(), gsm.MAX_ARMY_SIZE if gsm else 6]
	
	# La barra de la ruleta no aparece hasta que el jefe final puede salir (tras ganar la ronda 10)
	_track_holder.visible = not no_risk
	_boss_zone.size = Vector2(TRACK_WIDTH * chance, _track.size.y)
	_boss_zone.position = Vector2.ZERO
	_boss_zone.visible = chance > 0.0
	_needle.visible = chance > 0.0 # sin riesgo no hay marcador que interpretar
	
	var pm := get_node_or_null("/root/ProfileManager")
	var unlocks_before: int = pm.recent_unlocks.size() if pm and "recent_unlocks" in pm else 0
	_result_type = gsm.roll_round_type() if gsm else "Batalla Normal"
	if pm and "recent_unlocks" in pm and pm.recent_unlocks.size() > unlocks_before:
		_show_unlock_banner(pm.recent_unlocks.slice(unlocks_before))
	var is_boss: bool = _result_type == "Jefe Final"
	if _result_type == "Jefe de Sector":
		chance = 0.0 # la ronda del Jefe de Sector no gira la ruleta
		_boss_zone.visible = false
		_needle.visible = false
	
	# Punto donde se detendrá la aguja: dentro de la zona del jefe o fuera de ella
	var boss_w: float = _boss_zone.size.x
	if is_boss:
		_target_x = randf_range(0.15, 0.85) * maxf(boss_w, 2.0)
	else:
		_target_x = randf_range(boss_w + 6.0, TRACK_WIDTH - 6.0)
	
	if chance <= 0.0 or already_rolled:
		# Primera ronda (0%) o ruleta ya girada: se muestra el resultado directamente
		_place_needle(_target_x)
		_show_result()
	else:
		_spin()


func _army_count() -> int:
	var gsm = _gsm()
	if gsm == null:
		return 0
	var n: int = gsm.deployed_troops_data.size()
	for res in gsm.player_bench:
		if res is TroopCard:
			n += 1
	return n


func _spin() -> void:
	_fight_button.disabled = true
	_fight_button.text = "⏳ Girando…"
	_result_label.text = "Girando la ruleta..."
	_result_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	# La aguja recorre la barra de ida y vuelta varias veces y frena hasta el resultado
	var total: float = TRACK_WIDTH * 4.0 + _target_x
	_spin_tween = create_tween()
	_spin_tween.tween_method(_on_spin_step, 0.0, total, SPIN_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_spin_tween.tween_callback(_show_result)


func _on_spin_step(distance: float) -> void:
	var period: float = TRACK_WIDTH * 2.0
	var p: float = fmod(distance, period)
	_place_needle(p if p <= TRACK_WIDTH else period - p)


func _place_needle(x: float) -> void:
	_needle.position.x = clampf(x, 0.0, TRACK_WIDTH) - _needle.size.x * 0.5


## Termina la ruleta al instante (usado al pulsar sobre ella y en los tests).
func skip_spin() -> void:
	if _spin_tween and _spin_tween.is_running():
		_spin_tween.kill()
		_place_needle(_target_x)
		_show_result()


func _show_result() -> void:
	_fight_button.disabled = false
	match _result_type:
		"Jefe Final":
			_result_label.text = "☠️ ¡HA SALIDO EL JEFE! ☠️\nDerrótalo para ganar la partida"
			_result_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
			_fight_button.text = "☠️ ¡LUCHAR CONTRA EL JEFE!"
			_flash(BOSS_COLOR)
		"Jefe de Sector":
			_result_label.text = "⚔️ ¡JEFE DE SECTOR! ⚔️\nComandante con ❤ %d de vida y escoltas" % roundi(Economy.subboss_hp(_gsm().current_stage if _gsm() else 10))
			_result_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
			_fight_button.text = "⚔️ ¡ASALTAR EL SECTOR!"
			_flash(Color(1.0, 0.55, 0.2))
		"Batalla Élite":
			_result_label.text = "⚔️ Batalla Élite\nEnemigos más duros y mejor recompensa"
			_result_label.add_theme_color_override("font_color", Color(0.75, 0.5, 1.0))
			_fight_button.text = "⚔️ ¡A LUCHAR!"
		_:
			_result_label.text = "⚔️ Batalla Normal"
			_result_label.add_theme_color_override("font_color", Color(0.8, 0.88, 0.5))
			_fight_button.text = "⚔️ ¡A LUCHAR!"


func _flash(color: Color) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(color, 0.35)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var t := overlay.create_tween()
	t.tween_property(overlay, "color:a", 0.0, 0.8)
	t.tween_callback(overlay.queue_free)


func _on_fight_pressed() -> void:
	print("Iniciando ronda %d: %s" % [_gsm().current_stage if _gsm() else 1, _result_type])
	get_tree().change_scene_to_file(BATTLE_SCENE_PATH)


func _on_track_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		skip_spin()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.16, 0.21)
	style.border_color = GOLD_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	
	_round_label = _label("", 38, GOLD_COLOR)
	box.add_child(_round_label)
	_chance_label = _label("", 17, Color(1.0, 0.55, 0.5))
	box.add_child(_chance_label)
	
	# Ruleta: barra verde (combate normal) con la zona roja del jefe a la derecha
	var track_holder := CenterContainer.new()
	track_holder.name = "TrackHolder"
	_track_holder = track_holder
	box.add_child(track_holder)
	_track = ColorRect.new()
	_track.custom_minimum_size = Vector2(TRACK_WIDTH, 46)
	_track.size = _track.custom_minimum_size
	_track.color = SAFE_COLOR
	_track.mouse_filter = Control.MOUSE_FILTER_STOP
	_track.gui_input.connect(_on_track_input)
	track_holder.add_child(_track)
	
	_boss_zone = ColorRect.new()
	_boss_zone.color = BOSS_COLOR
	_boss_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_boss_zone)
	var skull := _label("☠️", 18, Color.WHITE)
	skull.set_anchors_preset(Control.PRESET_FULL_RECT)
	skull.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skull.clip_text = true
	_boss_zone.add_child(skull)
	
	_needle = ColorRect.new()
	_needle.color = Color.WHITE
	_needle.size = Vector2(4, 62)
	_needle.position = Vector2(0, -8)
	_needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_needle)
	
	_result_label = _label("", 22, Color.WHITE)
	_result_label.custom_minimum_size = Vector2(0, 64)
	box.add_child(_result_label)
	
	_fight_button = Button.new()
	_fight_button.custom_minimum_size = Vector2(320, 54)
	_fight_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fight_button.add_theme_font_size_override("font_size", 20)
	UiKit.style_button(_fight_button, Color(0.32, 0.36, 0.14), Color(0.78, 0.7, 0.44), Color.WHITE, 8)
	_fight_button.pressed.connect(_on_fight_pressed)
	box.add_child(_fight_button)
	
	_stats_label = _label("", 16, CREAM)
	_stats_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_label.tooltip_text = "💰 Monedas: se ganan por cada baja enemiga y al vencer. Compran equipo y reclutas en la Intendencia.\n⭐ Puntos de Mando: se ganan al vencer una ronda. Suben de nivel a tus tropas (panel de la tropa)."
	box.add_child(_stats_label)


## v7.1: aviso de especialidad desbloqueada al llegar a un Jefe de Sector.
func _show_unlock_banner(specs: Array) -> void:
	var names: Array[String] = []
	for sp in specs:
		names.append("%s %s" % [UiKit.emo(sp.emoji), sp.display_name])
	var l := UiKit.label("🔓 %s: lista para desbloquear en el Centro de mando al terminar la partida" % ", ".join(names), 22, UiKit.GOLD)
	l.name = "UnlockBanner"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.offset_left = -500
	l.offset_right = 500
	l.offset_top = 14
	l.offset_bottom = 50
	add_child(l)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## "0,5 %", "3 %", "12,5 %": con un decimal solo si hace falta.
static func pct_text(p: float) -> String:
	var v: float = p * 100.0
	if absf(v - roundf(v)) < 0.05:
		return "%d%%" % roundi(v)
	return ("%.1f%%" % v).replace(".", ",")
