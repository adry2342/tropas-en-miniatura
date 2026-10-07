extends Node2D
## Test de la Intendencia (SPEC v3 §7): ShopSystem + UI real (recruit_shop.gd) dentro de la batalla.

const BATTLE = preload("res://Scenes/Battle/battle.tscn")

var _fails: Array[String] = []
var _passes := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("TEST PASS: ", name)
	else:
		_fails.append(name)
		print("TEST FAIL: ", name)


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_dev/shots/%s.png" % file)


func _find_by_script(parent: Node, suffix: String) -> Node:
	for n in parent.get_children():
		if n.get_script() and n.get_script().resource_path.ends_with(suffix):
			return n
	return null


func _max_rarity(offers: Array) -> int:
	var m := 0
	for o in offers:
		if o != null:
			m = maxi(m, o.rarity)
	return m


func _unique(offers: Array) -> bool:
	var seen := {}
	for o in offers:
		if o == null or seen.has(o):
			return false
		seen[o] = true
	return true


func _ready() -> void:
	ProfileManager.all_specialties_unlocked = true # v7.1: estas pruebas ven todas las especialidades
	ProfileManager.persist = false # no tocar el perfil real (hitos, medallas)
	await get_tree().process_frame
	var gsm := GameStateManager
	gsm.reset_run()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777

	# --- Tiradas
	var r1_ok := true
	var uniq_ok := true
	var size_ok := true
	var weapons_total := 0
	var total := 0
	var min_round_ok := true
	var got3 := 0
	var got3_r4 := 0
	for i in 300:
		var o1 := ShopSystem.roll_equipment_offers(1, rng)
		r1_ok = r1_ok and _max_rarity(o1) <= 1
		uniq_ok = uniq_ok and _unique(o1)
		size_ok = size_ok and o1.size() == Economy.EQUIPMENT_OFFERS
		for o in o1:
			total += 1
			if o is WeaponData:
				weapons_total += 1
				min_round_ok = min_round_ok and o.min_round <= 1
		var o9 := ShopSystem.roll_equipment_offers(9, rng)
		uniq_ok = uniq_ok and _unique(o9)
		if _max_rarity(o9) >= 2:
			got3 += 1
		var o5 := ShopSystem.roll_equipment_offers(5, rng)
		if _max_rarity(o5) == 3:
			got3_r4 += 1
		var o3 := ShopSystem.roll_equipment_offers(3, rng)
		if _max_rarity(o3) >= 2:
			got3_r4 += 1
	_check(r1_ok, "ronda 1: rareza máxima ≤ 1 en 300 tiradas")
	_check(got3_r4 == 0, "ronda 3 nunca ≥ 2 y ronda 5 nunca 3")
	# NOTA: el contenido actual no tiene recursos de rareza 3 (solo 1 épico); se comprueba la rareza alta disponible.
	var top := 0
	for r in GameContent.items() + GameContent.weapons():
		top = maxi(top, r.rarity)
	_check(got3 > 0 or top < 2, "ronda 9: sale rareza alta (≥2) cuando existe (%d/300, máx. contenido %d)" % [got3, top])
	_check(uniq_ok, "ofertas sin duplicados")
	_check(size_ok, "siempre %d ofertas" % Economy.EQUIPMENT_OFFERS)
	var frac := float(weapons_total) / float(total)
	_check(frac > 0.2 and frac < 0.4, "≈30 %% armas (%d %%)" % roundi(frac * 100.0))
	_check(min_round_ok, "las armas respetan min_round")

	# --- UI real dentro de la batalla
	var battle = BATTLE.instantiate()
	add_child(battle)
	await _frames(3)
	var shop = _find_by_script(battle, "recruit_shop.gd")
	_check(shop != null and not shop.visible, "la Intendencia existe y empieza cerrada")
	gsm.reset_run()
	gsm.coins = 100
	gsm.command_points = 3
	gsm.current_stage = 1
	EventBus.roster_changed.emit()
	await _frames(2)

	EventBus.shop_requested.emit("equipo")
	await _frames(3)
	_check(shop.visible and gsm.ui_blocking and shop.current_tab() == "equipo", "shop_requested('equipo') abre la pestaña Equipo y bloquea")
	_check(gsm.equipment_offers.size() == 4 and _unique(gsm.equipment_offers), "se generan 4 ofertas distintas al abrir")
	var snapshot: Array = gsm.equipment_offers.duplicate()
	shop.close()
	_check(not shop.visible and not gsm.ui_blocking, "cerrar libera el bloqueo")
	EventBus.shop_requested.emit("equipo")
	await _frames(2)
	_check(gsm.equipment_offers == snapshot, "las ofertas persisten al reabrir")

	# Compra
	var first: Resource = gsm.equipment_offers[0]
	var price := Economy.price_of(first)
	var before: int = gsm.coins
	_check(shop.buy_equipment(0), "comprar la oferta 0")
	await _frames(2)
	_check(gsm.coins == before - price, "se cobra el precio (%d)" % price)
	_check(first in gsm.player_bench, "el objeto/arma va al inventario")
	_check(gsm.equipment_offers[0] == null, "la oferta queda como vendido (null)")
	_check(not shop.buy_equipment(0), "no se puede comprar dos veces")

	# Sin monedas
	gsm.coins = 0
	EventBus.roster_changed.emit()
	await _frames(2)
	var bench_n: int = gsm.player_bench.size()
	_check(not shop.buy_equipment(1) and gsm.player_bench.size() == bench_n and gsm.equipment_offers[1] != null, "sin monedas no compra")
	_check(not shop.reroll(), "sin monedas no renueva")
	var all_dis := true
	for b in shop._equip_buttons:
		all_dis = all_dis and b.disabled
	_check(all_dis, "botones de compra desactivados sin monedas")

	# Renovar
	gsm.coins = 50
	gsm.reroll_count = 0
	EventBus.roster_changed.emit()
	await _frames(2)
	_check(ShopSystem.reroll_cost() == 1, "1ª renovación cuesta 1")
	_check(shop.reroll() and gsm.coins == 49, "renovar cobra 1")
	_check(ShopSystem.reroll_cost() == 2, "2ª renovación cuesta 2")
	_check(shop.reroll() and gsm.coins == 47, "renovar cobra 2")
	_check(gsm.equipment_offers.size() == 4 and not gsm.equipment_offers.has(null), "renovar deja 4 ofertas nuevas")

	# Vender
	gsm.player_bench.clear()
	var cheap: ItemData = null
	for it in GameContent.items():
		if it.rarity == 0:
			cheap = it
			break
	var weap: WeaponData = GameContent.find_weapon("bazuca")
	gsm.player_bench.append(cheap)
	gsm.player_bench.append(weap)
	gsm.coins = 0
	EventBus.roster_changed.emit()
	await _frames(2)
	_check(shop._inv_box.get_child_count() == 2, "el inventario muestra 2 recursos")
	var gain: int = shop.sell(cheap)
	_check(gain == maxi(1, floori(Economy.price_of(cheap) * 0.5)) and gsm.coins == gain, "vender objeto devuelve 50 %% (+%d)" % gain)
	_check(not cheap in gsm.player_bench, "lo vendido sale del inventario")
	_check(shop.sell(cheap) == 0, "no se vende dos veces")
	var gain_w: int = shop.sell(weap)
	_check(gain_w == floori(Economy.price_of(weap) * 0.5), "vender arma +%d" % gain_w)
	_check(Economy.sell_price(cheap) >= 1, "venta mínima 1")

	# Captura Equipo con inventario variado
	gsm.coins = 23
	gsm.command_points = 4
	gsm.reroll_count = 2
	gsm.current_stage = 9
	gsm.equipment_offers = ShopSystem.roll_equipment_offers(9, rng)
	gsm.equipment_offers[2] = null
	gsm.player_bench.clear()
	for id in ["bazuca", "escopeta"]:
		var w := GameContent.find_weapon(id)
		if w:
			gsm.player_bench.append(w)
	var added := 0
	for it in GameContent.items():
		if added < 3:
			gsm.player_bench.append(it)
			added += 1
	EventBus.roster_changed.emit()
	await _frames(3)
	await _shot("intendencia_equipo")

	# Reclutas
	shop.close()
	gsm.shop_offers.clear()
	gsm.player_bench.clear()
	gsm.current_stage = 1
	gsm.coins = 100
	EventBus.recruit_shop_requested.emit()
	await _frames(3)
	_check(shop.visible and shop.current_tab() == "reclutas", "recruit_shop_requested abre la pestaña Reclutas")
	var offers: Array[TroopCard] = shop.get_offers()
	_check(offers.size() == 3 and shop._buy_buttons.size() == 3, "Reclutas ofrece 3 reclutas")
	await _shot("intendencia_reclutas")
	var rc: TroopCard = offers[0]
	var rprice := Economy.recruit_price(rc)
	var rbase := rprice - Economy.recruit_extras_surcharge(rc) # objeto/especialidad de serie suben el precio
	_check(rbase >= Economy.RECRUIT_PRICE_MIN and rbase <= Economy.RECRUIT_PRICE_MAX, "precio base de recluta %d 💰 en rango [MIN, MAX] (total %d)" % [rbase, rprice])
	_check(shop.buy(rc), "comprar recluta con monedas")
	await _frames(2)
	_check(gsm.coins == 100 - rprice, "se cobra Economy.recruit_price")
	_check(gsm.get_bench_cards().has(rc) and shop.get_offers().size() == 2, "recluta en la reserva y oferta retirada")
	gsm.coins = 0
	EventBus.roster_changed.emit()
	await _frames(2)
	var dis := true
	for k in shop._buy_buttons:
		if is_instance_valid(shop._buy_buttons[k]):
			dis = dis and shop._buy_buttons[k].disabled and "Faltan" in shop._buy_buttons[k].text
	_check(dis, "sin monedas los reclutas muestran 'Faltan N 💰'")

	# shop_requested abre la pestaña correcta
	shop.close()
	EventBus.shop_requested.emit("reclutas")
	await _frames(2)
	_check(shop.current_tab() == "reclutas" and shop._recruit_page.visible and not shop._equip_page.visible, "shop_requested('reclutas') → Reclutas")
	shop.close()
	EventBus.shop_requested.emit("equipo")
	await _frames(2)
	_check(shop.current_tab() == "equipo" and shop._equip_page.visible and not shop._recruit_page.visible, "shop_requested('equipo') → Equipo")

	# Esc y combate cierran
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	shop._unhandled_key_input(esc)
	_check(not shop.visible and not gsm.ui_blocking, "Esc cierra y desbloquea")
	EventBus.shop_requested.emit("equipo")
	await _frames(2)
	EventBus.battle_fight_started.emit()
	_check(not shop.visible and not gsm.ui_blocking, "al combatir se cierra")

	# Avanzar de ronda regenera
	gsm.coins = 50
	EventBus.shop_requested.emit("equipo")
	await _frames(2)
	var old: Array = gsm.equipment_offers.duplicate()
	var old_recruits: Array = gsm.shop_offers.duplicate()
	shop.close()
	gsm.reroll_count = 3
	gsm.advance_stage()
	_check(gsm.equipment_offers.is_empty() and gsm.reroll_count == 0 and gsm.shop_offers.is_empty(), "advance_stage limpia ofertas y renovaciones")
	EventBus.shop_requested.emit("equipo")
	await _frames(2)
	_check(gsm.equipment_offers.size() == 4 and gsm.equipment_offers != old, "avanzar de ronda regenera ofertas")
	_check(gsm.current_stage == 2 and _max_rarity(gsm.equipment_offers) <= 1, "ronda 2: rareza ≤ 1")
	shop.close()

	print("TEST DONE: %d fallos (%d ok)" % [_fails.size(), _passes])
	for f in _fails:
		print("  FALLO: ", f)
	gsm.reset_run()
	get_tree().quit()
