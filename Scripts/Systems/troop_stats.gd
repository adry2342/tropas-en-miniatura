class_name TroopStats
extends RefCounted
## Única fuente de verdad de las estadísticas finales de una tropa (combate y UI).

const LEVEL_HEALTH := 0.15
const LEVEL_DAMAGE := 0.10
const BASE_MOVE_SPEED := 90.0
const MIN_MOVE_SPEED := 30.0
## Afinidad arma/especialidad, en puntos de Daño y de Precisión.
const AFFINITY_DAMAGE := 15.0
const AFFINITY_ACCURACY := 10.0
## Todas las estadísticas se miden en PUNTOS (nunca en %):
##  - Daño, Cadencia, Curación y Veneno: 100 puntos = lo base del arma; cada punto suma una centésima
##    (+15 de daño → el arma pega 115/100). Precisión, Armadura y Evasión: 0–100 puntos.
##  - Vida, Alcance (px), Cargador (balas), Recarga (s), Movilidad y radio de Explosión (px): se suman tal cual.
const PTS := 100.0
## Veneno (balas venenosas): cada impacto añade a la "reserva" del blanco `poison_pct` × su daño, que se
## le va restando en POISON_DURATION s (cada impacto nuevo reinicia la cuenta). Ignora la armadura y el
## envenenado recibe POISON_HEAL_CUT menos curación. Al ser proporcional al daño, es igual de justo con una
## escopeta (muchos perdigones) que con un rifle o una ametralladora.
const POISON_DURATION := 3.0
const POISON_HEAL_CUT := 0.5
const MAX_ARMOR := 0.6
const MAX_DODGE := 0.5
const MIN_ACCURACY := 0.05
const MAX_ACCURACY := 0.98

## Claves de modificador válidas y su texto para la UI (SPEC sección 3).
const MODIFIER_KEYS := [
	"health", "damage", "fire_rate", "accuracy", "range", "magazine", "reload", "move_speed",
	"armor", "dodge", "aoe", "pierce", "poison", "heal", "suppress_hit",
]
## Claves que solo tienen sentido con munición (se ignoran fuera de las armas de bala).
const AMMO_ONLY_KEYS := ["poison", "pierce", "suppress_hit"]

static var _fallback_weapon: WeaponData = null


## Suma los modificadores de especialidad (+ sus mejoras del perfil, solo tropas del jugador) + habilidades
## + objetos + munición. `weapon`: arma para la que se calculan (null = la principal del card).
## La munición solo cuenta con armas de bala: un cuchillo o una bazuca no "disparan" balas venenosas.
static func collect_modifiers(card: TroopCard, weapon: WeaponData = null) -> Dictionary:
	var total := {}
	var sources: Array = []
	if card.specialty:
		sources.append(card.specialty.modifiers)
		if not card.is_enemy:
			var rank := SpecialtyProgression.current_rank(card.specialty.id)
			if rank > 0:
				sources.append(SpecialtyProgression.modifiers_for(card.specialty.id, rank))
	for s in card.skills:
		if s:
			sources.append(s.modifiers)
	for it in card.items:
		if it:
			sources.append(it.modifiers)
	var ew: WeaponData = weapon if weapon != null else card.get_weapon()
	if card.ammo and uses_ammo(ew):
		sources.append(card.ammo.modifiers)
	# Mejoras del arma equipada (PM): suaves y según la familia
	if ew:
		sources.append(Economy.weapon_upgrade_mods(ew, card.get_weapon_level(ew) - 1))
	for mods in sources:
		for k in mods:
			total[k] = float(total.get(k, 0.0)) + float(mods[k])
	if not uses_ammo(ew):
		for k in AMMO_ONLY_KEYS:
			total.erase(k)
	return total


## true si el arma dispara balas (le afecta la munición). Cuchillo, bazuca y lanzagranadas no.
static func uses_ammo(w: WeaponData) -> bool:
	return w != null and w.projectile == WeaponData.Projectile.BALA


static func has_affinity(card: TroopCard, weapon: WeaponData = null) -> bool:
	if weapon == null:
		weapon = card.get_weapon()
	return card.specialty != null and card.specialty.is_affine(weapon)


