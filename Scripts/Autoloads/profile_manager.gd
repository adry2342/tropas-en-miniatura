extends Node
## Perfil persistente FUERA de las runs (user://profile.json).
##  - Bóveda del Cuartel: hasta VAULT_SIZE tropas veteranas. Solo se consiguen venciendo al Jefe Final
##    (1 tropa por victoria, elegida entre las supervivientes de la run).
##  - Con la bóveda completa se desbloquea el modo de juego nuevo (aún sin implementar).
## Las tropas se guardan por ids de contenido (GameContent), no por rutas: sobreviven a cambios de carpetas.
##  - Medallas de mando (🏅) y rangos de especialidad (SpecialtyProgression): meta-progresión entre runs.
##    Las medallas se ganan al derrotar cada jefe (GameStateManager.apply_victory_rewards) y se gastan en el árbol de cada especialidad.

signal vault_changed
## Cambian las medallas o algún rango de especialidad.
signal progress_changed
## Se desbloqueó una especialidad al alcanzar un hito (llegar a un Jefe de Sector, vencer al Jefe Final…).
signal specialty_unlocked(sp: SpecialtyData)

## El juego exportado (.exe) y las pruebas desde Godot (F5) comparten la carpeta user://
## (%APPDATA%/Godot/app_userdata/Tropas en miniatura), así que usan archivos distintos:
## lo que guardes probando en el editor no aparece en el juego exportado, y al revés.
const SAVE_PATH_RELEASE := "user://profile.json"
const SAVE_PATH_EDITOR := "user://profile_dev.json"
## v2: medallas + rangos de especialidad (los perfiles v1 se siguen cargando: valen 0).
const SAVE_VERSION := 2
const VAULT_SIZE := 5

var vault: Array[TroopCard] = []
var final_boss_wins: int = 0
## Medallas de mando (🏅): moneda persistente para el árbol de especialidades.
var medals: int = 0
## id de especialidad -> rango desbloqueado (0..SpecialtyProgression.MAX_RANK). Sin entrada = 0.
var specialty_ranks: Dictionary = {}
## Hitos alcanzados ("sector_1", "final_boss"…). Un hito deja su especialidad LISTA para desbloquear;
## el jugador la desbloquea a mano en el Centro de mando (terminal), nunca a mitad de una run.
var milestones: Array = []
## Especialidades desbloqueadas de verdad (las únicas que se pueden usar). El Soldado siempre.
var unlocked_specialties: Array = ["soldado"]
## PROVISIONAL (botón de Configuración para pruebas): todo desbloqueado, incluido el hangar.
var dev_unlock_all: bool = false
## Tests: nunca borrar archivos del disco (delete_save solo limpia la memoria).
var test_mode: bool = false
## Solo para tests/herramientas: trata todas las especialidades como desbloqueadas.
var all_specialties_unlocked: bool = false
## Especialidades desbloqueadas durante la run en curso (el panel de fin de partida las anuncia).
var recent_unlocks: Array[SpecialtyData] = []
## false en los tests: no toca el disco.
var persist: bool = true


func _ready() -> void:
	_migrate_old_editor_save()
	load_profile()


## Archivo de perfil de esta ejecución (editor o juego exportado).
static func save_path() -> String:
	return SAVE_PATH_EDITOR if OS.has_feature("editor") else SAVE_PATH_RELEASE


## Hasta v5.0 el editor guardaba en profile.json, el mismo archivo que el .exe. La primera vez que se
## ejecuta desde Godot, ese perfil de pruebas pasa a profile_dev.json y el .exe queda limpio.
func _migrate_old_editor_save() -> void:
	if not persist or not OS.has_feature("editor"):
		return
	if FileAccess.file_exists(SAVE_PATH_EDITOR) or not FileAccess.file_exists(SAVE_PATH_RELEASE):
		return
	if DirAccess.rename_absolute(SAVE_PATH_RELEASE, SAVE_PATH_EDITOR) == OK:
		print("ProfileManager: perfil de pruebas movido a ", SAVE_PATH_EDITOR)


