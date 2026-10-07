class_name SpecialtyProgression
extends RefCounted
## Meta-progresión de especialidades (persistente entre runs; el rango de cada una lo guarda ProfileManager).
##
## Cada especialidad tiene un ÁRBOL VERTICAL sin ramas:
##   rango 0 = la especialidad tal cual (siempre "desbloqueada")
##   rangos 1..MAX_RANK = mejoras que se compran en orden, de abajo arriba, con Medallas de mando (🏅).
## Las mejoras se aplican SOLO a las tropas del jugador (TroopCard.is_enemy == false) con esa especialidad.
##
## ─── CÓMO RELLENAR LAS MEJORAS (diseño) ───────────────────────────────────────────────────────────
## Edita DEFAULT_TREES. Cada especialidad (id de GameContent) es una lista de MAX_RANK nodos, del rango 1
## (abajo, el primero que se compra) al rango 4 (arriba). Cada nodo es un diccionario:
##   "name":        texto corto que se ve en el árbol ("Mejora I", "Vendas de campaña"…)
##   "description": una frase con lo que hace
##   "cost":        Medallas de mando que cuesta desbloquearlo
##   "modifiers":   modificadores de estadística que SUMA este rango, con las mismas claves que
##                  TroopStats.MODIFIER_KEYS (p. ej. {"health_pct": 0.10, "accuracy": 0.05})
##   "effects":     efectos especiales {effect_id: params}, igual que SpecialtyData.extra_effects
##                  (se resuelven en effects.gd; p. ej. {"autocuracion": {"hps": 2.0}})
## Los rangos se ACUMULAN: con rango 3 la tropa tiene los modificadores de los nodos 1, 2 y 3 sumados
## (y los efectos de los tres fusionados: si un efecto se repite, gana el mayor de cada parámetro).
## ──────────────────────────────────────────────────────────────────────────────────────────────────

const MAX_RANK := 4
const DEFAULT_COSTS: Array[int] = [3, 5, 8, 12]
const PENDING_TEXT := "Mejora pendiente de definir"

## Medallas de mando al terminar una run (ganes o pierdas).
const MEDALS_ROUNDS_PER_MEDAL := 5   # 1 medalla por cada 5 rondas ganadas
const MEDALS_PER_SUBBOSS := 2        # por cada Jefe de Sector derrotado
const MEDALS_FINAL_BOSS := 5         # por derrotar al Jefe Final

