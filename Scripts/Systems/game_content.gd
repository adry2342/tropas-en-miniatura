class_name GameContent
extends RefCounted
## Catálogo explícito de todo el contenido (preload, sin escanear carpetas).
## Generado por el agente nucleo: si añades un .tres, añádelo también aquí.

const _WEAPONS := [
	preload("res://Resources/Weapons/pistola.tres"),
	preload("res://Resources/Weapons/subfusil.tres"),
	preload("res://Resources/Weapons/fusil_asalto.tres"),
	preload("res://Resources/Weapons/escopeta.tres"),
	preload("res://Resources/Weapons/cuchillo.tres"),
	preload("res://Resources/Weapons/rifle_francotirador.tres"),
	preload("res://Resources/Weapons/ametralladora.tres"),
	preload("res://Resources/Weapons/bazuca.tres"),
]

## v6: Soldado, Doctor (id "medico"), Radioperador (id "comunicaciones"), Mecánico, Infiltrado,
## Vigía y Saboteador. Mecánico, Infiltrado y Saboteador aún no tienen mecánica.
const _SPECIALTIES := [
	preload("res://Resources/Specialties/soldado.tres"),
	preload("res://Resources/Specialties/medico.tres"),
	preload("res://Resources/Specialties/comunicaciones.tres"),
	preload("res://Resources/Specialties/mecanico.tres"),
	preload("res://Resources/Specialties/infiltrado.tres"),
	preload("res://Resources/Specialties/vigia.tres"),
	preload("res://Resources/Specialties/saboteador.tres"),
]


const _SKILLS := [
	preload("res://Resources/Skills/piel_dura.tres"),
	preload("res://Resources/Skills/pulso_firme.tres"),
	preload("res://Resources/Skills/ojo_certero.tres"),
	preload("res://Resources/Skills/velocista.tres"),
	preload("res://Resources/Skills/esquiva.tres"),
	preload("res://Resources/Skills/gatillo_facil.tres"),
	preload("res://Resources/Skills/recarga_rapida.tres"),
	preload("res://Resources/Skills/camuflaje.tres"),
	preload("res://Resources/Skills/ultimo_en_pie.tres"),
	preload("res://Resources/Skills/venganza.tres"),
	preload("res://Resources/Skills/sangre_fria.tres"),
	preload("res://Resources/Skills/cargador_ampliado.tres"),
	preload("res://Resources/Skills/oficial.tres"),
	preload("res://Resources/Skills/instinto_veterano.tres"),
	preload("res://Resources/Skills/mira_laser.tres"),
	preload("res://Resources/Skills/bala_perforante.tres"),
	preload("res://Resources/Skills/traje_ghillie.tres"),
	preload("res://Resources/Skills/cirujano.tres"),
	preload("res://Resources/Skills/autocuracion.tres"),
	preload("res://Resources/Skills/coordenadas_precisas.tres"),
	preload("res://Resources/Skills/enlace_tactico.tres"),
]

const _ITEMS := [
	preload("res://Resources/Items/balas_huecas.tres"),
	preload("res://Resources/Items/balas_incendiarias.tres"),
	preload("res://Resources/Items/balas_perforantes.tres"),
	preload("res://Resources/Items/chaleco_tactico.tres"),
	preload("res://Resources/Items/blindaje_pesado.tres"),
	preload("res://Resources/Items/granada.tres"),
	preload("res://Resources/Items/botiquin.tres"),
	preload("res://Resources/Items/inyector_adrenalina.tres"),
	preload("res://Resources/Items/mira_telescopica.tres"),
]


static func weapons() -> Array[WeaponData]:
	var a: Array[WeaponData] = []
	a.assign(_WEAPONS)
	return a


static func specialties() -> Array[SpecialtyData]:
	var a: Array[SpecialtyData] = []
	a.assign(_SPECIALTIES)
	return a


static func skills() -> Array[SkillData]:
	var a: Array[SkillData] = []
	a.assign(_SKILLS)
	return a


static func items() -> Array[ItemData]:
	var a: Array[ItemData] = []
	a.assign(_ITEMS)
	return a


static func _find(list: Array, id: String) -> Resource:
	for r in list:
		if r and r.id == id:
			return r
	return null


static func find_weapon(id: String) -> WeaponData:
	return _find(_WEAPONS, id) as WeaponData


static func find_specialty(id: String) -> SpecialtyData:
	return _find(_SPECIALTIES, id) as SpecialtyData


static func find_skill(id: String) -> SkillData:
	return _find(_SKILLS, id) as SkillData


static func find_item(id: String) -> ItemData:
	return _find(_ITEMS, id) as ItemData
