class_name ShopSystem
extends RefCounted
## Lógica de la Intendencia de equipo (SPEC v3 §7): tiradas por ronda, compra, renovación y venta.
## El estado vive en GameStateManager (equipment_offers, reroll_count, player_bench, coins).


static func _gsm() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/GameStateManager")
	return null


static func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/EventBus")
	return null


static func _notify() -> void:
	var bus := _bus()
	if bus:
		bus.shop_changed.emit()


## Elige un recurso de `pool` según los pesos de rareza. null si el pool está vacío.
static func _pick(pool: Array, rng: RandomNumberGenerator) -> Resource:
	if pool.is_empty():
		return null
	var weights: Array = []
	for r in pool:
		weights.append(LevelUpSystem.rarity_weight(r.rarity))
	var i := LevelUpSystem.weighted_index(weights, rng)
	return pool[maxi(i, 0)]


## Tira las ofertas de equipo de la ronda: EQUIPMENT_OFFERS recursos distintos (objetos y armas).
static func roll_equipment_offers(round_num: int, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var max_r := Economy.max_shop_rarity(round_num)
	var items: Array = []
	for it in GameContent.items():
		if it.rarity <= max_r:
			items.append(it)
	var weapons: Array = []
	for w in GameContent.weapons():
		if w.rarity <= max_r and w.min_round <= round_num:
			weapons.append(w)
	var out: Array = []
	var guard := 0
	while out.size() < Economy.EQUIPMENT_OFFERS and (not items.is_empty() or not weapons.is_empty()) and guard < 200:
		guard += 1
		var want_weapon := rng.randf() < Economy.WEAPON_OFFER_CHANCE
		var pool: Array = weapons if (want_weapon and not weapons.is_empty()) or items.is_empty() else items
		var pick := _pick(pool, rng)
		if pick == null:
			continue
		out.append(pick)
		pool.erase(pick) # sin repetidos
	return out


## Genera las ofertas de la ronda si todavía no existen.
static func ensure_offers() -> void:
	var gsm := _gsm()
	if gsm == null:
		return
	if gsm.equipment_offers.is_empty():
		gsm.equipment_offers = roll_equipment_offers(gsm.current_stage)
		_notify()


## Compra la oferta `index`: cobra, la mete en el inventario y deja el hueco en null (vendido).
static func buy_equipment(index: int) -> bool:
	var gsm := _gsm()
	if gsm == null or index < 0 or index >= gsm.equipment_offers.size():
		return false
	var res: Resource = gsm.equipment_offers[index]
	if res == null:
		return false
	if not gsm.spend_coins(Economy.price_of(res)):
		return false
	gsm.player_bench.append(res)
	gsm.equipment_offers[index] = null
	var bus := _bus()
	if bus:
		bus.roster_changed.emit()
	_notify()
	return true


## Precio de la próxima renovación.
static func reroll_cost() -> int:
	var gsm := _gsm()
	return Economy.reroll_price(gsm.reroll_count if gsm else 0)


## Renueva las 4 ofertas pagando el precio creciente.
static func reroll() -> bool:
	var gsm := _gsm()
	if gsm == null:
		return false
	if not gsm.spend_coins(reroll_cost()):
		return false
	gsm.reroll_count += 1
	gsm.equipment_offers = roll_equipment_offers(gsm.current_stage)
	_notify()
	return true


## Vende un objeto o arma suelto del inventario. Devuelve las monedas ganadas.
static func sell(res: Resource) -> int:
	var gsm := _gsm()
	if gsm == null:
		return 0
	return gsm.sell_from_bench(res)