const DEFAULT_TREES := {
	"soldado": [
		{"name": "Mejora I", "description": PENDING_TEXT, "cost": 3, "modifiers": {}, "effects": {}},
		{"name": "Mejora II", "description": PENDING_TEXT, "cost": 5, "modifiers": {}, "effects": {}},
		{"name": "Mejora III", "description": PENDING_TEXT, "cost": 8, "modifiers": {}, "effects": {}},
		{"name": "Mejora IV", "description": PENDING_TEXT, "cost": 12, "modifiers": {}, "effects": {}},
	],
	"medico": [ # Doctor
		{"name": "Mejora I", "description": PENDING_TEXT, "cost": 3, "modifiers": {}, "effects": {}},
		{"name": "Mejora II", "description": PENDING_TEXT, "cost": 5, "modifiers": {}, "effects": {}},
		{"name": "Mejora III", "description": PENDING_TEXT, "cost": 8, "modifiers": {}, "effects": {}},
		{"name": "Mejora IV", "description": PENDING_TEXT, "cost": 12, "modifiers": {}, "effects": {}},
	],
	"comunicaciones": [ # Radioperador
		{"name": "Mejora I", "description": PENDING_TEXT, "cost": 3, "modifiers": {}, "effects": {}},
		{"name": "Mejora II", "description": PENDING_TEXT, "cost": 5, "modifiers": {}, "effects": {}},
		{"name": "Mejora III", "description": PENDING_TEXT, "cost": 8, "modifiers": {}, "effects": {}},
		{"name": "Mejora IV", "description": PENDING_TEXT, "cost": 12, "modifiers": {}, "effects": {}},
	],
	"mecanico": [
		{"name": "Mejora I", "description": PENDING_TEXT, "cost": 3, "modifiers": {}, "effects": {}},
		{"name": "Mejora II", "description": PENDING_TEXT, "cost": 5, "modifiers": {}, "effects": {}},
		{"name": "Mejora III", "description": PENDING_TEXT, "cost": 8, "modifiers": {}, "effects": {}},
		{"name": "Mejora IV", "description": PENDING_TEXT, "cost": 12, "modifiers": {}, "effects": {}},
	],
	"infiltrado": [
		{"name": "Mejora I", "description": PENDING_TEXT, "cost": 3, "modifiers": {}, "effects": {}},
		{"name": "Mejora II", "description": PENDING_TEXT, "cost": 5, "modifiers": {}, "effects": {}},
		{"name": "Mejora III", "description": PENDING_TEXT, "cost": 8, "modifiers": {}, "effects": {}},
		{"name": "Mejora IV", "description": PENDING_TEXT, "cost": 12, "modifiers": {}, "effects": {}},
	],
	"francotirador": [
		{"name": "Mejora I", "description": PENDING_TEXT, "cost": 3, "modifiers": {}, "effects": {}},
		{"name": "Mejora II", "description": PENDING_TEXT, "cost": 5, "modifiers": {}, "effects": {}},
		{"name": "Mejora III", "description": PENDING_TEXT, "cost": 8, "modifiers": {}, "effects": {}},
		{"name": "Mejora IV", "description": PENDING_TEXT, "cost": 12, "modifiers": {}, "effects": {}},
	],
	"saboteador": [
		{"name": "Mejora I", "description": PENDING_TEXT, "cost": 3, "modifiers": {}, "effects": {}},
		{"name": "Mejora II", "description": PENDING_TEXT, "cost": 5, "modifiers": {}, "effects": {}},
		{"name": "Mejora III", "description": PENDING_TEXT, "cost": 8, "modifiers": {}, "effects": {}},
		{"name": "Mejora IV", "description": PENDING_TEXT, "cost": 12, "modifiers": {}, "effects": {}},
	],
}

## Árboles en uso (copia profunda de DEFAULT_TREES; los tests pueden retocarla y luego llamar a reset_trees()).
static var trees: Dictionary = DEFAULT_TREES.duplicate(true)


## Restaura los árboles por defecto.
static func reset_trees() -> void:
	trees = DEFAULT_TREES.duplicate(true)


## Nodos (rangos 1..MAX_RANK, de abajo arriba) de una especialidad. Especialidad desconocida → [].
static func nodes(id: String) -> Array:
	return trees.get(id, [])


## Nodo de un rango (1..MAX_RANK). Fuera de rango o especialidad desconocida → {}.
static func node(id: String, rank: int) -> Dictionary:
	var list := nodes(id)
	if rank < 1 or rank > list.size():
		return {}
	return list[rank - 1]


## Coste en Medallas de mando del nodo de ese rango (0 si no existe).
static func cost(id: String, rank: int) -> int:
	var n := node(id, rank)
	if n.is_empty():
		return 0
	return int(n.get("cost", DEFAULT_COSTS[clampi(rank - 1, 0, DEFAULT_COSTS.size() - 1)]))


## Suma de los modificadores de los nodos 1..rank.
static func modifiers_for(id: String, rank: int) -> Dictionary:
	var total := {}
	if rank <= 0:
		return total
	var list := nodes(id)
	for i in mini(rank, list.size()):
		var mods = list[i].get("modifiers", {})
		for k in mods:
			total[k] = float(total.get(k, 0.0)) + float(mods[k])
	return total


## Efectos fusionados de los nodos 1..rank (si un efecto se repite, gana el mayor de cada parámetro numérico).
static func effects_for(id: String, rank: int) -> Dictionary:
	var out := {}
	if rank <= 0:
		return out
	var list := nodes(id)
	for i in mini(rank, list.size()):
		var effs = list[i].get("effects", {})
		for eid in effs:
			var params: Dictionary = effs[eid] if effs[eid] is Dictionary else {}
			if not out.has(eid):
				out[eid] = params.duplicate()
				continue
			var cur: Dictionary = out[eid]
			for k in params:
				var v = params[k]
				if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and cur.has(k):
					cur[k] = maxf(float(cur[k]), float(v))
				else:
					cur[k] = v
	return out


