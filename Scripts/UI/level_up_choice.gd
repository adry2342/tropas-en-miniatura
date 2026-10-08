extends CanvasLayer
## Modal de ascenso (SPEC v2 §9): muestra las 2 ofertas pagadas de una tropa y obliga a elegir una.
## No se puede cerrar sin elegir: Esc y clic en el fondo se ignoran. Las ofertas siguen en
## card.pending_offers, así que si el submenú se cierra por otro motivo, al reabrirlo vuelve a salir.
## Botón 👁 (abajo): mientras se mantiene pulsado el menú se oculta para ver la ficha de la tropa;
## al soltarlo vuelve. Durante la elección (también al ocultarlo) no se puede hacer nada más:
## una capa invisible tapa toda la pantalla y GameStateManager.ui_blocking queda activo.

signal chosen(card: TroopCard, offer: Dictionary)

const CARD_W := 340.0
const CARD_H := 420.0

var card: TroopCard = null
var _busy: bool = false
var _prev_blocking: bool = false
var _root: Control
var _dim: ColorRect
var _title: Label
var _subtitle: Label
var _cards_box: HBoxContainer
var _card_w: float = CARD_W
var _cards: Array[PanelContainer] = []
var _center: CenterContainer
var _peek_blocker: ColorRect
var _eye_button: Button
var _peeking: bool = false
var _peek_by_mouse: bool = false


func _ready() -> void:
	layer = 30
	visible = false
	add_to_group("level_up_modal")
	_build_ui()
	EventBus.level_up_offers_ready.connect(open)


func is_open() -> bool:
	return visible and card != null


## Intento de cerrar sin elegir: nunca se permite mientras haya ofertas pendientes.
func try_close() -> bool:
	if is_open() and not card.pending_offers.is_empty():
		_shake()
		return false
	_hide_now()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		try_close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventMouseButton:
		# Nada de atajos ni clics sueltos mientras se elige (incluido el modo 👁)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Respaldo: si el botón se soltó fuera (o se perdió el evento), el menú vuelve igualmente
	if _peeking and _peek_by_mouse and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		set_peek(false)


func is_peeking() -> bool:
	return _peeking


## Oculta (true) o muestra (false) el menú de cartas sin cerrarlo. Mientras está oculto, una capa
## invisible sigue bloqueando cualquier clic: solo se puede mirar.
func set_peek(on: bool) -> void:
	if on and (not is_open() or _busy):
		return
	_peeking = on
	if not on:
		_peek_by_mouse = false
	_dim.visible = not on
	_center.visible = not on
	_peek_blocker.visible = on
	_eye_button.text = "👀  Suelta para volver a elegir" if on else "👀  Mantén pulsado para ver la tropa"
	_eye_button.modulate.a = 0.75 if on else 1.0
	# Mirando: el botón baja al borde para tapar lo mínimo de la ficha
	_eye_button.offset_top = -44.0 if on else -66.0
	_eye_button.offset_bottom = -4.0 if on else -18.0


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.025, 0.05, 0.86)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	_root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_center = center

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(v)

	_title = UiKit.label("", 30, UiKit.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 6)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	v.add_child(_title)
	_subtitle = UiKit.label("", 16, Color("#C8C8B8"))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gap)

	_cards_box = HBoxContainer.new()
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_box.add_theme_constant_override("separation", 44)
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_cards_box)

	# Capa invisible para el modo 👁: deja ver lo de detrás pero no tocarlo
	_peek_blocker = ColorRect.new()
	_peek_blocker.name = "PeekBlocker"
	_peek_blocker.color = Color(0, 0, 0, 0.0)
	_peek_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_peek_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_peek_blocker.visible = false
	_root.add_child(_peek_blocker)

	# Botón grande del ojo, abajo en el centro
	_eye_button = Button.new()
	_eye_button.name = "EyeButton"
	_eye_button.text = "👀  Mantén pulsado para ver la tropa"
	_eye_button.focus_mode = Control.FOCUS_NONE
	_eye_button.tooltip_text = "Mantén pulsado para ocultar las cartas y ver la ficha de la tropa. Al soltar vuelven."
	_eye_button.add_theme_font_size_override("font_size", 17)
	_eye_button.anchor_left = 0.5
	_eye_button.anchor_right = 0.5
	_eye_button.anchor_top = 1.0
	_eye_button.anchor_bottom = 1.0
	_eye_button.offset_left = -190.0
	_eye_button.offset_right = 190.0
	_eye_button.offset_top = -66.0
	_eye_button.offset_bottom = -18.0
	UiKit.style_button(_eye_button, Color(0.12, 0.14, 0.19, 0.95), UiKit.GOLD, Color(1.0, 0.93, 0.7), 24, 6)
	_eye_button.button_down.connect(func():
		_peek_by_mouse = true
		set_peek(true))
	_eye_button.button_up.connect(set_peek.bind(false))
	_root.add_child(_eye_button)


