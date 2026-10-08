extends CanvasLayer
## Intendencia (SPEC v3 §7): tienda de la fase de planificación con dos pestañas.
## - Equipo: 4 ofertas de objetos/armas por ronda (ShopSystem), renovar con precio creciente y
##   venta de lo que haya suelto en el inventario.
## - Reclutas: 3 reclutas únicos (UnitFactory.make_recruit) guardados en GameStateManager.shop_offers.
## Se abre con EventBus.shop_requested(tab) o recruit_shop_requested (→ reclutas); se cierra con Esc,
## al pulsar fuera, al empezar el combate o al llenar el ejército comprando un recluta.

const OFFER_COUNT := 3 # reclutas por ronda
const CARD_W := 238.0  # ancho de la ficha de recluta
const EQUIP_W := 246.0 # ancho de la carta de equipo
const TAB_EQUIPO := "equipo"
const TAB_RECLUTAS := "reclutas"
const SOFT := Color("#C8C8B8") # gris claro para tipo/hueco/descripciones
const TIP_COINS := "💰 Monedas: se ganan por cada baja enemiga y al vencer. Compran equipo y reclutas en la Intendencia."
const TIP_POINTS := "⭐ Puntos de Mando: se ganan al vencer una ronda. Suben de nivel a tus tropas (panel de la tropa)."
const SLOT_EMOJI := ["🔶", "🛡️", "🔧"] # Munición, Armadura, Utilidad

var _tab: String = TAB_EQUIPO
var _offers_box: HBoxContainer      # reclutas
var _equip_box: HBoxContainer       # ofertas de equipo
var _inv_box: HBoxContainer         # inventario (vender)
var _inv_empty: Label
var _equip_page: VBoxContainer
var _recruit_page: VBoxContainer
var _coins_label: Label
var _points_label: Label
var _slots_label: Label
var _reroll_btn: Button
var _tab_buttons: Dictionary = {}   # String -> Button
var _buy_buttons: Dictionary = {}   # TroopCard -> Button (reclutas)
var _equip_buttons: Array = []      # Button por oferta de equipo (índice = oferta)


func _ready() -> void:
	layer = 25
	visible = false
	_build_ui()
	EventBus.shop_requested.connect(open)
	EventBus.recruit_shop_requested.connect(func(): open(TAB_RECLUTAS))
	EventBus.roster_changed.connect(_refresh)
	EventBus.shop_changed.connect(_refresh)
	EventBus.battle_fight_started.connect(close)