# ---------------------------------------------------------------- desbloqueo de especialidades
## v7.1: en un perfil nuevo solo está el Soldado. Cada hito del juego desbloquea otra especialidad
## (una vez por perfil). Orden y hitos PROVISIONALES: se cambian aquí.
##   milestone: "" = desde el principio · "sector_N" = llegar al N.º Jefe de Sector (ronda 10·N)
##              "final_boss" = vencer al Jefe Final · "infinite_mode" = completar el Modo Infinito
const UNLOCKS := [
	{"id": "soldado", "milestone": "", "text": "Disponible desde el principio"},
	{"id": "medico", "milestone": "sector_1", "text": "Llega al 1.er Jefe de Sector (ronda 10)"},
	{"id": "comunicaciones", "milestone": "sector_2", "text": "Llega al 2.º Jefe de Sector (ronda 20)"},
	{"id": "francotirador", "milestone": "sector_3", "text": "Llega al 3.er Jefe de Sector (ronda 30)"},
	{"id": "infiltrado", "milestone": "final_boss", "text": "Vence al Jefe Final"},
	{"id": "mecanico", "milestone": "sector_4", "text": "Llega al 4.º Jefe de Sector (ronda 40)"},
	{"id": "saboteador", "milestone": "infinite_mode", "text": "Completa el Modo Infinito"},
]


## Hito que desbloquea una especialidad ("" = libre desde el principio).
static func unlock_milestone(id: String) -> String:
	for u in UNLOCKS:
		if u.id == id:
			return u.milestone
	return ""


## Texto de cómo se desbloquea (para la UI).
static func unlock_text(id: String) -> String:
	for u in UNLOCKS:
		if u.id == id:
			return u.text
	return ""


## Especialidades que desbloquea un hito.
static func ids_for_milestone(milestone: String) -> Array[String]:
	var out: Array[String] = []
	for u in UNLOCKS:
		if u.milestone == milestone and milestone != "":
			out.append(u.id)
	return out


## ¿Está desbloqueada en el perfil del jugador? Sin perfil (herramientas, simulador) → todas.
static func is_unlocked(id: String) -> bool:
	var pm := _profile()
	if pm == null or not pm.has_method("is_specialty_unlocked"):
		return true
	return bool(pm.is_specialty_unlocked(id))


## Especialidades que puede usar el jugador (reclutas especializados y elección en Nv. 5).
static func available_specialties() -> Array[SpecialtyData]:
	var out: Array[SpecialtyData] = []
	for sp in GameContent.specialties():
		if is_unlocked(sp.id):
			out.append(sp)
	return out


static func _profile() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree or (loop as SceneTree).root == null:
		return null
	return (loop as SceneTree).root.get_node_or_null("/root/ProfileManager")


## Medallas de mando que da una run: 1 por cada 5 rondas ganadas, 2 por Jefe de Sector y 5 por el Jefe Final.
static func medals_for_run(rounds_won: int, subbosses_defeated: int, final_boss_defeated: bool) -> int:
	@warning_ignore("integer_division")
	return maxi(0, rounds_won) / MEDALS_ROUNDS_PER_MEDAL + MEDALS_PER_SUBBOSS * maxi(0, subbosses_defeated) \
			+ (MEDALS_FINAL_BOSS if final_boss_defeated else 0)


## Rango actual de una especialidad según el perfil (autoload ProfileManager). Sin perfil → 0.
## Barato y seguro desde código estático (TroopStats, Effects).
static func current_rank(id: String) -> int:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return 0
	var root: Window = (loop as SceneTree).root
	if root == null:
		return 0
	var pm := root.get_node_or_null("/root/ProfileManager")
	if pm == null or not pm.has_method("get_rank"):
		return 0
	return int(pm.get_rank(id))