# ---------------------------------------------------------------- bóveda

func is_vault_full() -> bool:
	return vault.size() >= VAULT_SIZE


func is_new_mode_unlocked() -> bool:
	return dev_unlock_all or vault.size() >= VAULT_SIZE


## Guarda una COPIA de la tropa en la bóveda. `replace_index` >= 0 sustituye ese hueco (bóveda llena).
## Devuelve true si se guardó.
func store_troop(card: TroopCard, replace_index: int = -1) -> bool:
	if card == null:
		return false
	var c := prepare_for_vault(card)
	if replace_index >= 0 and replace_index < vault.size():
		vault[replace_index] = c
	elif not is_vault_full():
		vault.append(c)
	else:
		return false
	_changed()
	return true


## Elimina un veterano de la bóveda (botón del Cuartel). Devuelve true si estaba.
func remove_troop(card: TroopCard) -> bool:
	var i := vault.find(card)
	if i < 0:
		return false
	vault.remove_at(i)
	_changed()
	return true


## Copia limpia para el Cuartel: sin ofertas de nivel pendientes (no se pueden elegir fuera de la run).
static func prepare_for_vault(card: TroopCard) -> TroopCard:
	var c := card.duplicate_card()
	c.pending_offers.clear()
	c.is_boss = false
	return c


## Llamar UNA vez al derrotar al Jefe Final.
func register_final_boss_win() -> void:
	final_boss_wins += 1
	reach_milestone("final_boss")
	_changed()


## ¿Puede usar el jugador esta especialidad? Solo si ya la desbloqueó en el Centro de mando.
func is_specialty_unlocked(id: String) -> bool:
	if all_specialties_unlocked or dev_unlock_all:
		return true
	return id in unlocked_specialties or SpecialtyProgression.unlock_milestone(id) == ""


## Hito alcanzado pero aún sin desbloquear: se puede desbloquear en el terminal del Centro de mando.
func is_specialty_claimable(id: String) -> bool:
	if is_specialty_unlocked(id):
		return false
	var m := SpecialtyProgression.unlock_milestone(id)
	return m != "" and m in milestones


func claimable_specialties() -> Array[SpecialtyData]:
	var out: Array[SpecialtyData] = []
	for sp in GameContent.specialties():
		if is_specialty_claimable(sp.id):
			out.append(sp)
	return out


## Desbloqueo manual (terminal del Centro de mando). Devuelve true si se desbloqueó.
func claim_specialty(id: String) -> bool:
	if not is_specialty_claimable(id):
		return false
	unlocked_specialties.append(id)
	print("Especialidad desbloqueada en el Centro de mando: ", id)
	save_profile()
	progress_changed.emit()
	return true


## PROVISIONAL (pruebas): desbloquea todas las especialidades, todos los hitos, el hangar y da medallas.
func dev_unlock_everything() -> void:
	dev_unlock_all = true
	for u in SpecialtyProgression.UNLOCKS:
		if u.milestone != "" and not u.milestone in milestones:
			milestones.append(u.milestone)
		if not u.id in unlocked_specialties:
			unlocked_specialties.append(u.id)
	medals += 999
	save_profile()
	vault_changed.emit()
	progress_changed.emit()


## PROVISIONAL (pruebas): borra la partida guardada (archivo incluido) y deja el perfil como nuevo.
func delete_save() -> void:
	clear_profile()
	var path := ProjectSettings.globalize_path(save_path())
	if not test_mode and FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(path)
	print("Partida guardada borrada: ", path)


## Marca un hito: su especialidad queda LISTA para desbloquear (se anuncia). No cambia la run en curso.
func reach_milestone(milestone: String) -> Array[SpecialtyData]:
	var out: Array[SpecialtyData] = []
	if milestone == "" or milestone in milestones:
		return out
	milestones.append(milestone)
	for id in SpecialtyProgression.ids_for_milestone(milestone):
		var sp := GameContent.find_specialty(id)
		if sp:
			out.append(sp)
			recent_unlocks.append(sp)
			print("Especialidad lista para desbloquear: %s (%s)" % [sp.display_name, milestone])
			specialty_unlocked.emit(sp)
	save_profile()
	progress_changed.emit()
	return out


