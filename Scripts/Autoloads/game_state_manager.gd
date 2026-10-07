extends Node

var player_bench: Array = [] # Reserva: TroopCard, ItemData y WeaponData (sueltos)
var deployed_troops_data: Array = [] # Tropas del tablero entre rondas: [{card: TroopCard, position: Vector2}]
var shop_offers: Array = [] # Ofertas de la tienda de reclutamiento de esta ronda (las gestiona la UI)
var wins_count: int = 0
var current_stage: int = 1 # Ronda actual (infinitas)
var current_node_type: String = "Batalla Normal"

# --- Rondas infinitas + ruleta del jefe ---
const BOSS_TYPE: String = "Jefe Final"
const ELITE_TYPE: String = "Batalla Élite"
const NORMAL_TYPE: String = "Batalla Normal"
const SUBBOSS_TYPE: String = "Jefe de Sector"
const BOSS_CHANCE_STEP: float = 0.005  # v4.1: +0,5 % por ronda desde BOSS_MIN_ROUND (≈10 % en la ronda 30)
const BOSS_MIN_ROUND: int = 11         # v4.1: tras ganar la ronda 10 (Jefe de Sector) empieza la ruleta
const SUBBOSS_EVERY: int = 10          # Cada 10 rondas (10, 20, 30…) toca un Jefe de Sector fijo
const ELITE_CHANCE: float = 0.2        # Probabilidad de batalla élite (desde la ronda 3)
var boss_chance: float = 0.0
var rolled_round: int = 0              # Ronda para la que ya se giró la ruleta (no se repite)
var last_roll_was_boss: bool = false
## Jefes de Sector derrotados en esta run (para las Medallas de mando al terminar).
var subbosses_defeated: int = 0
var coins: int = 0
var command_points: int = 0
## Alias de compatibilidad: el código nuevo usa `coins`.
var gold: int:
	get:
		return coins
	set(v):
		coins = v

# --- Seguimiento de ronda ---
var round_kills: int = 0
var round_kill_coins: int = 0
var round_player_losses: int = 0
var last_round_summary: Dictionary = {}

# --- Intendencia (estado; la lógica de tiradas es de ShopSystem) ---
var equipment_offers: Array = [] # ItemData / WeaponData / null (vendido)
var reroll_count: int = 0

# true mientras hay un menú modal abierto (bloquea el arrastre de tropas en el tablero)
var ui_blocking: bool = false

const MAX_DEPLOYED_TROOPS: int = 6
## Alias de compatibilidad; la fuente es Economy.
const STARTING_GOLD: int = Economy.STARTING_COINS


func get_deployed_count() -> int:
	var n := 0
	for t in get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(t) and not t.is_queued_for_deletion() \
				and t.team == t.Team.PLAYER and not t.has_meta("is_drag_preview"):
			n += 1
	return n


func can_deploy_more() -> bool:
	return get_deployed_count() < MAX_DEPLOYED_TROOPS


const MAX_ARMY_SIZE: int = 6 # Huecos del ejército (tablero + reserva)


## Tropas que tiene el jugador en total: desplegadas en el tablero + tarjetas en la reserva.
func get_army_size() -> int:
	var n := get_deployed_count()
	for res in player_bench:
		if res is TroopCard:
			n += 1
	return n


## Todo el ejército del jugador: las desplegadas en el último combate (también las que cayeron),
## las vivas del tablero y las de la reserva.
## Se usa al vencer al Jefe Final para elegir quién va al Cuartel.
func get_army_cards() -> Array[TroopCard]:
	var out: Array[TroopCard] = []
	# v7.2: la instantánea del despliegue incluye a los que cayeron en el combate final
	for entry in deployed_troops_data:
		var dc = entry.get("card")
		if dc is TroopCard and not dc in out:
			out.append(dc)
	for t in get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(t) and not t.is_queued_for_deletion() \
				and t.team == t.Team.PLAYER and not t.has_meta("is_drag_preview") \
				and t.get("card") is TroopCard and not t.card in out:
			out.append(t.card)
	for c in get_bench_cards():
		if not c in out:
			out.append(c)
	return out


## Tropas de la reserva (TroopCard).
func get_bench_cards() -> Array[TroopCard]:
	var out: Array[TroopCard] = []
	for res in player_bench:
		if res is TroopCard:
			out.append(res)
	return out


## Objetos sueltos de la reserva (ItemData).
func get_bench_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for res in player_bench:
		if res is ItemData:
			out.append(res)
	return out


## Armas sueltas de la reserva (WeaponData).
func get_bench_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for res in player_bench:
		if res is WeaponData:
			out.append(res)
	return out


func has_free_army_slot() -> bool:
	return get_army_size() < MAX_ARMY_SIZE


