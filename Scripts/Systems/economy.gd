class_name Economy
extends RefCounted
## Única fuente de constantes de economía (SPEC v3). El equilibrado solo toca este archivo.

const STARTING_COINS := 15
const STARTING_POINTS := 1
# Monedas por baja enemiga
const COINS_PER_KILL := 1          # v4: antes 2 (progresión más lenta, partidas de ~30 rondas)
const COINS_PER_KILL_ELITE := 2
const COINS_PER_KILL_BOSS := 4
const WIN_BONUS_COINS := 2
const INTEREST_STEP := 10
const INTEREST_MAX := 2
# Puntos de Mando por ronda ganada
const POINTS_PER_WIN := 1          # v4: 1 PM por ronda (antes 2): solo 1–2 tropas llegan a Nv. 10
const POINTS_PER_WIN_ELITE := 2    # élite y Jefe de Sector
const CLEAN_WIN_BONUS_POINTS := 0 # v4: sin bonus (antes +1)
# Coste en PM para pasar de nivel L a L+1 (índice = L)
const LEVEL_COST := [0, 1, 1, 2, 2, 3, 3, 4, 4, 5]
# Precios de la Intendencia (índice = rareza 0..3)
const ITEM_PRICE := [6, 10, 15, 22]
const WEAPON_PRICE := [9, 12, 15, 18]
const SELL_RATIO := 0.5
const REROLL_BASE := 1
const EQUIPMENT_OFFERS := 4
const WEAPON_OFFER_CHANCE := 0.3
## Bono por rango de entrenamiento a vida y daño.
const TRAINING_BONUS := 0.06
# Precio de recluta en monedas: precio clásico (40–70) / divisor, acotado
const RECRUIT_PRICE_DIVISOR := 3.3
const RECRUIT_PRICE_MIN := 13
const RECRUIT_PRICE_MAX := 19
# Reclutas que vienen con un objeto: probabilidad y cuánto del precio del objeto se cobra (≈25 % de descuento)
const RECRUIT_ITEM_CHANCE := 0.35
const RECRUIT_ITEM_PRICE_FACTOR := 0.75
# Reclutas: probabilidad de que el arma inicial sea rara en vez de común
const RECRUIT_RARE_WEAPON_CHANCE := 0.25
# Reclutas de la Intendencia que ya vienen con especialidad (nunca el primer recluta gratis) y su recargo
const RECRUIT_SPECIALTY_CHANCE := 0.2
const RECRUIT_SPECIALTY_PRICE := 4

# Mejora de armas con PM: nivel 1 (base) a 4. Coste en PM para pasar del nivel L al L+1 (índice = L).
const WEAPON_MAX_LEVEL := 4
const WEAPON_UPGRADE_COST := [0, 1, 2, 3]
const WEAPON_UPGRADE_DAMAGE := 0.04 # +4 % de daño por mejora en todas las armas (suave)

# Subida de nivel: probabilidad de que salga una 3.ª mejora para elegir
const THIRD_OFFER_CHANCE := 0.035

# Impacto letal: probabilidad muy baja por disparo; mata al instante salvo a los jefes (×3 de daño)
const LETHAL_CHANCE := 0.004
const LETHAL_BOSS_MULT := 3.0

# Jefe de Sector (cada 10 rondas): vida FIJA y conocida por nivel de sector (10, 20, 30, 40…)
const SUBBOSS_HP := [360, 650, 1050, 1550]
const SUBBOSS_HP_STEP := 500 # a partir del 5.º sector, +500 por sector


## Rareza máxima ofertada en la Intendencia según la ronda.
static func max_shop_rarity(round_num: int) -> int:
	if round_num < 4:
		return 1
	if round_num < 8:
		return 2
	return 3


## Pesos de rareza de habilidades según el nivel al que se sube.
static func skill_rarity_weights(target_level: int) -> Array:
	if target_level <= 3:
		return [60, 30, 10, 5]
	if target_level <= 6:
		return [40, 35, 18, 7]
	return [25, 35, 27, 13]


## PM para pasar del nivel `level` al siguiente (0 si ya es el máximo).
## Tipo de combate élite (mismo texto que GameStateManager.ELITE_TYPE).
const ELITE_NODE := "Batalla Élite"
const SUBBOSS_NODE := "Jefe de Sector"


static func level_cost(level: int) -> int:
	if level < 1 or level >= TroopCard.MAX_LEVEL:
		return 0
	return LEVEL_COST[level]


static func coins_for_kill(enemy_card: TroopCard, node_type: String) -> int:
	if enemy_card != null and enemy_card.is_boss:
		return COINS_PER_KILL_BOSS
	if node_type == ELITE_NODE:
		return COINS_PER_KILL_ELITE
	return COINS_PER_KILL


