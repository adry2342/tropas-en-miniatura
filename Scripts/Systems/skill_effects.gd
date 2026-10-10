class_name SkillEffects
extends RefCounted
## Habilidades generales con mecánica propia (lista del 2026-10-10). Cada tropa tiene la suya dentro de
## su Effects (effects.sk); troop.gd y Effects llaman a estos ganchos. Las 4 categorías:
##   △ Daño: ruleta_rusa · bala_rebote · gatillo_destino · cadena_polvora · todo_al_rojo · deuda_sangre
##   □ Tanque: ni_muerto · venganza_tiro · imaginate_yo · carne_canon · ojo_por_ojo · te_llevas_parte · problema_matarme
##   S Movilidad: ultimo_en_pie (en Effects) · esquive · no_me_pillas · cambio_sitio · panico_util · paso_fantasma
##   ○ Trampas/munición: doble_recarga · efecto_mariposa · cargador_veloz · trampas · municion_fantasma · pildora
##                       cable_trampa · senuelo · hacerse_muerto · recarga_desesperada · robo_cargador

const TROOP_SCENE_PATH := "res://Scenes/Troops/troop.tscn"
const MINE_SCRIPT := preload("res://Scripts/Battle/mine.gd")
const RICOCHET_TEXT_CD := 1.2
const GHOST_TEXT_CD := 1.5
const TRAP_SPACING := 46.0

var e: Effects
var troop: Node

# △
var roulette_done: bool = false
var _roulette_t: float = 0.0
var streak: int = 0
var _ricochet_txt: float = 0.0
var _ghost_txt: float = 0.0
## Disparo especial en curso: "" · "revenge" (Venganza) · "fate" (Gatillo del destino)
var pending_shot: String = ""
# □
var _imag_done: bool = false
var guarded: Node = null
var rally_pool: float = 0.0       # daño guardado (Ojo por ojo)
var _rally_left: float = 0.0
var _rally_started: bool = false
var _resist: Dictionary = {}      # instance_id del enemigo -> puntos de reducción (El problema es matarme)
# S
var dodge_stack: float = 0.0      # Esquive
var _enemy_dodge: Dictionary = {} # instance_id -> puntos de evasión (No me pillas dos veces)
var _swap_used: bool = false
var _panic_used: bool = false
var _ghost_dodges: int = 0
# ○
var _feign_used: bool = false
var _desperate_used: bool = false
var _butterfly_done: bool = false
# tanda 2
var duelist: Node = null          # Duelo al sol
var sandbags: int = 0             # Trinchera
var inertia: float = 0.0          # Inercia (puntos de evasión)
var _tracer_n: int = 0            # Balas trazadoras
var _baits: int = 0               # Cebo explosivo


func _init(effects: Effects, t: Node) -> void:
	e = effects
	troop = t


func has(id: String) -> bool:
	return e.has(id)


func p(id: String, key: String, def: float) -> float:
	return e.p(id, key, def)


func _alive(n) -> bool:
	return is_instance_valid(n) and not n.is_queued_for_deletion() and not n.is_dead


## Aliados de verdad (sin señuelos ni resucitados).
func _real_allies(include_self: bool = false) -> Array:
	var out: Array = []
	for a in e._allies(include_self):
		if not a.has_meta("summon"):
			out.append(a)
	return out


func _enemies() -> Array:
	var out: Array = []
	for t in troop.get_tree().get_nodes_in_group("troops"):
		if _alive(t) and "team" in t and t.team != troop.team and not t.has_meta("is_drag_preview"):
			out.append(t)
	return out


func _fx() -> Node:
	return troop._fx_parent()


# ================================================================ inicio y proceso

func on_fight_start() -> void:
	if has("carne_canon"):
		_link_guard()
	if has("trampas"):
		_place_traps()
	if has("cable_trampa"):
		_place_tripwire()
	if has("senuelo"):
		_place_decoy()
	if has("pildora"):
		_take_pill()
	if has("segunda_piel"):
		troop.shield = p("segunda_piel", "start", 15.0)
		troop.update_health_bar()