## Compra una tropa (TroopCard) por `price` y la deja en la reserva. Devuelve true si se pudo.
func recruit_troop(card: TroopCard, price: int) -> bool:
	if card == null or not has_free_army_slot():
		return false
	if not spend_coins(price):
		return false
	add_troop_to_army(card)
	print("Tropa reclutada: %s por %d monedas" % [card.unit_name, price])
	return true


func add_coins(amount: int, reason: String = "") -> void:
	if amount <= 0: # para gastar se usa spend_coins
		return
	coins += amount
	print("Monedas %+d (%s) | Total: %d" % [amount, reason, coins])
	EventBus.coins_changed.emit(coins, amount)
	EventBus.roster_changed.emit()


func spend_coins(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	coins -= amount
	if amount > 0:
		EventBus.coins_changed.emit(coins, -amount)
		EventBus.roster_changed.emit()
	return true


func add_points(amount: int, reason: String = "") -> void:
	if amount <= 0: # para gastar se usa spend_points
		return
	command_points += amount
	print("PM %+d (%s) | Total: %d" % [amount, reason, command_points])
	EventBus.command_points_changed.emit(command_points, amount)
	EventBus.roster_changed.emit()


func spend_points(amount: int) -> bool:
	if amount < 0 or command_points < amount:
		return false
	command_points -= amount
	if amount > 0:
		EventBus.command_points_changed.emit(command_points, -amount)
		EventBus.roster_changed.emit()
	return true


# Alias de compatibilidad
func add_gold(amount: int) -> void:
	add_coins(amount)


func spend_gold(amount: int) -> bool:
	return spend_coins(amount)


# --- Seguimiento de ronda y recompensas ---
func begin_round_tracking() -> void:
	round_kills = 0
	round_kill_coins = 0
	round_player_losses = 0


## Registra una baja enemiga y suma sus monedas. Devuelve las monedas ganadas.
func register_enemy_kill(enemy_card: TroopCard, node_type: String) -> int:
	var n := Economy.coins_for_kill(enemy_card, node_type)
	round_kills += 1
	round_kill_coins += n
	add_coins(n, "baja")
	return n


func register_player_loss() -> void:
	round_player_losses += 1


## Llamar UNA vez al ganar: bono de victoria, interés y PM. Guarda y devuelve el resumen.
func apply_victory_rewards(node_type: String) -> Dictionary:
	var clean := round_player_losses == 0
	if node_type == SUBBOSS_TYPE:
		subbosses_defeated += 1
	var win_coins := Economy.WIN_BONUS_COINS
	add_coins(win_coins, "victoria")
	var interest := Economy.interest_for(coins)
	add_coins(interest, "interés")
	var points := Economy.points_for_win(node_type, clean)
	add_points(points, "victoria")
	last_round_summary = {
		"kills": round_kills,
		"kill_coins": round_kill_coins,
		"win_coins": win_coins,
		"interest": interest,
		"points": points,
		"clean": clean,
		"coins_total": coins,
		"points_total": command_points,
	}
	return last_round_summary


## Añade una tropa (TroopCard) a la reserva.
func add_troop_to_army(card: TroopCard) -> void:
	if card == null:
		return
	player_bench.append(card)
	print("Tropa añadida a la reserva: ", card.get_title())
	EventBus.roster_changed.emit()


## Retira una tropa del tablero y guarda su mismo card en la reserva.
func return_troop_to_bench(troop: CharacterBody2D) -> void:
	if not is_instance_valid(troop) or troop.is_queued_for_deletion():
		return
	var card: TroopCard = troop.card
	if card:
		player_bench.append(card)
		print("Tropa devuelta a la reserva: %s (Nv. %d)" % [card.unit_name, card.level])
	troop.remove_from_group("troops")
	troop.queue_free()
	EventBus.roster_changed.emit()


func add_item(item: Resource) -> void:
	if item:
		player_bench.append(item)
		print("Objeto añadido a la bandeja: ", item.display_name)
		EventBus.roster_changed.emit()


## Equipa a la tropa un objeto suelto de la reserva (lo saca de la reserva). Devuelve true si cupo.
func equip_item_from_bench(card: TroopCard, item: ItemData) -> bool:
	if card == null or item == null or not item in player_bench:
		return false
	if not card.add_item(item):
		return false
	player_bench.erase(item)
	EventBus.roster_changed.emit()
	return true


## Equipa un arma suelta del inventario: la añade al arsenal de la tropa. false si ya la tiene.
func equip_weapon_from_bench(card: TroopCard, weapon: WeaponData) -> bool:
	if card == null or weapon == null or not weapon in player_bench:
		return false
	if card.has_weapon(weapon.id):
		return false
	card.weapons.append(weapon)
	player_bench.erase(weapon)
	EventBus.roster_changed.emit()
	EventBus.shop_changed.emit()
	return true


## Vende un recurso suelto del inventario. Devuelve las monedas ganadas (0 si no estaba).
func sell_from_bench(res: Resource) -> int:
	if res == null or not res in player_bench:
		return 0
	var gain := Economy.sell_price(res)
	player_bench.erase(res)
	add_coins(gain, "venta")
	EventBus.shop_changed.emit()
	return gain


func remove_from_bench(resource: Resource) -> void:
	if resource in player_bench:
		player_bench.erase(resource)
		print("Recurso consumido de la bandeja: ", resource.display_name if "display_name" in resource else "Recurso")
		EventBus.roster_changed.emit()


func save_deployed_troops(player_troops: Array) -> void:
	deployed_troops_data.clear()
	for troop in player_troops:
		if is_instance_valid(troop) and not troop.is_queued_for_deletion():
			deployed_troops_data.append({
				"card": troop.card,
				"position": troop.global_position,
			})
	print("Tropas en tablero guardadas para la siguiente ronda: ", deployed_troops_data.size())


## Tras ganar una ronda normal/élite: siguiente ronda y probabilidad de jefe (boss_chance_for_round).
func advance_stage() -> void:
	current_stage += 1
	wins_count += 1
	boss_chance = boss_chance_for_round(current_stage, boss_chance)
	shop_offers.clear()
	equipment_offers.clear()
	reroll_count = 0
	print("Avanzando a la ronda %d | Probabilidad de jefe: %d%%" % [current_stage, roundi(boss_chance * 100.0)])


## Probabilidad del jefe FINAL al llegar a la ronda `round_num`: 0 antes de BOSS_MIN_ROUND (11) y
## después 0,5 % en la 11, 1 % en la 12… (+BOSS_CHANCE_STEP por ronda). `prev` se conserva por compatibilidad.
static func boss_chance_for_round(round_num: int, _prev: float = 0.0) -> float:
	if round_num < BOSS_MIN_ROUND:
		return 0.0
	return minf(1.0, float(round_num - BOSS_MIN_ROUND + 1) * BOSS_CHANCE_STEP)


## true si en esa ronda toca Jefe de Sector (10, 20, 30…).
static func is_subboss_round(round_num: int) -> bool:
	return round_num > 0 and round_num % SUBBOSS_EVERY == 0


## Nivel del Jefe de Sector de esa ronda (1 en la 10, 2 en la 20…).
static func subboss_tier(round_num: int) -> int:
	return maxi(1, round_num / SUBBOSS_EVERY)


## Probabilidad de jefe que tendrá la ronda siguiente (para mostrarla en la pantalla de recompensas).
func next_boss_chance() -> float:
	return boss_chance_for_round(current_stage + 1, boss_chance)


## Gira la ruleta de la ronda actual (una sola vez por ronda) y fija el tipo de combate.
func roll_round_type() -> String:
	if rolled_round == current_stage:
		return current_node_type
	rolled_round = current_stage
	# Jefe de Sector fijo cada 10 rondas (tiene prioridad sobre la ruleta)
	if is_subboss_round(current_stage):
		last_roll_was_boss = false
		current_node_type = SUBBOSS_TYPE
		# v7.1: llegar al N.º Jefe de Sector desbloquea una especialidad (una vez por perfil)
		var pm := get_node_or_null("/root/ProfileManager")
		if pm and pm.has_method("reach_milestone"):
			pm.reach_milestone("sector_%d" % subboss_tier(current_stage))
		return current_node_type
	last_roll_was_boss = current_stage >= BOSS_MIN_ROUND and randf() < boss_chance
	if last_roll_was_boss:
		current_node_type = BOSS_TYPE
	elif current_stage >= 3 and randf() < ELITE_CHANCE:
		current_node_type = ELITE_TYPE
	else:
		current_node_type = NORMAL_TYPE
	return current_node_type


func is_boss_stage() -> bool:
	return current_node_type == BOSS_TYPE


func is_subboss_stage() -> bool:
	return current_node_type == SUBBOSS_TYPE


func reset_run() -> void:
	var pm := get_node_or_null("/root/ProfileManager")
	if pm and "recent_unlocks" in pm:
		pm.recent_unlocks.clear() # los avisos son por run
	player_bench.clear()
	deployed_troops_data.clear()
	wins_count = 0
	current_stage = 1
	current_node_type = NORMAL_TYPE
	boss_chance = 0.0
	rolled_round = 0
	last_roll_was_boss = false
	subbosses_defeated = 0
	coins = 0
	command_points = 0
	shop_offers.clear()
	equipment_offers.clear()
	reroll_count = 0
	begin_round_tracking()
	last_round_summary = {}
