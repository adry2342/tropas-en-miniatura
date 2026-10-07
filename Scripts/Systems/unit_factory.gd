class_name UnitFactory
extends RefCounted
## Genera reclutas únicos y enemigos escalados por ronda.

const NAMES := [
	"Ríos", "Kowalski", "Moreno", "Ivanov", "Okafor", "Tanaka", "Silva", "Müller",
	"Dubois", "Rossi", "Nakamura", "O'Brien", "Petrov", "García", "Núñez", "Haddad",
	"Lindqvist", "Kim", "Novak", "Costa", "Mendoza", "Becker", "Sato", "Fischer",
	"Romero", "Santos", "Volkov", "Duarte", "Herrera", "Kaya", "Andersen", "Murphy",
	"Vega", "Castillo", "Okoye", "Bianchi", "Hansen", "Quiroga", "Lebrun", "Zamora",
	"Torres", "Varga",
]
const STAT_VARIATION := 0.10
const BASE_HEALTH := 100.0
const BASE_DAMAGE := 1.0
const MIN_PRICE := 40
const MAX_PRICE := 70
## PROVISIONAL (pre-balance QA): los enemigos no cambian a su arma afín especial antes de esta ronda.
const AFFINE_WEAPON_MIN_ROUND := 4
## Niveles extra del líder jefe (equilibrado v3: antes +2, ahora +1; ya lleva ×BOSS_HP_MULT vida y ×BOSS_DMG_MULT daño de battle.gd).
const BOSS_EXTRA_LEVELS := 1
const ENEMY_ROUNDS_PER_LEVEL := 5.0