func on_process(delta: float) -> void:
	_ricochet_txt -= delta
	_ghost_txt -= delta
	if _rally_left > 0.0:
		_rally_left -= delta
	if has("trinchera"):
		if troop.is_moving:
			if sandbags > 0:
				sandbags = 0
				troop.queue_redraw()
		elif sandbags < int(p("trinchera", "stacks", 3.0)) and troop.still_time >= p("trinchera", "every", 1.5) * (sandbags + 1):
			sandbags += 1
			troop.queue_redraw()
	if has("inercia"):
		if troop.is_moving:
			inertia = minf(p("inercia", "cap", 25.0), inertia + p("inercia", "gain", 10.0) * delta)
		else:
			inertia = maxf(0.0, inertia - p("inercia", "decay", 15.0) * delta)
	if duelist != null and not _alive(duelist):
		duelist = null
	if has("ruleta_rusa") and not roulette_done:
		_roulette_t += delta
		if _roulette_t >= p("ruleta_rusa", "delay", 3.0) and not troop.is_busy():
			var tgt := _most_dangerous_in_range()
			if tgt != null:
				roulette_done = true
				_play_roulette(tgt)


# ================================================================ disparo propio

## Bonos para el disparo que va a salir (se suman a los de Effects.on_before_shot).
func before_shot(b: Dictionary) -> void:
	if has("todo_al_rojo") and streak > 0:
		b.damage_pct += streak * p("todo_al_rojo", "per_hit", 6.0) / TroopStats.PTS
	if pending_shot == "revenge":
		b.damage_pct += p("venganza_tiro", "damage_pct", 0.5)
	var w: WeaponData = troop.get_active_weapon()
	var mag: int = int(troop.stats.get("magazine", 0))
	if has("gatillo_destino") and mag >= 3 and troop.ammo == 1:
		pending_shot = "fate"
		b["sure_hit"] = true
		b["dodge_ignore"] = p("gatillo_destino", "dodge_ignore", 0.5)
		b["golden"] = true
		if randf() < p("gatillo_destino", "kill_chance", 0.1):
			b["lethal"] = true
		troop.show_text("🎯 Gatillo del destino", Color(1.0, 0.85, 0.3), 11, -8.0)
	if has("municion_fantasma") and w != null and mag <= 0 and w.projectile == WeaponData.Projectile.NINGUNO:
		if randf() < p("municion_fantasma", "knife_chance", 0.05):
			b["lethal"] = true
	if troop.panic_left > 0.0:
		b.accuracy += p("panico_util", "accuracy", -12.0) / TroopStats.PTS
	if has("fondo_cargador") and mag >= 3 and troop.ammo <= ceili(mag / 3.0):
		b.damage_pct += p("fondo_cargador", "damage", 25.0) / TroopStats.PTS
	if has("duelo_sol") and _alive(duelist):
		b.damage_pct += (p("duelo_sol", "vs", 30.0) if troop.target == duelist else p("duelo_sol", "others", -10.0)) / TroopStats.PTS
	if has("trazadoras") and w != null and w.projectile == WeaponData.Projectile.BALA:
		_tracer_n += 1
		if _tracer_n % int(p("trazadoras", "every", 4.0)) == 0:
			b["tracer"] = true


## Resultado del disparo: `hit` = algún perdigón acertó (de entrada; las balas desviadas no cuentan).
func after_shot(hit: bool) -> void:
	if has("todo_al_rojo"):
		if hit:
			streak += 1
			if streak >= 5 and streak % 5 == 0:
				troop.show_text("🔥 ×%d" % streak, Color(1.0, 0.45, 0.2), 12, -6.0)
		else:
			if streak >= 4:
				troop.show_text("❄ Racha perdida", Color(0.7, 0.85, 1.0), 10, -6.0)
			streak = 0
	if pending_shot == "revenge" and hit:
		var got: float = troop.card.add_skill_health("venganza", p("venganza_tiro", "hp_gain", 5.0), p("venganza_tiro", "hp_cap", 50.0))
		if got > 0.0:
			troop.add_live_max_health(got)
			troop.show_text("😡 +%d de vida máx." % roundi(got), Color(1.0, 0.5, 0.4), 11, -18.0)
	pending_shot = ""


## true = este disparo no gasta bala (Munición fantasma).
func skip_ammo() -> bool:
	if has("municion_fantasma") and randf() < p("municion_fantasma", "chance", 0.1):
		if _ghost_txt <= 0.0:
			_ghost_txt = GHOST_TEXT_CD
			troop.show_text("✨ Bala fantasma", Color(0.8, 0.9, 1.0), 10, 4.0)
		return true
	return false


