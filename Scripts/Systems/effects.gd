class_name Effects
extends RefCounted
## Comportamientos especiales de especialidades, habilidades y objetos (se despachan por effect_id).
## Cada tropa crea su propio Effects al empezar el combate; troop.gd llama a los ganchos.
##   on_fight_start · on_process(delta) · on_before_shot · on_hit · on_damaged · on_ally_died · on_kill
## v4 — mecánicas de especialidad (con sinergias entre ellas):
##   supresion (Soldado) · tirador_elite + paciencia (Francotirador) · primeros_auxilios + estabilizar (Médico)
##   radio (Radioperador: marcar y artillería)
## v6: Municionero y Zapador retirados; su código (reparto_municion, minas, carga_hueca) queda sin uso
##   por si se reaprovecha (p. ej. para el Saboteador). Mecánico, Infiltrado y Saboteador: sin mecánica aún.

const GRENADE_RANGE := 260.0      # alcance máximo del lanzamiento de la granada (objeto)
const GRENADE_FIRST_DELAY := 0.5  # la primera granada sale a la mitad del cooldown
const OFFICER_TICK := 0.25
const MINE_SCRIPT := preload("res://Scripts/Battle/mine.gd")
const MINE_SPACING := 44.0
const ARTILLERY_CLUSTER_RADIUS := 90.0
const ARTILLERY_SPREAD := 34.0
const SUPPRESS_TEXT_CD := 2.0
const ANTI_ARMOR_BOSS_MULT := 1.3

var troop: Node = null
var active: Dictionary = {}       # effect_id -> params (fusionados)
var botiquin_used: bool = false
var stabilize_used: bool = false
var artillery_done: bool = false
var marks_done: int = 0
var mines_placed: int = 0
var suppressions: int = 0
var grenades_thrown: int = 0
var heal_done: float = 0.0        # total curado por esta tropa (a sí misma o a aliados)
var _timers: Dictionary = {}
var _regen_shown: float = 0.0
var _regen_text_t: float = 0.0


func _init(t: Node) -> void:
	troop = t
	active = collect(t.card if t else null)


## Reúne los efectos de la especialidad, habilidades y objetos con sus parámetros.
## Si un efecto aparece dos veces (camuflaje + traje ghillie), se queda el mayor de cada parámetro.
static func collect(card: TroopCard) -> Dictionary:
	var out := {}
	if card == null:
		return out
	if card.specialty and card.specialty.passive_effect_id != "":
		_merge(out, card.specialty.passive_effect_id, card.specialty.passive_params)
	if card.specialty:
		for eid in card.specialty.extra_effects:
			_merge(out, String(eid), card.specialty.extra_effects[eid])
		# Mejoras de especialidad del perfil (meta-progresión): solo tropas del jugador
		if not card.is_enemy:
			var rank := SpecialtyProgression.current_rank(card.specialty.id)
			if rank > 0:
				var pe := SpecialtyProgression.effects_for(card.specialty.id, rank)
				for eid in pe:
					_merge(out, String(eid), pe[eid])
	for s in card.skills:
		if s and s.effect_id != "":
			_merge(out, s.effect_id, s.params)
	for it in card.items:
		if it and it.effect_id != "":
			_merge(out, it.effect_id, it.params)
	return out


static func _merge(out: Dictionary, id: String, params: Dictionary) -> void:
	if not out.has(id):
		out[id] = params.duplicate()
		return
	var cur: Dictionary = out[id]
	for k in params:
		var v = params[k]
		if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and cur.has(k):
			cur[k] = maxf(float(cur[k]), float(v))
		else:
			cur[k] = v


func has(id: String) -> bool:
	return active.has(id)


func p(id: String, key: String, default: float) -> float:
	return float(active.get(id, {}).get(key, default))


func _heal_mult() -> float:
	return float(troop.stats.get("heal_mult", 1.0))


func _allies(include_self: bool = false) -> Array:
	var out: Array = []
	for t in troop.get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(t) or t.is_queued_for_deletion() or t.has_meta("is_drag_preview"):
			continue
		if not ("team" in t) or t.team != troop.team or t.is_dead:
			continue
		if t == troop and not include_self:
			continue
		out.append(t)
	return out


# ---------------------------------------------------------------- ganchos