## Abre el modal con las ofertas pendientes de la tropa. Idempotente.
func open(target: TroopCard) -> void:
	if target == null or target.pending_offers.is_empty():
		return
	if is_open() and card == target and not _busy:
		return
	card = target
	_busy = false
	set_peek(false)
	# Ningún botón de detrás debe conservar el foco del teclado (Intro/Espacio no harían nada raro)
	var vp := get_viewport()
	if vp and vp.gui_get_focus_owner():
		vp.gui_release_focus()
	if not visible:
		_prev_blocking = GameStateManager.ui_blocking
	GameStateManager.ui_blocking = true
	visible = true
	_title.text = "¡%s sube a Nv. %d! Elige una" % [card.unit_name, card.level + 1]
	var spent: int = maxi(card.level, 1) # coste pagado al subir (Nv. actual → siguiente)
	if card.has_method("get_level_up_cost"):
		spent = int(card.get_level_up_cost())
	var gastaste := "Gastaste ⭐ %d" % spent
	if card.pending_offers.any(func(o): return String(o.get("type", "")) == "specialty"):
		_subtitle.text = "%s · deja de ser Recluta: elige su especialidad" % gastaste
	else:
		_subtitle.text = "%s · elige una mejora" % gastaste
	if card.pending_offers.size() > 2:
		_subtitle.text += "   ✨ ¡Suerte! Hoy hay una mejora extra para elegir"
	_rebuild_cards()
	_play_intro()


func _hide_now() -> void:
	set_peek(false)
	visible = false
	card = null
	_busy = false
	GameStateManager.ui_blocking = _prev_blocking


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		try_close()


# ---------------------------------------------------------------- cartas

func _rebuild_cards() -> void:
	for c in _cards_box.get_children():
		_cards_box.remove_child(c)
		c.queue_free()
	_cards.clear()
	# Con 3 ofertas (3.ª mejora por suerte) las cartas se estrechan para caber en 1152 px
	var three: bool = card.pending_offers.size() > 2
	_card_w = 316.0 if three else CARD_W
	_cards_box.add_theme_constant_override("separation", 22 if three else 44)
	for i in card.pending_offers.size():
		var pc := _make_card(card.pending_offers[i], i)
		_cards_box.add_child(pc)
		_cards.append(pc)