## Un impacto suyo llegó a `victim`.
func on_hit(victim: Node, info: Dictionary) -> void:
	if info.get("tracer", false) and _alive(victim) and not info.get("friendly_fire", false):
		victim.marked_left = maxf(victim.marked_left, p("trazadoras", "mark", 2.5))
		victim.marked_bonus = maxf(victim.marked_bonus, p("trazadoras", "bonus", 10.0) / TroopStats.PTS)
		victim.queue_redraw()
	if has("bala_rebote") and info.get("bullet", false) and not info.get("ricochet", false) \
			and not info.get("friendly_fire", false) and randf() < p("bala_rebote", "chance", 0.1):
		_ricochet(victim, info)


func on_kill(victim: Node) -> void:
	if has("cadena_polvora") and is_instance_valid(victim):
		_powder_fuse(victim)
	if has("ojo_por_ojo") and rally_pool > 0.0:
		var amount := rally_pool * p("ojo_por_ojo", "heal", 0.5)
		rally_pool = 0.0
		_rally_started = false
		_rally_left = 0.0
		var healed: float = troop.heal(amount * e._heal_mult(), false)
		if healed > 0.5:
			troop.show_text("💢 +%d" % roundi(healed), Color(1.0, 0.55, 0.45), 13, -10.0)
		troop.update_health_bar()


# ================================================================ impactos recibidos

## Evasión extra (fracción 0..1) contra `attacker`.
func dodge_bonus(attacker) -> float:
	var pts := dodge_stack + inertia
	if is_instance_valid(attacker):
		pts += float(_enemy_dodge.get(attacker.get_instance_id(), 0.0))
	return pts / TroopStats.PTS


## Multiplicador del daño que le llega de `attacker` (El problema es matarme).
func incoming_mult(attacker) -> float:
	var m := 1.0 - sandbags * p("trinchera", "per_stack", 7.0) / TroopStats.PTS
	if not has("problema_matarme") or not is_instance_valid(attacker):
		return m
	return m * (1.0 - float(_resist.get(attacker.get_instance_id(), 0.0)) / TroopStats.PTS)


func on_dodged(_attacker) -> void:
	if has("esquive"):
		var cap := p("esquive", "cap", 30.0)
		if dodge_stack < cap:
			dodge_stack = minf(cap, dodge_stack + p("esquive", "per_dodge", 10.0))
			troop.show_text("💨 +%d" % roundi(dodge_stack + float(troop.stats.get("modifiers", {}).get("dodge", 0.0))), Color(0.5, 0.9, 1.0), 10, 6.0)
	if has("paso_fantasma"):
		_ghost_dodges += 1
		if _ghost_dodges >= int(p("paso_fantasma", "dodges", 3.0)):
			_ghost_dodges = 0
			troop.ghost_step(p("paso_fantasma", "vanish", 1.0))


## Un enemigo le hizo daño y sigue vivo.
func on_hit_taken(attacker, info: Dictionary) -> void:
	if not is_instance_valid(attacker) or info.get("friendly_fire", false):
		return
	var id: int = attacker.get_instance_id()
	if has("duelo_sol") and not _alive(duelist) and not attacker.has_meta("summon"):
		duelist = attacker
		attacker.show_text("🤠 ¡Duelo!", Color(1.0, 0.8, 0.4), 12, -6.0)
		troop.target = attacker
	if has("no_me_pillas"):
		_enemy_dodge[id] = minf(p("no_me_pillas", "cap", 30.0), float(_enemy_dodge.get(id, 0.0)) + p("no_me_pillas", "per_hit", 5.0))
	if has("problema_matarme"):
		var before := float(_resist.get(id, 0.0))
		_resist[id] = minf(p("problema_matarme", "cap", 40.0), before + p("problema_matarme", "per_stack", 4.0))
		if before == 0.0:
			attacker.show_text("🧱", Color(0.85, 0.75, 0.6), 12, 0.0)
	if has("imaginate_yo") and not _imag_done and String(info.get("weapon_id", "")) != "":
		var mine: WeaponData = troop.get_active_weapon()
		if mine != null and mine.id == String(info.weapon_id):
			_imag_done = true
			var got: float = troop.card.add_skill_health("imaginate_yo", p("imaginate_yo", "hp_gain", 3.0))
			troop.add_live_max_health(got)
			troop.show_text("😏 ¿Eso es todo? +%d de vida máx." % roundi(got), Color(1.0, 0.85, 0.5), 10, -18.0)