## Precio de un recluta: base por arma y estadísticas + 75 % del precio de cada objeto que traiga
## (sale más barato que comprar el objeto aparte: incentivo) + recargo si ya trae especialidad.
static func recruit_price(card: TroopCard) -> int:
	var base: int = clampi(roundi(UnitFactory.recruit_price(card) / RECRUIT_PRICE_DIVISOR), RECRUIT_PRICE_MIN, RECRUIT_PRICE_MAX)
	return base + recruit_extras_surcharge(card)


## Suplemento del precio de un recluta por lo que trae de serie (objetos y especialidad).
static func recruit_extras_surcharge(card: TroopCard) -> int:
	var extra := 0
	if card and card.specialty != null:
		extra += RECRUIT_SPECIALTY_PRICE
	if card:
		for it in card.items:
			if it is ItemData:
				extra += roundi(ITEM_PRICE[clampi(it.rarity, 0, ITEM_PRICE.size() - 1)] * RECRUIT_ITEM_PRICE_FACTOR)
	return extra


static func price_of(res: Resource) -> int:
	if res == null:
		return 0
	if res is TroopCard:
		return recruit_price(res)
	if res is WeaponData:
		return WEAPON_PRICE[clampi(res.rarity, 0, WEAPON_PRICE.size() - 1)]
	if res is ItemData:
		return ITEM_PRICE[clampi(res.rarity, 0, ITEM_PRICE.size() - 1)]
	return 0


static func sell_price(res: Resource) -> int:
	return maxi(1, floori(price_of(res) * SELL_RATIO))


static func reroll_price(reroll_count: int) -> int:
	return REROLL_BASE + maxi(0, reroll_count)


static func interest_for(coins: int) -> int:
	return clampi(floori(float(maxi(0, coins)) / float(INTEREST_STEP)), 0, INTEREST_MAX)


static func points_for_win(node_type: String, clean: bool) -> int:
	var p := POINTS_PER_WIN_ELITE if node_type == ELITE_NODE or node_type == SUBBOSS_NODE else POINTS_PER_WIN
	if clean:
		p += CLEAN_WIN_BONUS_POINTS
	return p


## Coste en PM de mejorar un arma que está en el nivel `level` (0 si ya está al máximo).
static func weapon_upgrade_cost(level: int) -> int:
	if level < 1 or level >= WEAPON_MAX_LEVEL:
		return 0
	return WEAPON_UPGRADE_COST[level]


## Modificadores (claves de TroopStats) que da un arma mejorada `ranks` veces (nivel - 1).
## Suaves y distintos por familia: no cambian el arma, solo la pulen un poco.
static func weapon_upgrade_mods(w: WeaponData, ranks: int) -> Dictionary:
	if w == null or ranks <= 0:
		return {}
	var r := float(ranks)
	var m := {"damage_pct": WEAPON_UPGRADE_DAMAGE * r}
	match w.family:
		WeaponData.Family.PISTOLA: m["accuracy"] = 0.03 * r
		WeaponData.Family.AUTOMATICA: m["magazine_pct"] = 0.08 * r
		WeaponData.Family.ESCOPETA: m["fire_rate_pct"] = 0.04 * r
		WeaponData.Family.PRECISION: m["range_pct"] = 0.05 * r
		WeaponData.Family.PESADA: m["reload_pct"] = -0.06 * r
		WeaponData.Family.EXPLOSIVO: m["aoe_pct"] = 0.06 * r
		WeaponData.Family.CUERPO_A_CUERPO: m["move_speed_pct"] = 0.05 * r
	return m


## Texto corto de lo que mejora cada nivel de esa arma.
static func weapon_upgrade_hint(w: WeaponData) -> String:
	if w == null:
		return ""
	var extra := ""
	match w.family:
		WeaponData.Family.PISTOLA: extra = "+3 % precisión"
		WeaponData.Family.AUTOMATICA: extra = "+8 % cargador"
		WeaponData.Family.ESCOPETA: extra = "+4 % cadencia"
		WeaponData.Family.PRECISION: extra = "+5 % alcance"
		WeaponData.Family.PESADA: extra = "−6 % tiempo de recarga"
		WeaponData.Family.EXPLOSIVO: extra = "+6 % radio de explosión"
		WeaponData.Family.CUERPO_A_CUERPO: extra = "+5 % movimiento"
	return "+%d %% daño y %s por nivel" % [roundi(WEAPON_UPGRADE_DAMAGE * 100.0), extra]


## Vida fija del Jefe de Sector de la ronda (no depende de la variación ni del rendimiento).
static func subboss_hp(round_num: int) -> float:
	var tier: int = maxi(1, round_num / 10)
	if tier <= SUBBOSS_HP.size():
		return float(SUBBOSS_HP[tier - 1])
	return float(SUBBOSS_HP[-1] + (tier - SUBBOSS_HP.size()) * SUBBOSS_HP_STEP)