func _make_card(offer: Dictionary, index: int) -> PanelContainer:
	var type: String = String(offer.get("type", ""))
	var res: Resource = offer.get("resource")
	var info: Dictionary = UiKit.OFFER_TYPES.get(type, {"label": type.to_upper(), "color": Color.GRAY, "hint": ""})
	var type_color: Color = info.color
	var rarity: int = int(res.get("rarity")) if res and res.get("rarity") != null else 0
	var border_color: Color = UiKit.rarity_color(rarity)
	if type == "specialty" and res:
		border_color = (res as SpecialtyData).color
	elif type == "training":
		border_color = type_color

	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(_card_w, CARD_H)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := UiKit.style(Color(0.1, 0.11, 0.145), border_color, 14, 3, 16)
	sb.shadow_color = Color(border_color, 0.25)
	sb.shadow_size = 10
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_meta("style", sb)
	pc.set_meta("border", border_color)
	pc.set_meta("index", index)
	pc.resized.connect(func(): pc.pivot_offset = pc.size * 0.5)
	pc.mouse_entered.connect(_on_card_hover.bind(pc, true))
	pc.mouse_exited.connect(_on_card_hover.bind(pc, false))
	pc.gui_input.connect(_on_card_input.bind(pc))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)

	# Etiqueta de tipo + aclaración (hueco)
	var top := HBoxContainer.new()
	v.add_child(top)
	var pill := UiKit.panel(type_color, Color(0, 0, 0, 0), 10, 0, 0)
	pill.get_theme_stylebox("panel").content_margin_left = 10
	pill.get_theme_stylebox("panel").content_margin_right = 10
	pill.get_theme_stylebox("panel").content_margin_top = 2
	pill.get_theme_stylebox("panel").content_margin_bottom = 2
	pill.add_child(UiKit.label(info.label, 12, Color.WHITE))
	top.add_child(pill)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UiKit.label(info.hint, 12, type_color.lightened(0.35)))

	# Emoji grande
	var emoji_txt := "🎯" if type == "training" else (UiKit.emo(String(res.get("emoji"))) if res else "?")
	if res is WeaponData:
		v.add_child(UiKit.icon_rect(res.get_icon(), 84))
	else:
		var emoji := UiKit.label(emoji_txt, 60, Color.WHITE)
		emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(emoji)

	var name_txt := "Entrenamiento" if type == "training" else (String(res.get("display_name")) if res else "?")
	var name_l := UiKit.label(name_txt, 24, border_color.lightened(0.15))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	if type != "specialty" and type != "training":
		var rl := UiKit.label(UiKit.rarity_name(rarity), 12, UiKit.rarity_color(rarity))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rl)

	var desc_txt := "Instrucción intensiva: +%d %% de vida y de daño. Se acumula con cada entrenamiento." % roundi(Economy.TRAINING_BONUS * 100.0) if type == "training" else (String(res.get("description")) if res else "")
	var desc := UiKit.wrap_label(desc_txt, 13, UiKit.TEXT.darkened(0.12))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(desc)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 3)
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(details)
	var dpanel := UiKit.panel(Color(0.065, 0.075, 0.1), Color(0, 0, 0, 0), 8, 0, 10)
	details.add_child(dpanel)
	dpanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 3)
	dpanel.add_child(dv)
	match type:
		"specialty":
			_details_specialty(dv, res as SpecialtyData)
		"skill":
			_details_mods(dv, res.get("modifiers"), "Efecto")
			var sk := res as SkillData
			if sk.stackable:
				dv.add_child(UiKit.label("♻ Acumulable", 12, UiKit.MUTED))
			dv.add_child(UiKit.label("✓ Pasiva permanente · no ocupa hueco", 12, type_color.lightened(0.3)))
		"item":
			var it := res as ItemData
			dv.add_child(UiKit.label("Hueco: %s · %d/%d ocupados" % [it.get_slot_name(), card.items.size(), TroopCard.MAX_ITEM_SLOTS], 12, type_color.lightened(0.3)))
			_details_mods(dv, it.modifiers, "Efecto")
		"weapon":
			_details_weapon(dv, res as WeaponData)
		"training":
			dv.add_child(UiKit.label("❤ +%d %% de vida máxima" % roundi(Economy.TRAINING_BONUS * 100.0), 12, UiKit.HEALTH))
			dv.add_child(UiKit.label("💥 +%d %% de daño" % roundi(Economy.TRAINING_BONUS * 100.0), 12, UiKit.DAMAGE))
			dv.add_child(UiKit.label("Rangos actuales: %d → %d" % [card.training_ranks, card.training_ranks + 1], 12, type_color.lightened(0.3)))
			dv.add_child(UiKit.label("♻ Acumulable sin límite", 12, UiKit.MUTED))

	var choose := UiKit.panel(Color(type_color, 0.22), Color(type_color, 0.8), 8, 1, 6)
	var cl := UiKit.label("ELEGIR", 15, Color.WHITE)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choose.add_child(cl)
	v.add_child(choose)

	_ignore_mouse(v)
	return pc


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _details_mods(box: VBoxContainer, mods, title: String) -> void:
	if mods is Dictionary and not (mods as Dictionary).is_empty():
		box.add_child(UiKit.wrap_label("%s: %s" % [title, TroopStats.describe_modifiers(mods)], 12, UiKit.TEXT))


func _details_specialty(box: VBoxContainer, sp: SpecialtyData) -> void:
	var fams: Array[String] = []
	for f in sp.affine_families:
		fams.append(WeaponData.FAMILY_NAMES[clampi(int(f), 0, WeaponData.FAMILY_NAMES.size() - 1)])
	box.add_child(UiKit.wrap_label("⚔ Armas afines: %s" % ", ".join(fams), 12, UiKit.TEXT))
	var cur := card.get_weapon()
	if cur:
		var ok := sp.is_affine(cur)
		box.add_child(UiKit.wrap_label(("✓ Su %s es afín: +15 %% daño y +10 de precisión" if ok else "✗ Su %s no es afín") % cur.display_name, 12, UiKit.UP if ok else UiKit.MUTED))
	box.add_child(UiKit.label("✦ %s" % sp.passive_name, 13, sp.color.lightened(0.2)))
	box.add_child(UiKit.wrap_label(sp.passive_description, 12, UiKit.MUTED))
	if sp.synergy_text != "":
		box.add_child(UiKit.wrap_label("🤝 %s" % sp.synergy_text, 12, Color(0.75, 0.9, 1.0)))