## Después de cualquier daño a la vida (impactos, veneno…), si sigue en pie.
func on_damaged(amount: float) -> void:
	if has("ojo_por_ojo"):
		if not _rally_started:
			_rally_started = true
			_rally_left = p("ojo_por_ojo", "window", 3.0)
		elif _rally_left > 0.0:
			rally_pool += amount
		troop.update_health_bar()
	var ratio: float = troop.health / maxf(1.0, troop.get_max_health())
	if has("panico_util") and not _panic_used and ratio < p("panico_util", "threshold", 0.2):
		_panic_used = true
		var d := p("panico_util", "duration", 3.5)
		troop.start_panic(d)
		troop.add_buff("panico_dodge", "dodge", p("panico_util", "dodge", 35.0), d)
		troop.add_buff("panico_mov", "move_speed", p("panico_util", "speed", 25.0), d)
	if has("hacerse_muerto") and not _feign_used and ratio < p("hacerse_muerto", "threshold", 0.1):
		_feign_used = true
		if randf() < p("hacerse_muerto", "chance", 0.6):
			troop.feign_death(p("hacerse_muerto", "duration", 3.0))


## Un golpe de `amount` lo iba a matar. true = lo evita (Cambio de sitio).
func on_would_die(amount: float) -> bool:
	if not has("cambio_sitio") or _swap_used:
		return false
	var best: Node = null
	var bd := INF
	for a in _real_allies(false):
		var d: float = a.global_position.distance_to(troop.global_position)
		if d < bd:
			bd = d
			best = a
	if best == null:
		return false
	_swap_used = true
	var mine: Vector2 = troop.global_position
	var theirs: Vector2 = best.global_position
	CombatFX.flash(_fx(), mine, Color(0.6, 0.9, 1.0, 0.7), 26.0, 0.3)
	CombatFX.flash(_fx(), theirs, Color(0.6, 0.9, 1.0, 0.7), 26.0, 0.3)
	troop.global_position = theirs
	best.global_position = mine
	troop.show_text("🔀 ¡Cambio de sitio!", Color(0.6, 0.9, 1.0), 12, -12.0)
	best.take_damage(amount * p("cambio_sitio", "share", 0.5))
	return true


# ================================================================ muertes

## Esta tropa muere; `killer` = quien le dio el último golpe (puede ser null). `overkill` = daño sobrante.
func on_death(killer, overkill: float) -> void:
	if has("ni_muerto") and _alive(killer) and killer.team != troop.team and not killer.has_meta("summon"):
		killer.doom(p("ni_muerto", "delay", 5.0), p("ni_muerto", "boss_pct", 0.5))
	if has("te_llevas_parte"):
		var allies := _real_allies(false)
		if not allies.is_empty():
			var mh: float = troop.get_max_health()
			var total: float = mh * p("te_llevas_parte", "pct", 0.4) + minf(maxf(0.0, overkill), mh * p("te_llevas_parte", "overkill_cap", 0.4))
			var each: float = total * e._heal_mult() / allies.size()
			for a in allies:
				SkillFX.heal_orb(_fx(), troop.global_position, a, each)
			troop.show_text("💚 Te llevas parte de mí", Color(0.5, 1.0, 0.6), 11, -16.0)


## Cayó un aliado (de verdad, no un señuelo).
func on_ally_died(ally: Node) -> void:
	if has("venganza_tiro"):
		var k = ally.get("last_attacker")
		if _alive(k) and k.team != troop.team:
			pending_shot = "revenge"
			if not troop.instant_shot(k, "😡 ¡Venganza!"):
				pending_shot = ""
	if has("deuda_sangre"):
		var killer = ally.get("last_attacker")
		if _alive(killer) and killer.team != troop.team and not killer.has_meta("summon") \
				and not (killer.card != null and killer.card.is_boss):
			killer.set_meta("blood_debt", troop)
			killer.show_text("🩸 En deuda", Color(0.95, 0.25, 0.25), 11, 8.0)
			killer.queue_redraw()


## Murió cualquier tropa de verdad (de los dos bandos).
func on_unit_died(dead: Node) -> void:
	if has("efecto_mariposa") and not _butterfly_done:
		_butterfly_done = true
		_butterfly()
	if dead.team == troop.team:
		return
	if has("deuda_sangre") and dead.has_meta("blood_debt") and dead.get_meta("blood_debt") == troop:
		_raise_thrall(dead)
	if has("robo_cargador") and int(troop.stats.get("magazine", 0)) > 0 and not troop.is_busy() \
			and troop.steal_left <= 0.0 and int(dead.get("ammo")) > 0 \
			and dead.global_position.distance_to(troop.global_position) <= p("robo_cargador", "radius", 220.0) \
			and randf() < p("robo_cargador", "chance", 0.3):
		troop.go_steal(dead.global_position, int(dead.ammo), p("robo_cargador", "timeout", 3.0))


# ================================================================ recarga

