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


## Habilidades generales (lista definitiva preliminar, 2026-10-10). Se ofrecen al subir de nivel.
## Orden por categoría: △ Daño · □ Tanque · S Movilidad · ○ Trampas y munición. Generadas con _dev/gen_skills.py.
const _SKILLS := [
	preload("res://Resources/Skills/ruleta_rusa.tres"),
	preload("res://Resources/Skills/bala_rebote.tres"),
	preload("res://Resources/Skills/gatillo_destino.tres"),
	preload("res://Resources/Skills/cadena_polvora.tres"),
	preload("res://Resources/Skills/todo_al_rojo.tres"),
	preload("res://Resources/Skills/deuda_sangre.tres"),
	preload("res://Resources/Skills/ni_muerto.tres"),
	preload("res://Resources/Skills/venganza.tres"),
	preload("res://Resources/Skills/imaginate_yo.tres"),
	preload("res://Resources/Skills/carne_canon.tres"),
	preload("res://Resources/Skills/ojo_por_ojo.tres"),
	preload("res://Resources/Skills/te_llevas_parte.tres"),
	preload("res://Resources/Skills/problema_matarme.tres"),
	preload("res://Resources/Skills/ultimo_en_pie.tres"),
	preload("res://Resources/Skills/esquiva.tres"),
	preload("res://Resources/Skills/no_me_pillas.tres"),
	preload("res://Resources/Skills/cambio_sitio.tres"),
	preload("res://Resources/Skills/panico_util.tres"),
	preload("res://Resources/Skills/paso_fantasma.tres"),
	preload("res://Resources/Skills/doble_recarga.tres"),
	preload("res://Resources/Skills/efecto_mariposa.tres"),
	preload("res://Resources/Skills/cargador_veloz.tres"),
	preload("res://Resources/Skills/trampas.tres"),
	preload("res://Resources/Skills/municion_fantasma.tres"),
	preload("res://Resources/Skills/pildora.tres"),
	preload("res://Resources/Skills/cable_trampa.tres"),
	preload("res://Resources/Skills/senuelo.tres"),
	preload("res://Resources/Skills/hacerse_muerto.tres"),
	preload("res://Resources/Skills/recarga_desesperada.tres"),
	preload("res://Resources/Skills/robo_cargador.tres"),
	preload("res://Resources/Skills/fondo_cargador.tres"),
	preload("res://Resources/Skills/duelo_sol.tres"),
	preload("res://Resources/Skills/segunda_piel.tres"),
	preload("res://Resources/Skills/trinchera.tres"),
	preload("res://Resources/Skills/inercia.tres"),
	preload("res://Resources/Skills/retirada_tactica.tres"),
	preload("res://Resources/Skills/balas_trazadoras.tres"),
	preload("res://Resources/Skills/cebo_explosivo.tres"),
]

## Habilidades antiguas, retiradas de forma PROVISIONAL: ya no se ofrecen ni salen en el Códice, pero se
## siguen cargando para que los veteranos guardados no pierdan las que ya tenían.
const _LEGACY_SKILLS := [
	preload("res://Resources/Skills/piel_dura.tres"),
	preload("res://Resources/Skills/pulso_firme.tres"),
	preload("res://Resources/Skills/ojo_certero.tres"),
	preload("res://Resources/Skills/velocista.tres"),
	preload("res://Resources/Skills/gatillo_facil.tres"),
	preload("res://Resources/Skills/recarga_rapida.tres"),
	preload("res://Resources/Skills/camuflaje.tres"),
	preload("res://Resources/Skills/sangre_fria.tres"),
	preload("res://Resources/Skills/cargador_ampliado.tres"),
	preload("res://Resources/Skills/oficial.tres"),
	preload("res://Resources/Skills/instinto_veterano.tres"),
	preload("res://Resources/Skills/mira_laser.tres"),
	preload("res://Resources/Skills/traje_ghillie.tres"),
	preload("res://Resources/Skills/cirujano.tres"),
	preload("res://Resources/Skills/autocuracion.tres"),
	preload("res://Resources/Skills/coordenadas_precisas.tres"),
	preload("res://Resources/Skills/enlace_tactico.tres"),
]

const _ITEMS := [
	preload("res://Resources/Items/balas_venenosas.tres"),
	preload("res://Resources/Items/balas_perforantes.tres"),
	preload("res://Resources/Items/balas_aturdidoras.tres"),
	preload("res://Resources/Items/chaleco_tactico.tres"),
	preload("res://Resources/Items/blindaje_pesado.tres"),
	preload("res://Resources/Items/granada.tres"),
	preload("res://Resources/Items/granada_cegadora.tres"),
	preload("res://Resources/Items/granada_gas.tres"),
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
	var s := _find(_SKILLS, id) as SkillData
	return s if s != null else _find(_LEGACY_SKILLS, id) as SkillData


static func find_item(id: String) -> ItemData:
	return _find(_ITEMS, id) as ItemData
