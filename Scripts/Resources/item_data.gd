class_name ItemData
extends Resource
## Objeto o equipo: ocupa 1 de los 3 huecos de la tropa.

enum Slot { MUNICION, ARMADURA, UTILIDAD } # máx. 1 MUNICION y 1 ARMADURA por tropa

const SLOT_NAMES := ["Munición", "Armadura", "Utilidad"]

@export var id: String = ""
@export var display_name: String = "Objeto"
@export_multiline var description: String = ""
@export var emoji: String = "🎒"
@export var rarity: int = 0
@export var icon: Texture2D
@export var slot: Slot = Slot.UTILIDAD
@export var modifiers: Dictionary = {}
@export var effect_id: String = ""        # p. ej. "granada", "botiquin", "adrenalina"
@export var params: Dictionary = {}       # p. ej. {cooldown=6.0, damage=30.0, radius=70.0}


func get_slot_name() -> String:
	return SLOT_NAMES[slot]
