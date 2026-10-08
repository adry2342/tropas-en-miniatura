class_name SpecialtyData
extends Resource
## Especialidad que la tropa elige al llegar a Nv. 5 (o con la que ya viene algún recluta de la Intendencia) (deja de ser Recluta).

@export var id: String = ""               # "soldado","medico"(Doctor),"comunicaciones"(Radioperador),"mecanico","infiltrado","vigia","saboteador"
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var emoji: String = "⭐"
@export var color: Color = Color.WHITE    # color del nombre sobre la tropa y en la UI
@export var texture: Texture2D            # opcional; null = sprite del recluta
@export var affine_families: Array[int] = [] # valores de WeaponData.Family
@export var passive_name: String = ""
@export_multiline var passive_description: String = ""
@export var passive_effect_id: String = "" # se resuelve en effects.gd (combate)
@export var passive_params: Dictionary = {} # parámetros del efecto pasivo (p. ej. {interval=4.0})
@export var modifiers: Dictionary = {}    # modificadores pasivos fijos (SPEC sección 3)
## v4: efectos adicionales {effect_id: params} (una especialidad puede tener varias mecánicas)
@export var extra_effects: Dictionary = {}
## v4: texto de sinergias para la UI (con quién combina bien)
@export_multiline var synergy_text: String = ""


func is_affine(weapon: WeaponData) -> bool:
	return weapon != null and int(weapon.family) in affine_families