func on_fight_start() -> void:
	if has("camuflaje"):
		troop.camo_left = p("camuflaje", "duration", 3.0)
	if has("adrenalina"):
		var dur := p("adrenalina", "duration", 5.0)
		troop.add_buff("adrenalina", "fire_rate_pct", p("adrenalina", "fire_rate_pct", 0.4), dur)
		troop.add_buff("adrenalina_mov", "move_speed_pct", p("adrenalina", "move_speed_pct", 0.3), dur)
		troop.show_text("💉 ¡Adrenalina!", Color(1.0, 0.45, 0.3), 12, -6.0)
	if has("granada"):
		_timers["granada"] = p("granada", "cooldown", 6.0) * (1.0 - GRENADE_FIRST_DELAY)
	if has("primeros_auxilios"):
		_timers["primeros_auxilios"] = 0.0
	if has("oficial"):
		_timers["oficial"] = 0.0
	if has("reparto_municion"):
		_timers["municion"] = 0.0
	if has("radio"):
		_timers["radio_mark"] = p("radio", "mark_interval", 4.0) * 0.5
		_timers["artillery"] = 0.0
	if has("minas"):
		_place_mines()
	troop.update_visuals()


func on_process(delta: float) -> void:
	if has("primeros_auxilios"):
		_timers["primeros_auxilios"] += delta
		if _timers["primeros_auxilios"] >= p("primeros_auxilios", "interval", 4.0):
			if _first_aid():
				_timers["primeros_auxilios"] = 0.0
	if has("autocuracion"):
		_self_regen(delta)
	if has("oficial"):
		_timers["oficial"] += delta
		if _timers["oficial"] >= OFFICER_TICK:
			_timers["oficial"] = 0.0
			var r := p("oficial", "radius", 180.0)
			for a in _allies(false):
				if a.global_position.distance_to(troop.global_position) <= r:
					a.add_buff("oficial", "fire_rate_pct", p("oficial", "fire_rate_pct", 0.15), OFFICER_TICK * 2.0)
	if has("granada"):
		_timers["granada"] += delta
		# Sinergia: un Zapador lanza las granadas un 30 % más a menudo
		var gcd := p("granada", "cooldown", 6.0) * (0.7 if has("minas") else 1.0)
		if _timers["granada"] >= gcd:
			if _throw_grenade():
				_timers["granada"] = 0.0
	if has("reparto_municion"):
		_timers["municion"] += delta
		if _timers["municion"] >= OFFICER_TICK:
			_timers["municion"] = 0.0
			var rr := p("reparto_municion", "radius", 170.0)
			for a in _allies(false):
				if a.global_position.distance_to(troop.global_position) <= rr:
					a.add_buff("municion", "reload_pct", p("reparto_municion", "reload_pct", -0.3), OFFICER_TICK * 2.0)
	if has("radio"):
		_timers["radio_mark"] += delta
		if _timers["radio_mark"] >= p("radio", "mark_interval", 4.0):
			if _radio_mark():
				_timers["radio_mark"] = 0.0
		if not artillery_done:
			_timers["artillery"] += delta
			if _timers["artillery"] >= p("radio", "artillery_delay", 6.0) and _call_artillery():
				artillery_done = true


## Bonos para el disparo que va a salir: {accuracy, crit_chance, damage_pct}.
func on_before_shot() -> Dictionary:
	var b := {"accuracy": 0.0, "crit_chance": 0.0, "damage_pct": 0.0}
	if has("paciencia") and troop.still_time >= p("paciencia", "still_time", 1.0):
		b.accuracy += p("paciencia", "accuracy", 0.15)
		b.crit_chance += p("paciencia", "crit_chance", 0.10)
	if has("ultimo_en_pie") and _allies(false).is_empty():
		b.damage_pct += p("ultimo_en_pie", "damage_pct", 0.4)
	# Sinergia: el Tirador de élite remata a quien está suprimido (Soldado) o marcado (Radioperador)
	if has("tirador_elite"):
		var t = troop.target
		if t != null and is_instance_valid(t) and (t.suppressed_left > 0.0 or t.marked_left > 0.0):
			b.crit_chance += p("tirador_elite", "crit_vs_pinned", 0.25)
	return b


func on_hit(victim: Node, info: Dictionary) -> void:
	# Soldado: fuego de supresión — el blanco pierde precisión y velocidad un momento
	if has("supresion") and is_instance_valid(victim) and not victim.is_dead and not info.get("friendly_fire", false):
		var was: bool = victim.suppressed_left > 0.0
		victim.suppressed_left = maxf(victim.suppressed_left, p("supresion", "duration", 1.5))
		suppressions += 1
		if not was and Time.get_ticks_msec() - int(victim.get_meta("supp_txt", -99999)) > SUPPRESS_TEXT_CD * 1000.0:
			victim.set_meta("supp_txt", Time.get_ticks_msec())
			victim.show_text("😰 Suprimido", Color(0.8, 0.85, 1.0), 11, 8.0)