## Modifica la recarga que empieza: {time, ammo} (ammo -1 = cargador completo).
func on_reload_start(base_time: float) -> Dictionary:
	var out := {"time": base_time, "ammo": -1}
	if has("cebo_explosivo") and _baits < int(p("cebo_explosivo", "count", 2.0)):
		_baits += 1
		_drop_bait()
	var rolls := 2 if has("doble_recarga") else 1
	var mag: int = int(troop.stats.get("magazine", 0))
	if has("recarga_desesperada") and not _desperate_used and mag > 0 \
			and troop.health < troop.get_max_health() * p("recarga_desesperada", "threshold", 0.25):
		_desperate_used = true
		var n := 0
		for _i in rolls:
			n = maxi(n, randi_range(1, mag))
		out.time = 0.05
		out.ammo = n
		troop.show_text("🎰 ¡Recarga desesperada! %d/%d" % [n, mag], Color(1.0, 0.8, 0.3), 11, -10.0)
		return out
	if has("cargador_veloz"):
		for _i in rolls:
			if randf() < p("cargador_veloz", "chance", 0.35):
				out.time = 0.1
				troop.show_text("⚡ ¡Recarga veloz!", Color(1.0, 0.95, 0.4), 11, -10.0)
				return out
	if has("doble_recarga"):
		var lo := p("doble_recarga", "min", 0.6)
		var hi := p("doble_recarga", "max", 1.2)
		out.time = base_time * minf(randf_range(lo, hi), randf_range(lo, hi))
	return out


# ================================================================ △ mecánicas

func _most_dangerous_in_range() -> Node:
	var best: Node = null
	var bv := -1.0
	var r: float = troop.get_attack_range() + 60.0
	for t in _enemies():
		if not troop._is_valid_target(t) or t.global_position.distance_to(troop.global_position) > r:
			continue
		var v: float = t.threat_value()
		if v > bv:
			bv = v
			best = t
	return best


## Ruleta rusa: 1 bala en 6 recámaras, turnos alternos (él, enemigo, él…). Tarda unos segundos y mientras
## tanto no se mueve ni dispara. La bala sale en la recámara k (al azar): par = él, impar = el enemigo.
func _play_roulette(enemy: Node) -> void:
	var pull := p("ruleta_rusa", "pull_time", 0.32)
	var k := randi() % 6
	troop.hold_action(pull * (k + 1) + 0.7)
	troop.show_text("🎲 Ruleta rusa…", Color(1.0, 0.85, 0.4), 12, -14.0)
	var drum := SkillFX.RouletteDrum.new()
	drum.shooter = troop
	drum.enemy = enemy
	_fx().add_child(drum)
	var tree: SceneTree = troop.get_tree()
	var st := {"enemy": enemy}   # compartido entre los temporizadores (las lambdas copian las variables)
	for i in k + 1:
		tree.create_timer(pull * (i + 0.5), false).timeout.connect(func() -> void:
			if not is_instance_valid(drum) or not _alive(troop):
				return
			var at_self := i % 2 == 0
			if not at_self and not _alive(st.enemy):
				st.enemy = _most_dangerous_in_range()
				drum.enemy = st.enemy
			drum.set_step(i, at_self)
			if not at_self and _alive(st.enemy):
				troop.target = st.enemy
			if i < k:
				var who: Node2D = troop if at_self or not _alive(st.enemy) else st.enemy
				CombatFX.text(_fx(), who.global_position + Vector2(0, -who.overlay_top() - 16), "clic", Color(0.8, 0.8, 0.8), 11, 0.45)
			else:
				drum.bang()
				_roulette_bang(at_self, st.enemy))
	tree.create_timer(pull * (k + 1) + 0.9, false).timeout.connect(func() -> void:
		if is_instance_valid(drum):
			drum.queue_free())


func _roulette_bang(at_self: bool, enemy: Node) -> void:
	if troop.rig:
		troop.rig.fire()
	if at_self or not _alive(enemy):
		troop.show_text("💥 ¡BANG!", Color(1.0, 0.3, 0.2), 16, -20.0)
		CombatFX.flash(_fx(), troop.global_position + Vector2(0, -troop.overlay_top() * 0.6), Color(1, 0.9, 0.6, 0.9), 18.0, 0.2)
		troop.last_attacker = null
		troop.take_damage(troop.health + 1.0, true)
		return
	var from: Vector2 = troop.rig.muzzle_global() if troop.rig else troop.global_position
	troop.spawn_bullet(from, enemy, {"golden": true}, true)
	enemy.show_text("💥 ¡BANG!", Color(1.0, 0.3, 0.2), 16, -20.0)
	var boss: bool = enemy.card != null and enemy.card.is_boss
	var dmg: float = enemy.get_max_health() * p("ruleta_rusa", "boss_pct", 0.35) if boss else enemy.health + 1.0
	enemy.last_attacker = troop
	var killed: bool = enemy.take_damage(dmg, true)
	troop.on_hit_landed(enemy, {"damage": dmg, "roulette": true}, killed)