func _details_weapon(box: VBoxContainer, w: WeaponData) -> void:
	var cur: WeaponData = card.get_weapon()
	var aff := card.specialty != null and card.specialty.is_affine(w)
	box.add_child(UiKit.label("%s%s" % [w.get_family_name(), "  ·  ✓ afín" if aff else ""], 12, UiKit.UP if aff else UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	box.add_child(grid)
	var rows := [
		["Daño", w.damage * w.pellets, cur.damage * cur.pellets if cur else 0.0, ("%d×%d" % [w.pellets, roundi(w.damage)]) if w.pellets > 1 else "%d" % roundi(w.damage), true],
		["Cadencia", w.fire_rate, cur.fire_rate if cur else 0.0, "%.1f/s" % w.fire_rate, true],
		["Alcance", w.attack_range, cur.attack_range if cur else 0.0, "%d" % roundi(w.attack_range), true],
		["Precisión", w.accuracy, cur.accuracy if cur else 0.0, UiKit.pct(w.accuracy), true],
		["Cargador", 9999.0 if w.magazine <= 0 else float(w.magazine), (9999.0 if cur.magazine <= 0 else float(cur.magazine)) if cur else 0.0, UiKit.magazine_text(w.magazine), true],
	]
	for r in rows:
		grid.add_child(UiKit.label(r[0], 12, UiKit.MUTED))
		var val := UiKit.label(r[3], 12, UiKit.TEXT)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
		var arrow := "="
		var col := UiKit.MUTED
		if cur:
			var a: float = r[1]
			var b: float = r[2]
			if a > b + 0.0001:
				arrow = "↑"
				col = UiKit.UP
			elif a < b - 0.0001:
				arrow = "↓"
				col = UiKit.DOWN
		grid.add_child(UiKit.label(arrow, 13, col))
	if cur:
		box.add_child(UiKit.icon_label(cur.get_icon(), "Comparado con su %s" % cur.display_name, 11, UiKit.MUTED))


# ---------------------------------------------------------------- interacción y animación

func _on_card_hover(pc: PanelContainer, on: bool) -> void:
	if _busy or not is_instance_valid(pc):
		return
	var tw := pc.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pc, "scale", Vector2.ONE * (1.05 if on else 1.0), 0.12)
	var sb: StyleBoxFlat = pc.get_meta("style")
	var base: Color = pc.get_meta("border")
	sb.border_color = base.lightened(0.35) if on else base
	sb.shadow_size = 22 if on else 10
	sb.shadow_color = Color(base, 0.45 if on else 0.25)


func _on_card_input(event: InputEvent, pc: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		choose_offer(int(pc.get_meta("index")))


## Elige la oferta `index`: aplica, sube de nivel, anima y cierra.
func choose_offer(index: int) -> bool:
	if _busy or _peeking or not is_open() or index < 0 or index >= card.pending_offers.size():
		return false
	_busy = true
	var target := card
	var offer: Dictionary = card.pending_offers[index]
	var equip := String(offer.get("type", "")) == "weapon" and target.specialty == null
	LevelUpSystem.choose(target, index, equip)
	chosen.emit(target, offer)
	_play_outro(index)
	return true


func _play_intro() -> void:
	_dim.modulate.a = 0.0
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.2)
	tw.tween_property(_title, "modulate:a", 1.0, 0.3).set_delay(0.05)
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.3).set_delay(0.12)
	for i in _cards.size():
		var pc := _cards[i]
		pc.modulate.a = 0.0
		pc.scale = Vector2.ONE * 0.75
		tw.tween_property(pc, "modulate:a", 1.0, 0.25).set_delay(0.1 + i * 0.1)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.4).set_delay(0.1 + i * 0.1) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_outro(index: int) -> void:
	var tw := create_tween().set_parallel(true)
	for i in _cards.size():
		var pc := _cards[i]
		if i == index:
			tw.tween_property(pc, "scale", Vector2.ONE * 1.12, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pc.modulate = Color(1.6, 1.6, 1.6, 1.0)
			tw.tween_property(pc, "modulate", Color.WHITE, 0.35)
		else:
			tw.tween_property(pc, "modulate:a", 0.15, 0.25)
			tw.tween_property(pc, "scale", Vector2.ONE * 0.9, 0.25)
	tw.chain().tween_interval(0.25)
	tw.chain().tween_property(_root, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func():
		_root.modulate.a = 1.0
		_hide_now())


func _shake() -> void:
	if _cards_box == null:
		return
	var tw := create_tween()
	var base := _title.position
	for k in [8.0, -8.0, 5.0, -5.0, 0.0]:
		tw.tween_property(_title, "position:x", base.x + k, 0.04)