## Devuelve y vacía la lista de desbloqueos pendientes de anunciar.
func take_recent_unlocks() -> Array[SpecialtyData]:
	var out := recent_unlocks.duplicate()
	recent_unlocks.clear()
	return out


## Avisa de un cambio hecho desde fuera (p. ej. el arma equipada de un veterano) y guarda.
func notify_changed() -> void:
	_changed()


func clear_profile() -> void:
	vault.clear()
	final_boss_wins = 0
	medals = 0
	specialty_ranks.clear()
	milestones.clear()
	unlocked_specialties = ["soldado"]
	dev_unlock_all = false
	recent_unlocks.clear()
	_changed()
	progress_changed.emit()


# ---------------------------------------------------------------- medallas y especialidades

## Rango desbloqueado de una especialidad (0 = solo la especialidad base).
func get_rank(id: String) -> int:
	return clampi(int(specialty_ranks.get(id, 0)), 0, SpecialtyProgression.MAX_RANK)


## Coste en medallas del siguiente rango (0 si ya está al máximo o la especialidad no existe).
func next_cost(id: String) -> int:
	var r := get_rank(id)
	if r >= SpecialtyProgression.MAX_RANK:
		return 0
	return SpecialtyProgression.cost(id, r + 1)


func can_unlock_next(id: String) -> bool:
	if not is_specialty_unlocked(id): # especialidad aún bloqueada (hitos)
		return false
	var r := get_rank(id)
	if r >= SpecialtyProgression.MAX_RANK or SpecialtyProgression.node(id, r + 1).is_empty():
		return false
	return medals >= next_cost(id)


## Gasta medallas y sube un rango. Guarda y avisa. Devuelve true si se desbloqueó.
func unlock_next(id: String) -> bool:
	if not can_unlock_next(id):
		return false
	medals -= next_cost(id)
	specialty_ranks[id] = get_rank(id) + 1
	save_profile()
	progress_changed.emit()
	return true


## Suma medallas (n <= 0 no hace nada). Guarda y avisa.
func add_medals(n: int, reason: String = "") -> void:
	if n <= 0:
		return
	medals += n
	print("Medallas de mando %+d (%s) | Total: %d" % [n, reason, medals])
	save_profile()
	progress_changed.emit()


func _changed() -> void:
	save_profile()
	vault_changed.emit()


# ---------------------------------------------------------------- guardado

func save_profile() -> void:
	if not persist:
		return
	var data := {
		"version": SAVE_VERSION,
		"final_boss_wins": final_boss_wins,
		"medals": medals,
		"specialty_ranks": specialty_ranks.duplicate(),
		"reached_milestones": milestones.duplicate(),
		"unlocked_specialties": unlocked_specialties.duplicate(),
		"dev_unlock_all": dev_unlock_all,
		"vault": vault.map(func(c): return card_to_dict(c)),
	}
	var f := FileAccess.open(save_path(), FileAccess.WRITE)
	if f == null:
		push_error("ProfileManager: no se pudo guardar %s" % save_path())
		return
	f.store_string(JSON.stringify(data, "\t"))