## Bala de rebote: sale del blanco hacia otro enemigo cercano (siempre acierta, no vuelve a rebotar).
func _ricochet(victim: Node, info: Dictionary) -> void:
	if not is_instance_valid(victim):
		return
	var from: Vector2 = victim.global_position
	var best: Node = null
	var bd := p("bala_rebote", "radius", 170.0)
	for t in _enemies():
		if t == victim or not troop._is_valid_target(t):
			continue
		var d: float = t.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = t
	if best == null:
		return
	var ri := info.duplicate()
	ri["ricochet"] = true
	ri["lethal"] = false
	ri["damage"] = float(info.get("damage", 0.0)) * p("bala_rebote", "damage", 1.0)
	troop.spawn_bullet(from + from.direction_to(best.global_position) * 10.0, best, ri)
	if _ricochet_txt <= 0.0:
		_ricochet_txt = RICOCHET_TEXT_CD
		CombatFX.text(_fx(), from + Vector2(0, -30), "↪ ¡Rebote!", Color(1.0, 0.9, 0.5), 11, 0.5)


## Cadena de pólvora: mecha sobre el cuerpo y explosión al poco. Si mata, el nuevo cuerpo también explota.
func _powder_fuse(victim: Node) -> void:
	var pos: Vector2 = victim.global_position
	var mh: float = victim.get_max_health()
	var dmg := minf(p("cadena_polvora", "base", 18.0) + mh * p("cadena_polvora", "hp_pct", 0.12), p("cadena_polvora", "cap", 70.0))
	var radius := p("cadena_polvora", "radius", 75.0)
	var delay := p("cadena_polvora", "delay", 0.6)
	var parent := _fx()
	var tree: SceneTree = troop.get_tree()
	var team: int = troop.team
	var att = troop
	SkillFX.fuse(parent, pos, delay)
	tree.create_timer(delay, false).timeout.connect(func() -> void:
		if not is_instance_valid(parent):
			return
		CombatFX.explosion(parent, pos, radius)
		CombatFX.text(parent, pos + Vector2(0, -26), "🧨", Color(1.0, 0.6, 0.2), 14, 0.5)
		for en in CombatFX.enemies_in_radius(tree, pos, radius, team):
			if en.has_meta("summon"):
				continue
			var f := clampf(en.global_position.distance_to(pos) / radius, 0.0, 1.0)
			CombatFX.apply_hit(en, {"damage": dmg * lerpf(1.0, 0.4, f), "lethal": false, "powder": true,
					"attacker": att if is_instance_valid(att) and not att.is_dead else null}))


## Deuda de sangre: el enemigo en deuda se levanta de nuestro lado y pelea a puñetazos un rato.
func _raise_thrall(dead: Node) -> void:
	var pos: Vector2 = dead.global_position
	var src: TroopCard = dead.card
	if src == null:
		return
	var parent := _fx()
	var holder = troop
	var tree: SceneTree = troop.get_tree()
	tree.create_timer(0.9, false).timeout.connect(func() -> void:
		if not is_instance_valid(parent) or not is_instance_valid(holder):
			return
		var c := src.duplicate_card()
		c.skills.clear()
		c.items.clear()
		c.ammo = null
		c.specialty = null
		c.is_boss = false
		c.is_enemy = false
		var fists := WeaponData.new()
		fists.id = "punos"
		fists.display_name = "Puños"
		fists.family = WeaponData.Family.CUERPO_A_CUERPO
		fists.projectile = WeaponData.Projectile.NINGUNO
		fists.damage = p("deuda_sangre", "punch_damage", 6.0) # × su propio daño (escala con la ronda)
		fists.fire_rate = p("deuda_sangre", "punch_rate", 1.2)
		fists.attack_range = 42.0
		fists.optimal_range = 42.0
		fists.accuracy = 0.9
		fists.magazine = 0
		fists.fire_on_move = true
		fists.move_speed_mult = 1.15
		c.weapons = [fists]
		c.equipped_weapon = 0
		var t = load(TROOP_SCENE_PATH).instantiate()
		t.set_meta("summon", true)
		t.set_meta("thrall_binder", holder)
		t.team = holder.team
		t.card = c
		parent.add_child(t)
		t.global_position = pos
		t.start_as_summon(p("deuda_sangre", "duration", 10.0), p("deuda_sangre", "hp_pct", 0.5))
		t.show_text("🩸 ¡Se levanta!", Color(0.9, 0.3, 0.35), 13, -10.0)
		CombatFX.flash(parent, pos, Color(0.8, 0.15, 0.2, 0.6), 30.0, 0.5))


