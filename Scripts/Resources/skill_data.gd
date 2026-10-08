class_name SkillData
extends Resource
## Habilidad PASIVA intrínseca: no ocupa hueco de objeto.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var emoji: String = "⭐"
@export var rarity: int = 0
@export var requires: Array[String] = []  # ids de habilidades necesarias
@export var stackable: bool = false
@export var modifiers: Dictionary = {}    # SPEC sección 3
@export var effect_id: String = ""        # comportamiento especial (effects.gd); "" = solo modificadores
@export var params: Dictionary = {}
