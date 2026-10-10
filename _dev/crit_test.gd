extends Node2D
## Comprobaciones de que ya no existe el golpe crítico y de que el impacto letal sigue funcionando.

const TROOP := preload("res://Scenes/Troops/troop.tscn")

func _ready() -> void:
	var ok := true
	# 1) Ninguna estadística, clave de modificador ni recurso habla de crítico
	var c: TroopCard = UnitFactory.make_recruit()
	var s := TroopStats.compute(c)
	var bad: Array = []
	for k in s.keys():
		if "crit" in String(k):
			bad.append(k)
	ok = _check("compute sin claves de crítico", bad.is_empty()) and ok
	ok = _check("MODIFIER_KEYS sin crítico", not ("crit_chance" in TroopStats.MODIFIER_KEYS) and not ("crit_mult" in TroopStats.MODIFIER_KEYS)) and ok
	var w_bad := false
	for w in GameContent.weapons():
		for p in w.get_property_list():
			if "crit" in String(p.name):
				w_bad = true
	ok = _check("WeaponData sin crítico", not w_bad) and ok
	var m_bad := false
	for list in [GameContent.skills(), GameContent.items(), GameContent.specialties()]:
		for r in list:
			var txt := str(r.get("modifiers")) + str(r.get("passive_params")) + str(r.get("extra_effects")) \
					+ str(r.get("description")) + str(r.get("passive_description")) + str(r.get("synergy_text"))
			if "crit" in txt or "crít" in txt.to_lower():
				m_bad = true
				print("    con crítico: ", r.get("id"))
	ok = _check("habilidades/objetos/especialidades sin crítico", not m_bad) and ok
	# 2) Combate: impacto normal = daño exacto; impacto letal mata de un disparo
	var a = _spawn(UnitFactory.make_recruit(), Vector2(200, 300), 0)
	var d = _spawn(UnitFactory.make_recruit(), Vector2(330, 300), 1)
	d.ai_enabled = false
	a.ai_enabled = false
	await get_tree().process_frame
	d.force_dodge = 0
	var hp0: float = d.health
	d.receive_hit({"damage": 5.0, "lethal": false, "attacker": a})
	ok = _check("impacto normal hace su daño (sin multiplicador)", is_equal_approx(hp0 - d.health, 5.0 * (1.0 - float(d.stats.armor)))) and ok
	var info: Dictionary = a._hit_info(10.0, a.stats.weapon, false)
	ok = _check("_hit_info sin crit/headshot", not info.has("crit") and not info.has("headshot")) and ok
	a.force_hit = 1
	a.force_lethal = 1
	a.target = d
	a.attack()
	await get_tree().create_timer(1.5).timeout
	ok = _check("disparo forzado letal cuenta un letal", a.lethals == 1) and ok
	ok = _check("el impacto letal mata de un disparo", d.is_dead) and ok
	print("CRIT_TEST ", "OK" if ok else "FALLO")


func _spawn(c: TroopCard, p: Vector2, team: int) -> Node:
	var t = TROOP.instantiate()
	t.set_meta("no_snap", true)
	t.team = team
	t.card = c
	add_child(t)
	t.global_position = p
	return t


func _check(name: String, cond: bool) -> bool:
	print(("  ✔ " if cond else "  ✘ ") + name)
	return cond