# ================================================================ □ mecánicas

## Carne de cañón: se une al aliado con menos vida máxima (el más frágil).
func _link_guard() -> void:
	var best: Node = null
	var bh := INF
	for a in _real_allies(false):
		if a.has_meta("guardian"):
			continue
		var mh: float = a.get_max_health()
		if mh < bh:
			bh = mh
			best = a
	if best == null:
		return
	guarded = best
	best.set_meta("guardian", troop)
	best.set_meta("guardian_share", p("carne_canon", "share", 0.3))
	troop.queue_redraw()


# ================================================================ ○ mecánicas

func _lane_x() -> float:
	return troop.field_rect(troop.get_tree()).get_center().x


func _place_traps() -> void:
	var w := [p("trampas", "w0", 50.0), p("trampas", "w1", 35.0), p("trampas", "w2", 15.0)]
	var n: int = maxi(0, LevelUpSystem.weighted_index(w, _rng()))
	if n == 0:
		troop.show_text("🪤 Sin trampas…", Color(0.75, 0.75, 0.75), 10, 6.0)
		return
	troop.show_text("🪤 ×%d" % n, Color(1.0, 0.75, 0.4), 11, 6.0)
	var mid := _lane_x()
	for i in n:
		var m = MINE_SCRIPT.new()
		m.trap_mode = true
		m.team = troop.team
		m.owner_troop = troop
		m.damage = p("trampas", "damage", 20.0) * float(troop.stats.get("damage_mult", 1.0))
		m.root_time = p("trampas", "root", 2.0)
		m.trigger_radius = 26.0
		m.visible_to_player = troop.team == 0
		var off_y := (float(i) - (n - 1) * 0.5) * TRAP_SPACING
		m.position = Vector2(mid + (i - (n - 1) * 0.5) * 30.0, troop.global_position.y + off_y + 18.0)
		_fx().add_child(m)


func _place_tripwire() -> void:
	var w := SkillFX.Tripwire.new()
	w.team = troop.team
	w.owner_troop = troop
	w.stun = p("cable_trampa", "stun", 1.5)
	w.downed = p("cable_trampa", "downed", 4.0)
	w.lethal = p("cable_trampa", "lethal", 0.08)
	w.visible_to_player = troop.team == 0
	_fx().add_child(w)
	var x: float = _lane_x() - troop.back_dir() * 40.0
	w.global_position = Vector2(x, troop.global_position.y + 18.0)


func _place_decoy() -> void:
	var c: TroopCard = troop.card.duplicate_card()
	c.skills.clear()
	c.items.clear()
	c.unit_name = "Señuelo"
	var t = load(TROOP_SCENE_PATH).instantiate()
	t.set_meta("summon", true)
	t.set_meta("decoy_hits", int(p("senuelo", "hits", 6.0)))
	t.set_meta("decoy_max", int(p("senuelo", "hits", 6.0)))
	t.team = troop.team
	t.card = c
	t.ai_enabled = false
	_fx().add_child(t)
	var f: Rect2 = troop.field_rect(troop.get_tree())
	var pos: Vector2 = troop.global_position + Vector2(-troop.back_dir() * 75.0, randf_range(-20.0, 20.0))
	pos.x = clampf(pos.x, f.position.x + 10.0, f.end.x - 10.0)
	pos.y = clampf(pos.y, f.position.y + 10.0, f.end.y - 10.0)
	t.global_position = pos
	t.start_as_summon(0.0, 1.0)
	CombatFX.flash(_fx(), pos, Color(0.95, 0.85, 0.55, 0.6), 22.0, 0.3)


func _take_pill() -> void:
	var d := p("pildora", "duration", 6.0)
	troop.add_buff("pildora_mov", "move_speed", p("pildora", "speed", 45.0), d)
	troop.add_buff("pildora_dodge", "dodge", p("pildora", "dodge", 30.0), d)
	troop.apply_poison(troop.get_max_health() * p("pildora", "poison_pct", 0.3), p("pildora", "poison_time", 10.0), true)
	troop.show_text("💊 ¡Píldora!", Color(1.0, 0.45, 0.45), 12, -6.0)