func _exit_tree() -> void:
	if visible:
		_set_blocking(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open(tab: String = TAB_EQUIPO) -> void:
	_tab = TAB_RECLUTAS if tab == TAB_RECLUTAS else TAB_EQUIPO
	ensure_offers()
	ShopSystem.ensure_offers()
	visible = true
	_set_blocking(true)
	_rebuild_all()
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	_set_blocking(false)


func current_tab() -> String:
	return _tab


func _set_blocking(value: bool) -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.ui_blocking = value


func _set_tab(tab: String) -> void:
	_tab = tab
	_refresh()


## Genera los reclutas de la ronda si aún no existen.
func ensure_offers() -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm == null:
		return
	if gsm.shop_offers.is_empty():
		for i in OFFER_COUNT:
			gsm.shop_offers.append(UnitFactory.make_recruit(null, true))


## Reclutas que aún se pueden comprar.
func get_offers() -> Array[TroopCard]:
	var out: Array[TroopCard] = []
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm:
		for o in gsm.shop_offers:
			if o is TroopCard:
				out.append(o)
	return out


## Compra un recluta. Devuelve true si se ha reclutado.
func buy(card: TroopCard) -> bool:
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm == null or card == null:
		return false
	var idx: int = gsm.shop_offers.find(card)
	if idx < 0:
		return false
	if not gsm.recruit_troop(card, Economy.recruit_price(card)):
		return false
	gsm.shop_offers[idx] = null # la oferta desaparece (hueco "Reclutado")
	_rebuild_recruits()
	_refresh()
	if not gsm.has_free_army_slot():
		close()
	return true


## Compra la oferta de equipo `index` (delegado en ShopSystem).
func buy_equipment(index: int) -> bool:
	var ok := ShopSystem.buy_equipment(index)
	if ok:
		_refresh()
	return ok


func reroll() -> bool:
	var ok := ShopSystem.reroll()
	if ok:
		_refresh()
	return ok


func sell(res: Resource) -> int:
	return ShopSystem.sell(res)


# ---------------------------------------------------------------- refresco

func _refresh() -> void:
	if not visible:
		return
	var gsm = get_node_or_null("/root/GameStateManager")
	var coins: int = gsm.coins if gsm else 0
	_coins_label.text = "💰 %d" % coins
	_points_label.text = "⭐ %d PM" % (gsm.command_points if gsm else 0)
	_equip_page.visible = _tab == TAB_EQUIPO
	_recruit_page.visible = _tab == TAB_RECLUTAS
	for t in _tab_buttons:
		_style_tab(_tab_buttons[t], t == _tab)
	if _tab == TAB_EQUIPO:
		_rebuild_equipment(coins)
	else:
		_refresh_recruits(coins)


func _refresh_recruits(coins: int) -> void:
	var gsm = get_node_or_null("/root/GameStateManager")
	var free_slots: int = (gsm.MAX_ARMY_SIZE - gsm.get_army_size()) if gsm else 0
	_slots_label.text = "Huecos libres en el ejército: %d de %d" % [maxi(free_slots, 0), gsm.MAX_ARMY_SIZE if gsm else 6]
	for c in _buy_buttons:
		if not is_instance_valid(_buy_buttons[c]):
			continue
		var btn: Button = _buy_buttons[c]
		var price := Economy.recruit_price(c)
		var affordable: bool = coins >= price
		btn.disabled = not affordable or free_slots <= 0
		if free_slots <= 0:
			btn.text = "Ejército lleno"
		elif not affordable:
			btn.text = "Faltan %d 💰" % (price - coins)
		else:
			btn.text = "Reclutar · %d 💰" % price
		var extra := Economy.recruit_extras_surcharge(c)
		btn.tooltip_text = ("Precio base %d 💰 + %d 💰 por lo que trae de serie" % [price - extra, extra]) if extra > 0 else ""



func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


# ---------------------------------------------------------------- UI base

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := UiKit.panel(UiKit.BG, UiKit.GOLD, 12, 2, 16)
	panel.name = "ShopPanel"
	panel.custom_minimum_size = Vector2(1080, 600)
	center.add_child(panel)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	panel.add_child(main)

	# Cabecera: título, monedas, puntos de mando y cerrar
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	main.add_child(header)
	var title := UiKit.label("🏪 INTENDENCIA", 26, UiKit.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_coins_label = UiKit.label("", 21, UiKit.GOLD)
	header.add_child(_resource_chip(_coins_label, UiKit.GOLD, TIP_COINS))
	_points_label = UiKit.label("", 16, Color(0.55, 0.8, 1.0, 0.7))
	header.add_child(_resource_chip(_points_label, Color(0.55, 0.8, 1.0, 0.6), TIP_POINTS))
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(40, 38)
	UiKit.style_button(close_btn, UiKit.PANEL_2, UiKit.BORDER)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Pestañas
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	main.add_child(tabs)
	for pair in [[TAB_EQUIPO, "🎒 Equipo"], [TAB_RECLUTAS, "🎖️ Reclutas"]]:
		var tb := Button.new()
		tb.text = pair[1]
		tb.custom_minimum_size = Vector2(150, 36)
		tb.add_theme_font_size_override("font_size", 16)
		var key: String = pair[0]
		tb.pressed.connect(func(): _set_tab(key))
		tabs.add_child(tb)
		_tab_buttons[key] = tb

	_equip_page = VBoxContainer.new()
	_equip_page.add_theme_constant_override("separation", 10)
	main.add_child(_equip_page)
	_build_equipment_page()

	_recruit_page = VBoxContainer.new()
	_recruit_page.add_theme_constant_override("separation", 10)
	main.add_child(_recruit_page)
	_build_recruit_page()


func _resource_chip(lbl: Label, color: Color, tip: String = "") -> PanelContainer:
	var chip := UiKit.panel(Color(color.r * 0.16, color.g * 0.16, color.b * 0.16), Color(color, 0.5), 8, 1, 6)
	chip.custom_minimum_size = Vector2(96, 0)
	chip.tooltip_text = tip
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(lbl)
	return chip


func _style_tab(btn: Button, active: bool) -> void:
	if active:
		UiKit.style_button(btn, Color(0.34, 0.27, 0.07), UiKit.GOLD, Color(1.0, 0.93, 0.65), 8, 6)
	else:
		UiKit.style_button(btn, UiKit.PANEL, UiKit.BORDER, UiKit.MUTED, 8, 6)


# ---------------------------------------------------------------- pestaña Equipo

func _build_equipment_page() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_equip_page.add_child(top)
	var hint := UiKit.label("Ofertas de la ronda: equipo para tus tropas. Renovar cuesta más con cada uso esta ronda.", 13, UiKit.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(hint)
	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(280, 38)
	_reroll_btn.add_theme_font_size_override("font_size", 16)
	UiKit.style_button(_reroll_btn, Color(0.12, 0.26, 0.4), Color(0.4, 0.7, 1.0), Color(0.85, 0.94, 1.0), 8, 6)
	_reroll_btn.pressed.connect(func(): reroll())
	_reroll_btn.tooltip_text = "Cambia las 4 ofertas. El coste sube con cada uso esta ronda."
	top.add_child(_reroll_btn)

	_equip_box = HBoxContainer.new()
	_equip_box.add_theme_constant_override("separation", 12)
	_equip_page.add_child(_equip_box)

	var inv_title := UiKit.label("🎒 INVENTARIO  ·  objetos y armas sueltos (equípalos desde el panel de la tropa)", 14, UiKit.MUTED)
	_equip_page.add_child(inv_title)
	var inv_panel := UiKit.panel(UiKit.PANEL, UiKit.BORDER, 10, 1, 8)
	inv_panel.custom_minimum_size = Vector2(0, 112)
	_equip_page.add_child(inv_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_panel.add_child(scroll)
	_inv_box = HBoxContainer.new()
	_inv_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_inv_box)


func _type_line(res: Resource) -> String:
	if res is WeaponData:
		return "🔫 Arma · %s" % res.get_family_name()
	if res is ItemData:
		return "%s %s · 1 hueco" % [SLOT_EMOJI[clampi(res.slot, 0, 2)], res.get_slot_name()]
	return ""


func _rebuild_equipment(coins: int) -> void:
	for c in _equip_box.get_children():
		_equip_box.remove_child(c)
		c.queue_free()
	_equip_buttons.clear()
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm == null:
		return
	for i in gsm.equipment_offers.size():
		var res: Resource = gsm.equipment_offers[i]
		if res == null:
			_equip_box.add_child(_make_sold("✔ Vendido"))
		else:
			_equip_box.add_child(_make_equip_card(i, res, coins))
	# Botón de renovar
	var cost := ShopSystem.reroll_cost()
	_reroll_btn.text = "🔄 Renovar (%d 💰) · sube cada vez" % cost
	_reroll_btn.disabled = coins < cost
	_reroll_btn.tooltip_text = "El coste sube con cada uso esta ronda." + ("" if coins >= cost else "\nFaltan %d 💰" % (cost - coins))
	_rebuild_inventory()


func _make_equip_card(index: int, res: Resource, coins: int) -> Control:
	var rarity: int = res.rarity
	var col := UiKit.rarity_color(rarity)
	var pc := UiKit.panel(UiKit.PANEL, Color(col, 0.85), 10, 2, 12)
	pc.custom_minimum_size = Vector2(EQUIP_W, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	pc.add_child(box)

	var icon_panel := UiKit.panel(Color(col.r * 0.16, col.g * 0.16, col.b * 0.16), Color(col, 0.35), 8, 1, 6)
	box.add_child(icon_panel)
	if res is WeaponData:
		icon_panel.add_child(UiKit.icon_rect(res.get_icon(), 56))
	else:
		var emoji := UiKit.label(UiKit.emo(res.emoji), 40, UiKit.TEXT)
		emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_panel.add_child(emoji)

	var name_l := UiKit.label(res.display_name, 19, col)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.name = "NameLabel"
	box.add_child(name_l)
	var rar := UiKit.label(UiKit.rarity_name(rarity).to_upper(), 12, col)
	rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(rar)
	var type_l := UiKit.label(_type_line(res), 13, SOFT)
	type_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(type_l)
	var desc := UiKit.wrap_label(res.description, 13, SOFT, EQUIP_W - 28.0)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size.y = 56
	desc.max_lines_visible = 4
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(desc)

	var price := Economy.price_of(res)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	btn.add_theme_font_size_override("font_size", 15)
	UiKit.style_button(btn, Color(0.3, 0.24, 0.06), UiKit.GOLD, Color(1.0, 0.93, 0.65), 8, 6)
	if coins >= price:
		btn.text = "Comprar · %d 💰" % price
	else:
		btn.text = "Faltan %d 💰" % (price - coins)
		btn.disabled = true
	btn.pressed.connect(func(): buy_equipment(index))
	box.add_child(btn)
	_equip_buttons.append(btn)
	return pc


func _make_sold(text: String) -> Control:
	var pc := UiKit.panel(Color(0.09, 0.1, 0.13, 0.8), Color(0.3, 0.34, 0.42, 0.5), 10, 1, 12)
	pc.custom_minimum_size = Vector2(EQUIP_W if _tab == TAB_EQUIPO else CARD_W, 0)
	var l := UiKit.label(text, 18, Color(0.5, 0.8, 0.55))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc


func _rebuild_inventory() -> void:
	for c in _inv_box.get_children():
		_inv_box.remove_child(c)
		c.queue_free()
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm == null:
		return
	var any := false
	for res in gsm.player_bench:
		if res is ItemData or res is WeaponData:
			any = true
			_inv_box.add_child(_make_inv_cell(res))
	if not any:
		var empty := UiKit.label("Inventario vacío. Lo que compres y no equipes aparecerá aquí.", 14, SOFT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(1020, 92)
		_inv_box.add_child(empty)


func _make_inv_cell(res: Resource) -> Control:
	var col := UiKit.rarity_color(res.rarity)
	var cell := UiKit.panel(UiKit.PANEL_2, Color(col, 0.7), 8, 1, 8)
	cell.custom_minimum_size = Vector2(178, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	cell.add_child(v)
	var n: Label
	if res is WeaponData:
		var row := UiKit.icon_label(res.get_icon(), res.display_name, 13, col)
		n = row.get_meta("label")
		n.clip_text = true
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size.x = 158
		v.add_child(row)
	else:
		n = UiKit.label("%s %s" % [UiKit.emo(res.emoji), res.display_name], 13, col)
		n.clip_text = true
		n.custom_minimum_size.x = 158
		v.add_child(n)
	var t := UiKit.label(_type_line(res), 12, SOFT)
	t.clip_text = true
	v.add_child(t)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 28)
	btn.add_theme_font_size_override("font_size", 13)
	btn.text = "Vender +%d 💰" % Economy.sell_price(res)
	UiKit.style_button(btn, Color(0.2, 0.3, 0.2), Color(0.45, 0.75, 0.5), Color(0.85, 1.0, 0.88), 6, 4)
	btn.pressed.connect(func(): sell(res))
	v.add_child(btn)
	return cell


# ---------------------------------------------------------------- pestaña Reclutas

func _build_recruit_page() -> void:
	_slots_label = UiKit.label("", 15, SOFT)
	_recruit_page.add_child(_slots_label)

	_offers_box = HBoxContainer.new()
	_offers_box.add_theme_constant_override("separation", 14)
	_offers_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_recruit_page.add_child(_offers_box)

	var hint := UiKit.label("Cada recluta es único: nombre, Vida, Daño, arma y, a veces, un objeto 🎒 o hasta especialidad 🎖️ (cuestan algo más). Llegan a la reserva; arrástralos al tablero.", 12, UiKit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recruit_page.add_child(hint)


func _rebuild_all() -> void:
	_rebuild_recruits()


func _rebuild_recruits() -> void:
	for c in _offers_box.get_children():
		_offers_box.remove_child(c)
		c.queue_free()
	_buy_buttons.clear()
	var gsm = get_node_or_null("/root/GameStateManager")
	if gsm == null:
		return
	for o in gsm.shop_offers:
		if o is TroopCard:
			_offers_box.add_child(_make_offer(o))
		else:
			_offers_box.add_child(_make_sold("✔ Reclutado"))


func _make_offer(card: TroopCard) -> Control:
	var pc := UiKit.make_recruit_card(card, CARD_W)
	var box: VBoxContainer = pc.get_meta("box")
	_frame_weapon_badge(box)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	btn.add_theme_font_size_override("font_size", 15)
	UiKit.style_button(btn, Color(0.3, 0.24, 0.06), UiKit.GOLD, Color(1.0, 0.93, 0.65))
	btn.pressed.connect(func():
		if buy(card):
			pass)
	box.add_child(btn)
	_buy_buttons[card] = btn
	return pc


## Enmarca el icono del arma de la ficha de recluta (esquina del retrato) para que se lea como insignia.
func _frame_weapon_badge(box: VBoxContainer) -> void:
	if box.get_child_count() == 0:
		return
	var portrait := box.get_child(0)
	if portrait.get_child_count() < 2 or not (portrait.get_child(1) is Label):
		return
	var badge: Label = portrait.get_child(1)
	portrait.remove_child(badge)
	var frame := UiKit.panel(Color(0.07, 0.08, 0.1, 0.92), UiKit.GOLD, 6, 1, 3)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_END
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(badge)
	portrait.add_child(frame)