func on_damaged(_amount: float) -> void:
	if has("botiquin") and not botiquin_used and troop.health > 0.0 \
			and troop.health < troop.get_max_health() * p("botiquin", "threshold", 0.4):
		botiquin_used = true
		var healed: float = troop.heal(troop.get_max_health() * p("botiquin", "heal_pct", 0.35) * _heal_mult())
		heal_done += healed
		CombatFX.text(troop.get_parent(), troop.global_position + Vector2(0, -troop.overlay_top() - 30), "🩹 Botiquín", Color(0.5, 1.0, 0.6), 12)


func on_ally_died(_ally: Node) -> void:
	if has("venganza"):
		troop.add_buff("venganza", "fire_rate_pct", p("venganza", "fire_rate_pct", 0.3), p("venganza", "duration", 4.0))
		troop.add_buff("venganza_mov", "move_speed_pct", 0.15, p("venganza", "duration", 4.0))
		CombatFX.text(troop.get_parent(), troop.global_position + Vector2(0, -troop.overlay_top() - 30), "¡Venganza!", Color(1.0, 0.4, 0.3), 12)


func on_kill(_victim: Node) -> void:
	pass # gancho disponible para efectos futuros


# ---------------------------------------------------------------- efectos con lógica propia

## Médico: cura al aliado más herido (proporción de vida) dentro del radio. Devuelve true si curó.
func _first_aid() -> bool:
	var r := p("primeros_auxilios", "radius", 220.0)
	var best: Node = null
	var best_ratio := 1.0
	for a in _allies(true):
		if a.global_position.distance_to(troop.global_position) > r:
			continue
		var ratio: float = a.health / maxf(1.0, a.get_max_health())
		if ratio < best_ratio - 0.001:
			best_ratio = ratio
			best = a
	if best == null:
		return false
	var amount: float = best.get_max_health() * p("primeros_auxilios", "heal_pct", 0.06) * _heal_mult()
	heal_done += best.heal(amount)
	if best != troop:
		CombatFX.flash(troop.get_parent(), best.global_position, Color(0.4, 1.0, 0.5, 0.5), 22.0, 0.35)
	return true


func _self_regen(delta: float) -> void:
	var amount: float = troop.get_max_health() * p("autocuracion", "pct_per_sec", 0.02) * _heal_mult() * delta
	var healed: float = troop.heal(amount, false)
	heal_done += healed
	_regen_shown += healed
	_regen_text_t += delta
	if _regen_text_t >= 1.0:
		_regen_text_t = 0.0
		if _regen_shown >= 0.5:
			troop.show_heal_text(_regen_shown)
		_regen_shown = 0.0


## Lanza la granada al objetivo actual si está a tiro. Devuelve true si la lanzó.
func _throw_grenade() -> bool:
	var tgt = troop.target
	if tgt == null or not is_instance_valid(tgt) or tgt.is_dead:
		return false
	var reach := maxf(GRENADE_RANGE, float(troop.stats.get("attack_range", 0.0)))
	if troop.global_position.distance_to(tgt.global_position) > reach:
		return false
	var dmg: float = p("granada", "damage", 30.0) * float(troop.stats.get("damage_mult", 1.0))
	troop.throw_grenade(tgt, dmg, p("granada", "radius", 70.0))
	grenades_thrown += 1
	return true


# ---------------------------------------------------------------- v4: especialidades

## Médico (Estabilizar): la primera vez en el combate que un aliado cercano iba a caer, queda a
## 1 PV y recibe una cura grande. Lo llama troop.take_damage antes de morir. Devuelve true si salvó.
static func try_stabilize(victim: Node) -> bool:
	if victim == null or not is_instance_valid(victim):
		return false
	for t in victim.get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(t) or t.is_dead or t == victim or not ("team" in t) or t.team != victim.team:
			continue
		var e: Effects = t.effects
		if e == null or not e.has("estabilizar") or e.stabilize_used:
			continue
		if t.global_position.distance_to(victim.global_position) > e.p("estabilizar", "radius", 220.0):
			continue
		e.stabilize_used = true
		victim.health = 1.0
		var healed: float = victim.heal(victim.get_max_health() * e.p("estabilizar", "heal_pct", 0.25) * e._heal_mult())
		e.heal_done += healed
		victim.show_text("🩺 ¡Estabilizado!", Color(0.5, 1.0, 0.6), 13, -16.0)
		CombatFX.flash(victim.get_parent(), victim.global_position, Color(0.4, 1.0, 0.5, 0.6), 30.0, 0.4)
		return true
	return false


