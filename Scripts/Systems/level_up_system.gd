class_name LevelUpSystem
extends RefCounted
## Subida de nivel con Puntos de Mando: 2 ofertas al azar, el jugador elige 1.

const TYPE_WEIGHTS := {"skill": 55.0, "item": 25.0, "weapon": 20.0}
const RARITY_WEIGHTS := [60.0, 30.0, 10.0, 5.0]
const AFFINE_WEAPON_FACTOR := 2.0
const OFFER_COUNT := 2


static func _rng(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng:
		return rng
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


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


static func rarity_weight(rarity: int) -> float:
	return RARITY_WEIGHTS[clampi(rarity, 0, RARITY_WEIGHTS.size() - 1)]


## Índice elegido al azar según pesos (-1 si no hay nada con peso > 0).
static func weighted_index(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, w)
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= maxf(0.0, weights[i])
		if roll < 0.0:
			return i
	return weights.size() - 1


static func _skill_ok(card: TroopCard, s: SkillData) -> bool:
	if card.has_skill(s.id) and not s.stackable:
		return false
	for req in s.requires:
		if not card.has_skill(req):
			return false
	return true


## Candidatos de un tipo: [{resource, weight}]. round_limit > 0 filtra armas por min_round (enemigos).
static func candidates(card: TroopCard, type: String, round_limit: int = 0) -> Array:
	var out: Array = []
	match type:
		"specialty":
			for sp in GameContent.specialties():
				# El jugador solo elige entre las desbloqueadas; los enemigos usan todas
				if card.is_enemy or SpecialtyProgression.is_unlocked(sp.id):
					out.append({"resource": sp, "weight": 1.0})
		"skill":
			for s in GameContent.skills():
				if _skill_ok(card, s):
					out.append({"resource": s, "weight": rarity_weight(s.rarity)})
		"item":
			for it in GameContent.items():
				if card.can_add_item(it):
					out.append({"resource": it, "weight": rarity_weight(it.rarity)})
		"weapon":
			for w in GameContent.weapons():
				if card.has_weapon(w.id):
					continue
				if round_limit > 0 and w.min_round > round_limit:
					continue
				var wt := rarity_weight(w.rarity)
				if card.specialty and card.specialty.is_affine(w):
					wt *= AFFINE_WEAPON_FACTOR
				out.append({"resource": w, "weight": wt})
	return out


## Devuelve 2 ofertas distintas {type, resource}. No modifica la tropa.
## Jugador: especialidades en Nv. TroopCard.SPECIALTY_LEVEL (5); después solo habilidades (pesos por nivel) con respaldo "training".
## for_enemy = true conserva el reparto antiguo (habilidad/objeto/arma) para escalar enemigos.
static func roll_offers(card: TroopCard, rng: RandomNumberGenerator = null, round_limit: int = 0, for_enemy: bool = false) -> Array[Dictionary]:
	rng = _rng(rng)
	if for_enemy:
		return _roll_offers_enemy(card, rng, round_limit)
	# Pequeña probabilidad (Economy.THIRD_OFFER_CHANCE) de que salga una 3.ª mejora para elegir
	var count: int = OFFER_COUNT + (1 if rng.randf() < Economy.THIRD_OFFER_CHANCE else 0)
	if card.specialty == null and card.level + 1 >= TroopCard.SPECIALTY_LEVEL:
		return _roll_from_pools(rng, {"specialty": candidates(card, "specialty")}, count)
	var offers: Array[Dictionary] = []
	var weights := Economy.skill_rarity_weights(card.level + 1)
	var pool: Array = []
	for s in GameContent.skills():
		if _skill_ok(card, s):
			pool.append(s)
	for _i in count:
		var w: Array = []
		for s in pool:
			w.append(float(weights[clampi(s.rarity, 0, weights.size() - 1)]))
		var idx := weighted_index(w, rng)
		if idx < 0:
			break
		offers.append({"type": "skill", "resource": pool[idx]})
		pool.remove_at(idx)
	# Respaldo: una sola carta de entrenamiento si faltan habilidades (nunca dos idénticas)
	if offers.size() < OFFER_COUNT:
		offers.append({"type": "training", "resource": null})
	return offers


static func _roll_offers_enemy(card: TroopCard, rng: RandomNumberGenerator, round_limit: int) -> Array[Dictionary]:
	var pools := {}
	if card.specialty == null and card.level + 1 >= TroopCard.ENEMY_SPECIALTY_LEVEL:
		pools["specialty"] = candidates(card, "specialty")
	else:
		for t in TYPE_WEIGHTS:
			pools[t] = candidates(card, t, round_limit)
	return _roll_from_pools(rng, pools, OFFER_COUNT)


static func _roll_from_pools(rng: RandomNumberGenerator, pools: Dictionary, count: int = OFFER_COUNT) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var used: Array = []
	for _i in count:
		# Tipos que aún tienen candidatos sin usar (si uno se agota, se rellena con otro)
		var types: Array = []
		var type_w: Array = []
		for t in pools:
			var any_left := false
			for c in pools[t]:
				if not c.resource in used:
					any_left = true
					break
			if any_left:
				types.append(t)
				type_w.append(TYPE_WEIGHTS.get(t, 1.0))
		var ti := weighted_index(type_w, rng)
		if ti < 0:
			break
		var t: String = types[ti]
		var res_list: Array = []
		var res_w: Array = []
		for c in pools[t]:
			if not c.resource in used:
				res_list.append(c.resource)
				res_w.append(c.weight)
		var ri := weighted_index(res_w, rng)
		if ri < 0:
			break
		used.append(res_list[ri])
		offers.append({"type": t, "resource": res_list[ri]})
	return offers


## Valida, cobra los PM y rellena card.pending_offers. Aún NO sube de nivel.
static func begin_level_up(card: TroopCard, rng: RandomNumberGenerator = null) -> bool:
	if card == null or not card.can_level_up():
		return false
	var gsm := _gsm()
	if gsm == null or gsm.command_points < card.get_level_up_cost():
		return false
	# Primero se tiran las ofertas: si no hubiera ninguna, no se cobran los PM
	var offers := roll_offers(card, rng)
	if offers.is_empty() or not gsm.spend_points(card.get_level_up_cost()):
		return false
	card.pending_offers.clear()
	for o in offers:
		card.pending_offers.append(o)
	var bus := _bus()
	if bus:
		bus.level_up_offers_ready.emit(card)
	return true


## Aplica una oferta a la tropa (sin subir nivel ni emitir señales).
static func apply_offer(card: TroopCard, offer: Dictionary, equip_weapon: bool = false) -> void:
	var res: Resource = offer.get("resource")
	match String(offer.get("type", "")):
		"training":
			card.training_ranks += 1
		"specialty":
			card.specialty = res as SpecialtyData
		"skill":
			card.skills.append(res as SkillData)
		"item":
			card.add_item(res as ItemData)
		"weapon":
			var w := res as WeaponData
			if not card.has_weapon(w.id):
				card.weapons.append(w)
			if equip_weapon or card.specialty == null or card.weapons.size() == 1:
				card.equipped_weapon = card.weapons.find(w)


## El jugador elige la oferta `index`: se aplica, sube de nivel y se avisa.
## equip_weapon = true equipa el arma nueva (si la oferta es un arma).
static func choose(card: TroopCard, index: int, equip_weapon: bool = false) -> void:
	if card == null or index < 0 or index >= card.pending_offers.size():
		return
	apply_offer(card, card.pending_offers[index], equip_weapon)
	card.level = mini(card.level + 1, TroopCard.MAX_LEVEL)
	card.pending_offers.clear()
	var bus := _bus()
	if bus:
		bus.roster_changed.emit()
		bus.troop_leveled.emit(card)


## Mejora con PM el arma `w` de la tropa (por defecto la equipada): nivel +1, máximo Economy.WEAPON_MAX_LEVEL.
static func upgrade_weapon(card: TroopCard, w: WeaponData = null) -> bool:
	if card == null:
		return false
	if w == null:
		w = card.get_weapon()
	if not card.can_upgrade_weapon(w):
		return false
	var gsm := _gsm()
	if gsm == null or not gsm.spend_points(card.get_weapon_upgrade_cost(w)):
		return false
	card.weapon_levels[w.id] = card.get_weapon_level(w) + 1
	var bus := _bus()
	if bus:
		bus.roster_changed.emit()
	return true