## Efecto mariposa: cada aliado recibe un resultado al azar.
func _butterfly() -> void:
	for a in _real_allies(true):
		var r := randi() % 5
		match r:
			0:
				a.show_text("🦋 …nada", Color(0.75, 0.75, 0.8), 10, -2.0)
			1:
				a.heal(p("efecto_mariposa", "health", 30.0), false)
				a.show_text("🦋 +%d vida" % roundi(p("efecto_mariposa", "health", 30.0)), Color(0.5, 1.0, 0.6), 10, -2.0)
			2:
				var mag: int = int(a.stats.get("magazine", 0))
				if mag > 0:
					var extra: int = ceili(mag * p("efecto_mariposa", "ammo_pct", 0.25))
					a.ammo += extra
					a.weapon_ammo[a.active_weapon] = a.ammo
					a.reloading = false
					a._update_reload_bar()
					a.show_text("🦋 +%d balas" % extra, Color(1.0, 0.9, 0.5), 10, -2.0)
				else:
					a.heal(p("efecto_mariposa", "health", 30.0), false)
					a.show_text("🦋 +%d vida" % roundi(p("efecto_mariposa", "health", 30.0)), Color(0.5, 1.0, 0.6), 10, -2.0)
			3:
				a.camo_left = maxf(a.camo_left, p("efecto_mariposa", "invis", 2.0))
				a.update_visuals()
				a.show_text("🦋 ¡Invisible!", Color(0.75, 0.85, 1.0), 10, -2.0)
			4:
				var d := p("efecto_mariposa", "rush", 4.0)
				var v := p("efecto_mariposa", "rush_value", 40.0)
				a.add_buff("mariposa_mov", "move_speed", v, d)
				a.add_buff("mariposa_dodge", "dodge", v, d)
				a.show_text("🦋 ¡Velocidad!", Color(0.5, 0.9, 1.0), 10, -2.0)
		CombatFX.flash(_fx(), a.global_position, Color(0.85, 0.6, 1.0, 0.45), 20.0, 0.35)


static var _rng_inst: RandomNumberGenerator = null

static func _rng() -> RandomNumberGenerator:
	if _rng_inst == null:
		_rng_inst = RandomNumberGenerator.new()
		_rng_inst.randomize()
	return _rng_inst



# ================================================================ tanda 2

## Curación que sobra con la vida llena (Segunda piel: se vuelve escudo).
func on_overheal(excess: float) -> void:
	if has("segunda_piel") and excess > 0.0:
		troop.shield = minf(p("segunda_piel", "cap", 40.0), troop.shield + excess)
		troop.update_health_bar()


## Retirada táctica: al vaciar el cargador salta hacia atrás y recarga con más evasión.
func on_magazine_empty() -> void:
	if not has("retirada_tactica") or int(troop.stats.get("magazine", 0)) < 3 or troop.is_busy():
		return
	var near: Node = null
	var bd := INF
	for t in _enemies():
		var d: float = t.global_position.distance_to(troop.global_position)
		if d < bd:
			bd = d
			near = t
	var dir := Vector2(troop.back_dir(), 0.0)
	if near != null:
		dir = (troop.global_position - near.global_position).normalized()
	var f: Rect2 = troop.field_rect(troop.get_tree())
	var to: Vector2 = troop.global_position + dir * p("retirada_tactica", "jump", 70.0)
	to.x = clampf(to.x, f.position.x + 8.0, f.end.x - 8.0)
	to.y = clampf(to.y, f.position.y + 8.0, f.end.y - 8.0)
	troop.add_buff("retirada_dodge", "dodge", p("retirada_tactica", "dodge", 25.0), float(troop.stats.get("reload_time", 2.0)) + 0.4)
	troop.hop_to(to)


func _drop_bait() -> void:
	var m = MINE_SCRIPT.new()
	m.team = troop.team
	m.owner_troop = troop
	m.damage = p("cebo_explosivo", "damage", 25.0) * float(troop.stats.get("damage_mult", 1.0))
	m.radius = p("cebo_explosivo", "radius", 60.0)
	m.trigger_radius = 28.0
	m.visible_to_player = troop.team == 0
	m.position = troop.global_position + Vector2(0, 20)
	_fx().add_child(m)
	troop.show_text("🎁", Color(1.0, 0.7, 0.4), 12, 4.0)