## Estadísticas finales con el arma `weapon` (null = la principal, card.get_weapon()).
## En combate cada arma del arsenal tiene las suyas (la tropa cambia de arma si se queda sin balas).
static func compute(card: TroopCard, weapon: WeaponData = null) -> Dictionary:
	var w: WeaponData = weapon if weapon != null else card.get_weapon()
	if w == null:
		if _fallback_weapon == null:
			_fallback_weapon = WeaponData.new()
			_fallback_weapon.display_name = "Puños"
		w = _fallback_weapon
	var m := collect_modifiers(card, null if w == _fallback_weapon else w)
	var affinity := has_affinity(card, w)
	var lv: int = maxi(card.level, 1) - 1
	var ranks: int = card.training_ranks

	var max_health: float = card.base_health * (1.0 + LEVEL_HEALTH * lv) + m.get("health", 0.0) \
			+ Economy.TRAINING_HEALTH * ranks + card.get_skill_health()
	var damage_pts: float = m.get("damage", 0.0) + (AFFINITY_DAMAGE if affinity else 0.0) + Economy.TRAINING_DAMAGE * ranks
	var damage_mult: float = card.base_damage * (1.0 + LEVEL_DAMAGE * lv) * maxf(0.1, 1.0 + damage_pts / PTS)
	var move_speed: float = maxf(MIN_MOVE_SPEED, BASE_MOVE_SPEED * w.move_speed_mult + m.get("move_speed", 0.0))
	var range_add: float = m.get("range", 0.0)
	var accuracy: float = clampf(w.accuracy + (m.get("accuracy", 0.0) + (AFFINITY_ACCURACY if affinity else 0.0)) / PTS,
			MIN_ACCURACY, MAX_ACCURACY)
	var magazine: int = 0
	if w.magazine > 0:
		magazine = maxi(1, w.magazine + roundi(m.get("magazine", 0.0)))
	var poison_pct: float = maxf(0.0, m.get("poison", 0.0) / PTS)
	var attack_range: float = maxf(20.0, w.attack_range + range_add)

	var s := {
		"max_health": max_health,
		"damage_mult": damage_mult,
		"move_speed": move_speed,
		"attack_range": attack_range,
		"fire_rate": maxf(0.05, w.fire_rate * (1.0 + m.get("fire_rate", 0.0) / PTS)),
		"fire_rate_pts": PTS + m.get("fire_rate", 0.0), # Cadencia en puntos (100 = la base del arma)
		"accuracy": accuracy,
		"optimal_range": clampf(w.optimal_range + range_add, 0.0, attack_range),
		"accuracy_falloff": w.accuracy_falloff,
		"close_bonus": w.close_bonus,
		"min_range": w.min_range,
		"fire_on_move": w.fire_on_move,
		"magazine": magazine,
		"reload_time": maxf(0.1, w.reload_time + m.get("reload", 0.0)),
		"pellets": maxi(1, w.pellets),
		"aoe_radius": maxf(10.0, w.aoe_radius + m.get("aoe", 0.0)) if w.aoe_radius > 0.0 else 0.0,
		"poison_pct": poison_pct, # fracción del daño de cada impacto que se añade como veneno
		"poison_duration": POISON_DURATION if poison_pct > 0.0 else 0.0,
		"armor": clampf(m.get("armor", 0.0) / PTS, 0.0, MAX_ARMOR),
		"dodge": clampf(m.get("dodge", 0.0) / PTS, 0.0, MAX_DODGE),
		"pierce": int(round(m.get("pierce", 0.0))),
		"suppress_hit": m.get("suppress_hit", 0.0), # s de supresión que deja cada impacto (balas aturdidoras)
		"weapon_damage": w.damage,
		"affinity": affinity,
		# Extras (no están en la SPEC, útiles para combate/UI)
		"heal_mult": maxf(0.0, 1.0 + m.get("heal", 0.0) / PTS), # multiplica las curaciones que hace la tropa
		"weapon": w,
		"modifiers": m,
	}
	s["hit_damage"] = w.damage * damage_mult
	s["direct_dps"] = estimate_direct_dps(s)
	s["poison_dps"] = s.direct_dps * poison_pct # a la larga, el veneno suma `poison_pct` × el daño directo
	s["dps"] = s.direct_dps + s.poison_dps
	return s


## DPS total estimado (directo + veneno). Para mostrar en la UI.
static func estimate_dps(s: Dictionary) -> float:
	return estimate_direct_dps(s) * (1.0 + float(s.get("poison_pct", 0.0)))


