class_name SkillData
extends Resource
## Habilidad PASIVA intrínseca: no ocupa hueco de objeto.
## Desde 2026-10-10 cada habilidad pertenece a una de las 4 categorías (símbolo en la interfaz):
##   △ Daño · □ Tanque / vida · S Movilidad / esquiva · ○ Trampas, sigilo y munición.

enum Category { DANO, TANQUE, MOVILIDAD, UTILIDAD }


const CATEGORY_NAMES: Array[String] = ["Daño", "Tanque", "Movilidad", "Trampas y munición"]
## Símbolo de texto (para tooltips y textos). En la interfaz se dibuja con CategoryBadge.
const CATEGORY_SYMBOLS: Array[String] = ["△", "□", "S", "○"]
const CATEGORY_COLORS: Array[Color] = [
	Color(1.0, 0.42, 0.32),   # △ rojo
	Color(0.45, 0.85, 0.45),  # □ verde
	Color(0.4, 0.8, 1.0),     # S cian
	Color(1.0, 0.78, 0.3),    # ○ ámbar
]

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var emoji: String = "⭐"
@export var rarity: int = 0
@export var category: Category = Category.DANO
@export var requires: Array[String] = []  # ids de habilidades necesarias
@export var stackable: bool = false
## true = los enemigos no la reciben al subir de nivel (mecánicas que serían injustas contra el jugador).
@export var player_only: bool = false
## "" = cualquiera · "magazine" = solo si lleva un arma con cargador · "bullets" = solo con un arma de bala.
@export var needs: String = ""
@export var modifiers: Dictionary = {}    # SPEC sección 3 (en puntos)
@export var effect_id: String = ""        # comportamiento especial (effects.gd / skill_effects.gd); "" = solo modificadores
@export var params: Dictionary = {}


func get_category_name() -> String:
	return CATEGORY_NAMES[clampi(int(category), 0, CATEGORY_NAMES.size() - 1)]


func get_category_symbol() -> String:
	return CATEGORY_SYMBOLS[clampi(int(category), 0, CATEGORY_SYMBOLS.size() - 1)]


func get_category_color() -> Color:
	return CATEGORY_COLORS[clampi(int(category), 0, CATEGORY_COLORS.size() - 1)]


static func category_color(c: int) -> Color:
	return CATEGORY_COLORS[clampi(c, 0, CATEGORY_COLORS.size() - 1)]