## Zapador: coloca sus minas delante de su casilla (hacia el enemigo), en su carril.
func _place_mines() -> void:
	var n: int = int(p("minas", "count", 1.0)) + int(p("mas_minas", "extra", 0.0))
	# v4.1: la mina va en MITAD del campo, en la fila (carril) del zapador: es por donde pasan
	# los dos bandos al chocar, no delante de su casilla (allí casi nunca llega el enemigo)
	var mid_x: float = troop.field_rect(troop.get_tree()).get_center().x
	var parent: Node = troop.get_parent()
	if parent == null:
		return
	for i in n:
		var m = MINE_SCRIPT.new()
		m.team = troop.team
		m.owner_troop = troop
		m.damage = p("minas", "damage", 45.0) * float(troop.stats.get("damage_mult", 1.0))
		m.radius = p("minas", "radius", 70.0)
		m.trigger_radius = p("minas", "trigger", 30.0)
		m.visible_to_player = troop.team == 0
		var off_y := (float(i) - (n - 1) * 0.5) * MINE_SPACING
		m.position = Vector2(mid_x, troop.global_position.y + off_y)
		parent.add_child(m)
		mines_placed += 1


## Radioperador: marca al enemigo más peligroso a su alcance de radio. Marcado = recibe más daño
## de todos, pierde el camuflaje y atrae el fuego (los aliados lo prefieren como objetivo).
func _radio_mark() -> bool:
	var rng_ := p("radio", "mark_range", 450.0)
	var best: Node = null
	var best_v := -1.0
	for t in troop.get_tree().get_nodes_in_group("troops"):
		if not is_instance_valid(t) or t.is_dead or t.has_meta("is_drag_preview") or not ("team" in t) or t.team == troop.team:
			continue
		if t.global_position.distance_to(troop.global_position) > rng_:
			continue
		var v: float = t.threat_value()
		if v > best_v:
			best_v = v
			best = t
	if best == null:
		return false
	best.marked_left = p("radio", "mark_duration", 4.0) + p("enlace", "mark_duration", 0.0)
	best.marked_bonus = maxf(best.marked_bonus, p("radio", "mark_bonus", 0.15) + p("enlace", "mark_bonus", 0.0))
	best.camo_left = 0.0
	best.update_visuals()
	marks_done += 1
	best.show_text("📡 Marcado", Color(1.0, 0.45, 0.35), 11, 8.0)
	CombatFX.flash(best.get_parent(), best.global_position, Color(1.0, 0.25, 0.2, 0.45), 26.0, 0.4)
	return true


## Radioperador: una vez por combate pide fuego de artillería sobre el grupo enemigo más denso.
## Los proyectiles caen tras un aviso y solo dañan al enemigo.
func _call_artillery() -> bool:
	var enemies: Array = []
	for t in troop.get_tree().get_nodes_in_group("troops"):
		if is_instance_valid(t) and not t.is_dead and not t.has_meta("is_drag_preview") and "team" in t and t.team != troop.team:
			enemies.append(t)
	if enemies.is_empty():
		return false
	var best: Node = enemies[0]
	var best_n := -1
	for e in enemies:
		var n := 0
		for o in enemies:
			if o.global_position.distance_to(e.global_position) <= ARTILLERY_CLUSTER_RADIUS:
				n += 1
		if n > best_n:
			best_n = n
			best = e
	var center: Vector2 = best.global_position
	var shells: int = int(p("radio", "shells", 3.0)) + int(p("coordenadas", "extra_shells", 0.0))
	var dmg: float = p("radio", "shell_damage", 26.0) * float(troop.stats.get("damage_mult", 1.0)) * (1.0 + p("coordenadas", "damage_pct", 0.0))
	var radius := p("radio", "shell_radius", 60.0)
	var parent: Node = troop.get_parent()
	var tree := troop.get_tree()
	var team: int = troop.team
	var att = troop
	troop.show_text("📡 ¡Artillería en camino!", Color(1.0, 0.8, 0.35), 12, -6.0)
	CombatFX.flash(parent, center, Color(1.0, 0.3, 0.2, 0.25), 70.0, 0.9)
	for i in shells:
		var pos := center + Vector2(randf_range(-ARTILLERY_SPREAD, ARTILLERY_SPREAD), randf_range(-ARTILLERY_SPREAD, ARTILLERY_SPREAD))
		tree.create_timer(0.8 + 0.25 * i, false).timeout.connect(func():
			if not is_instance_valid(parent):
				return
			CombatFX.explosion(parent, pos, radius)
			for e in CombatFX.enemies_in_radius(tree, pos, radius, team):
				var f := clampf(e.global_position.distance_to(pos) / radius, 0.0, 1.0)
				CombatFX.apply_hit(e, {"damage": dmg * lerpf(1.0, 0.35, f), "crit": false, "lethal": false,
						"attacker": att if is_instance_valid(att) else null, "artillery": true}))
	return true

