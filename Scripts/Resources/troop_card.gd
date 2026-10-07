class_name TroopCard
extends Resource
## Estado persistente de UNA tropa (en el tablero o en la reserva). Todo sale de aquí.

const MAX_ITEM_SLOTS := 3
const MAX_LEVEL := 10
## Nivel al que una tropa del jugador elige especialidad (v3.2: antes Nv. 2).
const SPECIALTY_LEVEL := 5
## Los enemigos siguen especializándose pronto (su escalado está equilibrado así).
const ENEMY_SPECIALTY_LEVEL := 2

@export var unit_name: String = "Recluta"
@export var base_health: float = 100.0    # Vida base (±10 % al reclutar)
@export var base_damage: float = 1.0      # Daño = multiplicador (1.0 = 100 %)
@export var level: int = 1
@export var specialty: SpecialtyData = null # null = Recluta
@export var weapons: Array[WeaponData] = [] # arsenal (≥1)
@export var equipped_weapon: int = 0      # índice en weapons
@export var items: Array[ItemData] = []   # máx. MAX_ITEM_SLOTS
@export var skills: Array[SkillData] = []
@export var pending_offers: Array = []    # ofertas pagadas sin elegir: [{type, resource}]
@export var is_boss: bool = false
## true en las tropas enemigas (UnitFactory.make_enemy): no reciben las mejoras de especialidad del perfil.
@export var is_enemy: bool = false
@export var training_ranks: int = 0     # rangos de entrenamiento (+6 % vida y daño cada uno)
@export var weapon_levels: Dictionary = {} # id de arma -> nivel de mejora (1..Economy.WEAPON_MAX_LEVEL); sin entrada = 1

var display_name: String:
	get:
		return unit_name


func get_weapon() -> WeaponData:
	if weapons.is_empty():
		return null
	return weapons[clampi(equipped_weapon, 0, weapons.size() - 1)]


func get_specialty_name() -> String:
	return specialty.display_name if specialty else "Recluta"


func get_title() -> String:
	return "%s · %s" % [unit_name, get_specialty_name()]


func has_skill(skill_id: String) -> bool:
	for s in skills:
		if s and s.id == skill_id:
			return true
	return false


func has_item(item_id: String) -> bool:
	for it in items:
		if it and it.id == item_id:
			return true
	return false


func has_weapon(weapon_id: String) -> bool:
	for w in weapons:
		if w and w.id == weapon_id:
			return true
	return false


## Huecos libres + máx. 1 MUNICION y 1 ARMADURA + sin duplicados.
func can_add_item(item: ItemData) -> bool:
	if item == null or items.size() >= MAX_ITEM_SLOTS or has_item(item.id):
		return false
	if item.slot != ItemData.Slot.UTILIDAD:
		for it in items:
			if it and it.slot == item.slot:
				return false
	return true


func add_item(item: ItemData) -> bool:
	if not can_add_item(item):
		return false
	items.append(item)
	return true


## Quita el objeto y lo devuelve a la reserva del jugador (GameStateManager.player_bench).
func remove_item(item: ItemData) -> bool:
	if item == null or not item in items:
		return false
	items.erase(item)
	var gsm: Node = null
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		gsm = (loop as SceneTree).root.get_node_or_null("/root/GameStateManager")
	if gsm:
		gsm.add_item(item)
	return true


## Nivel de mejora de un arma del arsenal (1 si nunca se mejoró).
func get_weapon_level(w: WeaponData = null) -> int:
	if w == null:
		w = get_weapon()
	if w == null:
		return 1
	return clampi(int(weapon_levels.get(w.id, 1)), 1, Economy.WEAPON_MAX_LEVEL)


## Coste en PM de mejorar esa arma (0 si está al máximo).
func get_weapon_upgrade_cost(w: WeaponData = null) -> int:
	return Economy.weapon_upgrade_cost(get_weapon_level(w))


func can_upgrade_weapon(w: WeaponData = null) -> bool:
	if w == null:
		w = get_weapon()
	return w != null and has_weapon(w.id) and get_weapon_level(w) < Economy.WEAPON_MAX_LEVEL


func get_level_up_cost() -> int:
	return Economy.level_cost(level) # En Puntos de Mando


func can_level_up() -> bool:
	return level < MAX_LEVEL and pending_offers.is_empty()


## Copia profunda segura: los arrays son nuevos, los recursos de contenido se comparten.
func duplicate_card() -> TroopCard:
	var c := TroopCard.new()
	c.unit_name = unit_name
	c.base_health = base_health
	c.base_damage = base_damage
	c.level = level
	c.specialty = specialty
	c.weapons = weapons.duplicate()
	c.equipped_weapon = equipped_weapon
	c.items = items.duplicate()
	c.skills = skills.duplicate()
	for o in pending_offers:
		c.pending_offers.append((o as Dictionary).duplicate() if o is Dictionary else o)
	c.is_boss = is_boss
	c.is_enemy = is_enemy
	c.weapon_levels = weapon_levels.duplicate()
	c.training_ranks = training_ranks
	return c
