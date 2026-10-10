class_name ItemData
extends Resource
## Objeto o equipo. ARMADURA y UTILIDAD ocupan 1 de los 3 huecos de la tropa (máx. 1 armadura);
## MUNICION va en su propio hueco (TroopCard.ammo): cargar otra sustituye a la que hubiera.

enum Slot { MUNICION, ARMADURA, UTILIDAD }

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