## DPS teórico de los impactos (con precisión a distancia óptima y recarga), sin el veneno.
static func estimate_direct_dps(s: Dictionary) -> float:
	var w: WeaponData = s.get("weapon") as WeaponData
	var landed: float = s.pellets * s.accuracy
	var stack: float = 1.0 + (w.pellet_stack_bonus if w else 0.0) * maxf(0.0, landed - 1.0)
	var per_shot: float = s.hit_damage * landed * stack
	var rate: float = s.fire_rate
	if s.magazine > 0:
		var cycle: float = s.magazine / s.fire_rate + s.reload_time
		rate = s.magazine / cycle
	return per_shot * rate


## Valor en puntos (fracción interna × 100), sin "%".
static func _pts(v: float) -> String:
	return "%d" % roundi(v * PTS)


## Texto corto de un diccionario de modificadores ("+15 de vida, +10 de cadencia").
static func describe_modifiers(mods: Dictionary) -> String:
	var parts: Array[String] = []
	for k in mods:
		var v: float = float(mods[k])
		match k:
			"health": parts.append("%+d de vida" % roundi(v))
			"damage": parts.append("%+d de daño" % roundi(v))
			"fire_rate": parts.append("%+d de cadencia" % roundi(v))
			"accuracy": parts.append("%+d de precisión" % roundi(v))
			"range": parts.append("%+d de alcance" % roundi(v))
			"magazine": parts.append("%+d de cargador" % roundi(v))
			"reload": parts.append(("%+.2f" % v).rstrip("0").rstrip(".").replace(".", ",") + " s de recarga")
			"move_speed": parts.append("%+d de movilidad" % roundi(v))
			"armor": parts.append("%+d de armadura" % roundi(v))
			"dodge": parts.append("%+d de evasión" % roundi(v))
			"aoe": parts.append("%+d de radio de explosión" % roundi(v))
			"pierce": parts.append("atraviesa %d enemigo(s)" % roundi(v))
			"poison": parts.append("%+d de veneno" % roundi(v))
			"heal": parts.append("%+d de curación" % roundi(v))
			"suppress_hit": parts.append(("los impactos suprimen %.1f s" % v).replace(".", ","))
			_: parts.append("%s %+.2f" % [k, v])
	return ", ".join(parts).replace("+-", "−").replace("-", "−")


## Líneas legibles con las estadísticas finales, para la UI.
static func describe(card: TroopCard) -> Array[String]:
	var s := compute(card)
	var w: WeaponData = s.weapon
	var lines: Array[String] = []
	lines.append("❤ Vida: %d" % roundi(s.max_health))
	lines.append("💥 Daño: %s" % _pts(s.damage_mult))
	var arma := "%s (%s)" % [w.display_name, w.get_family_name()]
	if s.affinity:
		arma += " · afín"
	lines.append("Arma: " + arma)
	var golpe := "%d" % roundi(s.hit_damage)
	if s.pellets > 1:
		golpe = "%d × %d" % [s.pellets, roundi(s.hit_damage)]
	lines.append("Impacto: %s · cadencia %d (%.1f disparos/s)" % [golpe, roundi(s.fire_rate_pts), s.fire_rate])
	lines.append("Precisión: %s" % _pts(s.accuracy))
	lines.append("Alcance: %d px (óptimo %d)" % [roundi(s.attack_range), roundi(s.optimal_range)])
	if s.magazine > 0:
		lines.append("Cargador: %d · recarga %.1f s" % [s.magazine, s.reload_time])
	else:
		lines.append("Cargador: ∞")
	if s.aoe_radius > 0.0:
		lines.append("Explosión: radio %d" % roundi(s.aoe_radius))
	if s.poison_pct > 0.0:
		lines.append("🧪 Veneno: %s (≈ %.1f/s en %.0f s)" % [_pts(s.poison_pct), s.poison_dps, s.poison_duration])
	if s.armor > 0.0:
		lines.append("Armadura: %s" % _pts(s.armor))
	if s.dodge > 0.0:
		lines.append("Evasión: %s" % _pts(s.dodge))
	if s.pierce > 0:
		lines.append("Atraviesa: %d enemigo(s)" % s.pierce)
	if s.suppress_hit > 0.0:
		lines.append("😰 Suprime al impactar: %.1f s" % s.suppress_hit)
	lines.append("Munición: %s%s" % [card.get_ammo_name(), "" if uses_ammo(w) else " (no la usa)"])
	if s.heal_mult != 1.0:
		lines.append("Curación: %s" % _pts(s.heal_mult))
	lines.append("Movilidad: %d" % roundi(s.move_speed))
	lines.append("DPS estimado: %.1f" % s.dps)
	return lines