func load_profile() -> void:
	vault.clear()
	final_boss_wins = 0
	medals = 0
	specialty_ranks.clear()
	milestones.clear()
	unlocked_specialties = ["soldado"]
	dev_unlock_all = false
	if not persist or not FileAccess.file_exists(save_path()):
		progress_changed.emit()
		return
	var txt := FileAccess.get_file_as_string(save_path())
	var data = JSON.parse_string(txt)
	if not data is Dictionary:
		push_warning("ProfileManager: perfil ilegible, se empieza de cero")
		progress_changed.emit()
		return
	final_boss_wins = int(data.get("final_boss_wins", 0))
	apply_progress_dict(data) # v1 no tiene estas claves → 0
	# v7.2: "reached_milestones" (la clave antigua "milestones" se ignora: todo empieza bloqueado)
	var ms = data.get("reached_milestones", [])
	if ms is Array:
		for m in ms:
			if not str(m) in milestones:
				milestones.append(str(m))
	var us = data.get("unlocked_specialties", [])
	if us is Array:
		for id in us:
			var sp := GameContent.find_specialty(str(id))
			if sp and not sp.id in unlocked_specialties:
				unlocked_specialties.append(sp.id)
	dev_unlock_all = bool(data.get("dev_unlock_all", false))
	for d in data.get("vault", []):
		var c := card_from_dict(d)
		if c and vault.size() < VAULT_SIZE:
			vault.append(c)
	vault_changed.emit()
	progress_changed.emit()


## Medallas y rangos en formato del archivo (para guardar / tests de ida y vuelta sin disco).
func progress_to_dict() -> Dictionary:
	return {"medals": medals, "specialty_ranks": specialty_ranks.duplicate()}


## Lee medallas y rangos de un diccionario del archivo. Claves ausentes (perfil v1) → 0.
## Ids desconocidos se ignoran.
func apply_progress_dict(data: Dictionary) -> void:
	medals = maxi(0, int(data.get("medals", 0)))
	specialty_ranks.clear()
	var sr = data.get("specialty_ranks", {})
	if sr is Dictionary:
		for k in sr:
			var sp := GameContent.find_specialty(str(k))
			if sp == null:
				continue
			specialty_ranks[sp.id] = clampi(int(sr[k]), 0, SpecialtyProgression.MAX_RANK)


static func card_to_dict(c: TroopCard) -> Dictionary:
	return {
		"unit_name": c.unit_name,
		"base_health": c.base_health,
		"base_damage": c.base_damage,
		"level": c.level,
		"specialty": c.specialty.id if c.specialty else "",
		"weapons": c.weapons.filter(func(w): return w != null).map(func(w): return w.id),
		"equipped_weapon": c.equipped_weapon,
		"items": c.items.filter(func(i): return i != null).map(func(i): return i.id),
		"skills": c.skills.filter(func(s): return s != null).map(func(s): return s.id),
		"training_ranks": c.training_ranks,
		"weapon_levels": c.weapon_levels.duplicate(),
	}


## Reconstruye una tropa. Contenido que ya no existe se ignora; sin armas → null.
static func card_from_dict(d) -> TroopCard:
	if not d is Dictionary:
		return null
	var c := TroopCard.new()
	c.unit_name = str(d.get("unit_name", "Veterano"))
	c.base_health = float(d.get("base_health", 100.0))
	c.base_damage = float(d.get("base_damage", 1.0))
	c.level = clampi(int(d.get("level", 1)), 1, TroopCard.MAX_LEVEL)
	var sp := str(d.get("specialty", ""))
	c.specialty = GameContent.find_specialty(sp) if sp != "" else null
	for id in d.get("weapons", []):
		var w := GameContent.find_weapon(str(id))
		if w:
			c.weapons.append(w)
	if c.weapons.is_empty():
		return null
	c.equipped_weapon = clampi(int(d.get("equipped_weapon", 0)), 0, c.weapons.size() - 1)
	for id in d.get("items", []):
		var it := GameContent.find_item(str(id))
		if it and c.items.size() < TroopCard.MAX_ITEM_SLOTS:
			c.items.append(it)
	for id in d.get("skills", []):
		var s := GameContent.find_skill(str(id))
		if s:
			c.skills.append(s)
	c.training_ranks = int(d.get("training_ranks", 0))
	var wl = d.get("weapon_levels", {})
	if wl is Dictionary:
		for k in wl:
			c.weapon_levels[str(k)] = int(wl[k])
	return c