static func _rng(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng:
		return rng
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


static func random_name(rng: RandomNumberGenerator = null) -> String:
	rng = _rng(rng)
	return NAMES[rng.randi_range(0, NAMES.size() - 1)]


static func _base_card(rng: RandomNumberGenerator) -> TroopCard:
	var c := TroopCard.new()
	c.unit_name = random_name(rng)
	c.base_health = snappedf(BASE_HEALTH * rng.randf_range(1.0 - STAT_VARIATION, 1.0 + STAT_VARIATION), 0.1)
	c.base_damage = snappedf(BASE_DAMAGE * rng.randf_range(1.0 - STAT_VARIATION, 1.0 + STAT_VARIATION), 0.01)
	c.level = 1
	return c


static func recruit_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w in GameContent.weapons():
		if w.recruit_pool:
			out.append(w)
	return out


## Armas que puede traer un recluta: todas las comunes y raras (más variedad que el pool de enemigos).
static func recruit_weapon_options() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w in GameContent.weapons():
		if w.rarity <= 1:
			out.append(w)
	return out


## Recluta Nv. 1: nombre aleatorio, Vida/Daño ±10 %, arma aleatoria (común o, a veces, rara) y,
## con Economy.RECRUIT_ITEM_CHANCE, un objeto aleatorio (munición especial, chaleco…). El precio
## (Economy.recruit_price) sube según el arma y el objeto, con descuento respecto a comprarlo aparte.
## allow_specialty: solo los reclutas de la Intendencia pueden venir ya especializados
## (Economy.RECRUIT_SPECIALTY_CHANCE). El primer recluta gratis nunca.
static func make_recruit(rng: RandomNumberGenerator = null, allow_specialty: bool = false) -> TroopCard:
	rng = _rng(rng)
	var c := _base_card(rng)
	var commons: Array[WeaponData] = []
	var rares: Array[WeaponData] = []
	for w in recruit_weapon_options():
		if w.rarity == 0:
			commons.append(w)
		else:
			rares.append(w)
	var pool: Array[WeaponData] = rares if (not rares.is_empty() and rng.randf() < Economy.RECRUIT_RARE_WEAPON_CHANCE) else commons
	if pool.is_empty():
		pool = recruit_weapons()
	c.weapons.assign([pool[rng.randi_range(0, pool.size() - 1)]])
	c.equipped_weapon = 0
	if rng.randf() < Economy.RECRUIT_ITEM_CHANCE:
		var items: Array = []
		var weights: Array = []
		for it in GameContent.items():
			if it.rarity <= 1 and c.can_add_item(it):
				items.append(it)
				weights.append(LevelUpSystem.rarity_weight(it.rarity))
		var i := LevelUpSystem.weighted_index(weights, rng)
		if i >= 0:
			c.add_item(items[i])
	if allow_specialty and rng.randf() < Economy.RECRUIT_SPECIALTY_CHANCE:
		var specs := SpecialtyProgression.available_specialties() # solo las desbloqueadas
		if not specs.is_empty():
			c.specialty = specs[rng.randi_range(0, specs.size() - 1)]
	return c


## Precio de reclutamiento (40–70) según arma y variaciones de Vida/Daño.
static func recruit_price(card: TroopCard) -> int:
	var price := 48.0
	var w := card.get_weapon()
	if w:
		match w.family:
			WeaponData.Family.PISTOLA: price += 0.0
			WeaponData.Family.ESCOPETA: price += 4.0
			WeaponData.Family.AUTOMATICA: price += 6.0
			_: price += 8.0
		price += w.rarity * 6.0
	price += (card.base_health / BASE_HEALTH - 1.0) * 60.0
	price += (card.base_damage / BASE_DAMAGE - 1.0) * 90.0
	return clampi(roundi(price), MIN_PRICE, MAX_PRICE)


## v4.1: armas de los enemigos = la misma variedad que los reclutas (incluido el cuchillo, que carga
## cuerpo a cuerpo), solo las desbloqueadas a esa ronda (min_round). Antes solo pistola/subfusil/
## fusil/escopeta y los enemigos parecían "quietos" frente a un jugador que sí lleva tropas de choque.
static func enemy_weapon_options(round_num: int) -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w in recruit_weapon_options():
		if w.min_round <= maxi(1, round_num):
			out.append(w)
	if out.is_empty():
		out = recruit_weapons()
	return out


## Nivel de un enemigo según la ronda (≈ 1 + ronda/3, tope 10).
static func enemy_level(round_num: int, is_elite: bool = false, is_boss_leader: bool = false) -> int:
	var lv := 1 + floori(round_num / ENEMY_ROUNDS_PER_LEVEL) # v4: +1 nivel cada 5 rondas (antes 4)
	if is_elite:
		lv += 1
	if is_boss_leader:
		lv += BOSS_EXTRA_LEVELS
	return clampi(lv, 1, TroopCard.MAX_LEVEL)


## Enemigo escalado por ronda. Los multiplicadores de dificultad y de jefe los aplica combate.
static func make_enemy(round_num: int, is_elite: bool = false, is_boss_leader: bool = false, rng: RandomNumberGenerator = null) -> TroopCard:
	rng = _rng(rng)
	round_num = maxi(1, round_num)
	var c := _base_card(rng)
	c.is_boss = is_boss_leader
	c.is_enemy = true # sin mejoras de especialidad del perfil del jugador
	var pool := enemy_weapon_options(round_num)
	c.weapons.assign([pool[rng.randi_range(0, pool.size() - 1)]])
	var target := enemy_level(round_num, is_elite, is_boss_leader)
	while c.level < target:
		var offers := LevelUpSystem.roll_offers(c, rng, round_num, true)
		if offers.is_empty():
			c.level += 1
			continue
		var offer: Dictionary = offers[rng.randi_range(0, offers.size() - 1)]
		var equip := false
		if offer.type == "weapon" and c.specialty and c.specialty.is_affine(offer.resource) \
				and not c.specialty.is_affine(c.get_weapon()):
			equip = true
		LevelUpSystem.apply_offer(c, offer, equip)
		c.level += 1
		if offer.type == "specialty":
			_give_affine_weapon(c, round_num, rng)
	return c


## Cambia el arma por una de la familia afín disponible en esta ronda (si hay).
static func _give_affine_weapon(c: TroopCard, round_num: int, rng: RandomNumberGenerator) -> void:
	if c.specialty == null or c.specialty.is_affine(c.get_weapon()):
		return
	if round_num < AFFINE_WEAPON_MIN_ROUND: # PROVISIONAL (pre-balance QA)
		return
	var options: Array[WeaponData] = []
	var weights: Array = []
	for w in GameContent.weapons():
		if c.specialty.is_affine(w) and w.min_round <= round_num:
			options.append(w)
			weights.append(LevelUpSystem.rarity_weight(w.rarity))
	var i := LevelUpSystem.weighted_index(weights, rng)
	if i < 0:
		return
	c.weapons.assign([options[i]])
	c.equipped_weapon = 0
